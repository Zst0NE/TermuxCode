import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/secure_store.dart';
import '../services/ssh_service.dart';

/// Chat + dual backends: builtin harness OR remote native Claude/Codex/OpenCode.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required SecureStore store,
    required SshService ssh,
    LlmService? llm,
  })  : _store = store,
        _ssh = ssh,
        _llm = llm ?? LlmService() {
    final stack = buildDefaultAgentStack(_ssh, mode: PermissionMode.auto);
    _runtime = AgentRuntime(
      llm: _llm,
      registry: stack.registry,
      gate: stack.gate,
    );
    _remote = RemoteCliSession(_ssh);
    _remoteAgent = RemoteAgentSession(_ssh);
    _mode = AgentMode.auto;
    _runtime.gate.mode = PermissionMode.auto;
  }

  final SecureStore _store;
  final SshService _ssh;
  final LlmService _llm;
  late final AgentRuntime _runtime;
  late final RemoteCliSession _remote;
  late final RemoteAgentSession _remoteAgent;

  final List<ChatMessage> _messages = [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  AgentMode _mode = AgentMode.auto;
  AgentBackend _backend = AgentBackend.builtin;
  Timer? _saveDebounce;
  StreamSubscription<RemoteAgentEvent>? _remoteSub;
  String? _remoteStreamMsgId;

  final Map<String, Completer<bool>> _approvalWaiters = {};
  final Set<String> _resolvedToolCalls = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isBusy => _busy;
  bool get sending => _busy;
  bool get historyLoaded => _loaded;
  String? get error => _error;
  AgentMode get mode => _mode;
  AgentBackend get backend => _backend;
  RemoteCliSession get remoteCli => _remote;
  RemoteAgentSession get remoteAgent => _remoteAgent;

  void setMode(AgentMode mode) {
    if (_mode == mode || _busy) return;
    _mode = mode;
    _runtime.gate.mode = switch (mode) {
      AgentMode.plan => PermissionMode.ask,
      AgentMode.ask => PermissionMode.ask,
      AgentMode.auto => PermissionMode.auto,
      AgentMode.bypass => PermissionMode.bypass,
    };
    notifyListeners();
  }

  void setBackend(AgentBackend backend) {
    if (_backend == backend || _busy) return;
    _backend = backend;
    notifyListeners();
  }

  bool isAwaitingApproval(String id) =>
      _approvalWaiters.containsKey(id) && !_resolvedToolCalls.contains(id);

  Future<void> loadHistory() async {
    if (_loaded) return;
    try {
      final raw = await _store.loadChatHistory();
      _messages
        ..clear()
        ..addAll(raw.map(ChatMessage.fromJson));
    } catch (e) {
      _error = '恢复对话失败: $e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        await _store.saveChatHistory(
          _messages.map((m) => m.toJson()).toList(),
        );
      } catch (_) {}
    });
  }

  /// After SSH connect: detect CLIs and prefer remote native if any found.
  Future<void> onHostConnected() async {
    await _remote.detect();
    if (_remote.hasAny) {
      _backend = AgentBackend.remoteNative;
      // Prefer claude > opencode > codex if present
      for (final k in [
        RemoteCliKind.claude,
        RemoteCliKind.opencode,
        RemoteCliKind.codex,
      ]) {
        if (_remote.available.containsKey(k)) {
          _remote.select(k);
          break;
        }
      }
    } else {
      _backend = AgentBackend.builtin;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _busy) return;
    _error = null;

    final userMsg = ChatMessage(role: ChatRole.user, text: text.trim());
    _messages.add(userMsg);
    _busy = true;
    notifyListeners();
    _scheduleSave();

    try {
      if (!_ssh.isConnected) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '先连接你的远程主机。连上后我会优先使用主机上的 Claude / Codex / OpenCode（若已安装）。',
        ));
        return;
      }

      if (_backend == AgentBackend.remoteNative) {
        await _sendViaRemoteNative(text.trim());
        return;
      }

      // Builtin harness path (BYOK).
      final cfg = await _store.loadLlmConfig();
      final key = (await _store.loadLlmApiKey()) ?? '';
      if (!cfg.isConfigured || key.trim().isEmpty) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '内置 Agent 需要 API Key。也可切换到「远程 Agent」使用主机上的 Claude/Codex/OpenCode。',
        ));
        return;
      }

      await for (final event in _runtime.run(
        userText: text.trim(),
        mode: _mode,
        config: cfg,
        apiKey: key,
        history: [
          for (final m in _messages)
            if (m.id != userMsg.id) m,
        ],
        onApprove: (req) async {
          // Auto/Bypass may still emit ask for non-allowlist; Completer UI.
          final completer = Completer<bool>();
          _approvalWaiters[req.id] = completer;
          notifyListeners();
          return completer.future;
        },
      )) {
        _handleEvent(event, userMsg.text);
      }
    } catch (e) {
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: 'Agent 运行失败：$e',
      ));
      _error = '$e';
    } finally {
      _busy = false;
      _cancelPendingWaiters();
      notifyListeners();
      _scheduleSave();
    }
  }

  Future<void> _sendViaRemoteNative(String text) async {
    if (!_remote.hasAny) {
      await _remote.detect();
    }
    if (!_remote.hasAny || _remote.selected == null) {
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text:
            '主机上未检测到 claude / codex / opencode。\n'
            '请在服务器安装其一，或切换到「内置 Agent」并用 API Key。',
      ));
      return;
    }

    final kind = _remote.selected!;
    // Prefix mode hint for plan-like behavior on remote agents.
    final payload = switch (_mode) {
      AgentMode.plan =>
        '[Plan mode — propose a plan only, do not execute destructive steps]\n$text',
      AgentMode.ask =>
        '[Ask mode — explain before running commands]\n$text',
      AgentMode.auto => text,
      AgentMode.bypass =>
        '[Autonomous mode — proceed carefully]\n$text',
    };

    try {
      if (!_remoteAgent.isRunning || _remoteAgent.kind != kind) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '正在主机上启动 **${kind.label}**（PTY 会话）…',
        ));
        notifyListeners();
        await _remoteSub?.cancel();
        await _remoteAgent.start(kind);
        _remoteSub = _remoteAgent.events.listen(_onRemoteAgentEvent);
        // Give CLI a moment to boot.
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }

      // Streaming bubble
      final streamMsg = ChatMessage(
        role: ChatRole.assistant,
        text: '',
      );
      _remoteStreamMsgId = streamMsg.id;
      _messages.add(streamMsg);
      notifyListeners();

      _remoteAgent.send(payload);

      // Wait until idle gap or timeout (simple turn boundary for PTY agents).
      await _waitRemoteTurnIdle(timeout: const Duration(minutes: 6));
    } catch (e) {
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: '远程 Agent 失败：$e',
      ));
      _error = '$e';
    } finally {
      _remoteStreamMsgId = null;
    }
  }

  void _onRemoteAgentEvent(RemoteAgentEvent e) {
    switch (e) {
      case RemoteAgentText(:final text):
        final id = _remoteStreamMsgId;
        if (id == null) return;
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx < 0) return;
        final prev = _messages[idx];
        _messages[idx] = ChatMessage(
          id: prev.id,
          role: ChatRole.assistant,
          text: '${prev.text}$text',
          createdAt: prev.createdAt,
        );
        notifyListeners();
        _scheduleSave();
      case RemoteAgentStatus(:final message):
        // Soft status as system-like assistant line if no stream yet.
        if (_remoteStreamMsgId == null) {
          _messages.add(ChatMessage(role: ChatRole.assistant, text: '… $message'));
          notifyListeners();
        }
      case RemoteAgentExit():
        _busy = false;
        notifyListeners();
      case RemoteAgentError(:final message):
        _messages.add(ChatMessage(role: ChatRole.assistant, text: '错误：$message'));
        _busy = false;
        notifyListeners();
    }
  }

  /// Heuristic turn end: no new stdout for [quiet] duration.
  Future<void> _waitRemoteTurnIdle({
    required Duration timeout,
    Duration quiet = const Duration(seconds: 4),
  }) async {
    final start = DateTime.now();
    var lastLen = -1;
    var stableSince = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final id = _remoteStreamMsgId;
      final idx = id == null ? -1 : _messages.indexWhere((m) => m.id == id);
      final len = idx >= 0 ? _messages[idx].text.length : 0;
      if (len != lastLen) {
        lastLen = len;
        stableSince = DateTime.now();
      } else if (len > 0 &&
          DateTime.now().difference(stableSince) >= quiet) {
        return;
      }
      if (!_remoteAgent.isRunning) return;
    }
  }

  /// Non-interactive one-shot (legacy /cli).
  Future<void> runRemoteCli(String prompt) async {
    if (prompt.trim().isEmpty || _busy) return;
    if (!_ssh.isConnected) {
      _error = '请先连接 SSH';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    _messages.add(ChatMessage(
      role: ChatRole.user,
      text: '[Remote CLI] ${prompt.trim()}',
    ));
    notifyListeners();
    try {
      if (!_remote.hasAny) await _remote.detect();
      if (!_remote.hasAny) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '远端未检测到 opencode / claude / codex。',
        ));
        return;
      }
      final kind = _remote.selected!;
      final buf = StringBuffer();
      await for (final chunk
          in RemoteCliAdapter(_ssh).runPrompt(kind, prompt.trim())) {
        buf.writeln(chunk);
      }
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: '### ${kind.label}\n\n```\n${buf.toString().trim()}\n```',
      ));
    } catch (e) {
      _error = '$e';
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: 'Remote CLI 失败：$e',
      ));
    } finally {
      _busy = false;
      notifyListeners();
      _scheduleSave();
    }
  }

  void _handleEvent(AgentEvent event, String userText) {
    switch (event) {
      case AgentUserMessage(:final text):
        if (text == userText) return;
        _messages.add(ChatMessage(role: ChatRole.user, text: text));
      case AgentAssistantDelta(:final delta):
        if (_messages.isNotEmpty &&
            _messages.last.role == ChatRole.assistant &&
            !_messages.last.hasToolCalls) {
          final last = _messages.last;
          _messages[_messages.length - 1] = ChatMessage(
            id: last.id,
            role: ChatRole.assistant,
            text: '${last.text}$delta',
            toolCalls: last.toolCalls,
            createdAt: last.createdAt,
          );
        } else {
          _messages.add(ChatMessage(role: ChatRole.assistant, text: delta));
        }
        notifyListeners();
        return;
      case AgentAssistantText(:final text, :final toolCalls):
        if (_messages.isNotEmpty &&
            _messages.last.role == ChatRole.assistant &&
            !_messages.last.hasToolCalls) {
          final last = _messages.last;
          _messages[_messages.length - 1] = ChatMessage(
            id: last.id,
            role: ChatRole.assistant,
            text: text.isNotEmpty ? text : last.text,
            toolCalls: [
              for (final t in toolCalls)
                ToolCall(
                  id: t.id,
                  command: (t.arguments['command'] as String?) ??
                      (t.arguments['path'] as String?) ??
                      t.name,
                  rationale: t.arguments['rationale'] as String?,
                ),
            ],
            createdAt: last.createdAt,
          );
        } else {
          _messages.add(ChatMessage(
            role: ChatRole.assistant,
            text: text,
            toolCalls: [
              for (final t in toolCalls)
                ToolCall(
                  id: t.id,
                  command: (t.arguments['command'] as String?) ??
                      (t.arguments['path'] as String?) ??
                      t.name,
                  rationale: t.arguments['rationale'] as String?,
                ),
            ],
          ));
        }
      case AgentPermissionRequest():
        notifyListeners();
        return;
      case AgentToolFinished(:final result):
        _messages.add(ChatMessage(
          role: ChatRole.tool,
          toolResult: ToolResult(
            toolCallId: result.toolCallId,
            exitCode: result.isError ? 1 : 0,
            stdout: result.isError ? '' : result.content,
            stderr: result.isError ? result.content : '',
            declined: result.content.contains('declined') ||
                result.content.contains('denied'),
            timedOut: result.timedOut,
            truncated: result.truncated,
          ),
        ));
      case AgentTurnDone():
        return;
      case AgentTurnError(:final message):
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '错误：$message',
        ));
        _error = message;
      case AgentModeInfo():
        return;
    }
    notifyListeners();
    _scheduleSave();
  }

  Future<void> approveToolCall(ToolCall call) async {
    if (!_ssh.isConnected) {
      _error = '请先连接远程主机';
      notifyListeners();
      _resolveWaiter(call.id, false);
      return;
    }
    _resolveWaiter(call.id, true);
  }

  void declineToolCall(ToolCall call) {
    _resolveWaiter(call.id, false);
  }

  Future<void> clearMessages() async {
    _cancelPendingWaiters();
    _messages.clear();
    _resolvedToolCalls.clear();
    notifyListeners();
    try {
      await _store.clearChatHistory();
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _remoteSub?.cancel();
    _remoteAgent.dispose();
    _cancelPendingWaiters();
    _llm.dispose();
    super.dispose();
  }

  void _resolveWaiter(String id, bool approved) {
    if (_resolvedToolCalls.contains(id)) return;
    final c = _approvalWaiters.remove(id);
    if (c != null && !c.isCompleted) {
      _resolvedToolCalls.add(id);
      c.complete(approved);
    }
  }

  void _cancelPendingWaiters() {
    for (final entry in _approvalWaiters.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(false);
      }
    }
    _approvalWaiters.clear();
  }
}
