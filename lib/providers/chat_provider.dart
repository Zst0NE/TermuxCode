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
    _todos = stack.todos;
    _memory = ProjectMemory(_ssh);
    _runtime = AgentRuntime(
      llm: _llm,
      registry: stack.registry,
      gate: stack.gate,
      memory: _memory,
      todos: _todos,
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
  late final TodoStore _todos;
  late final ProjectMemory _memory;

  final List<ChatMessage> _messages = [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  AgentMode _mode = AgentMode.auto;
  AgentBackend _backend = AgentBackend.builtin;
  Timer? _saveDebounce;
  StreamSubscription<RemoteAgentEvent>? _remoteSub;
  String? _remoteStreamMsgId;
  Completer<bool>? _remoteSendConfirm;
  String? _pendingRemotePreview;

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
  TodoStore get todos => _todos;
  ProjectMemory get memory => _memory;
  String get hostCwd => _memory.cwd;

  /// Remote Ask-mode: waiting for user to confirm sending to host agent.
  bool get awaitingRemoteSendConfirm =>
      _remoteSendConfirm != null && !(_remoteSendConfirm!.isCompleted);
  String? get pendingRemotePreview => _pendingRemotePreview;

  /// Confirm or cancel a pending remote Ask-mode send.
  void resolveRemoteSendConfirm(bool ok) {
    final c = _remoteSendConfirm;
    if (c == null || c.isCompleted) return;
    c.complete(ok);
    _remoteSendConfirm = null;
    _pendingRemotePreview = null;
    notifyListeners();
  }

  /// Interrupt remote native agent (Ctrl+C).
  void interruptRemoteAgent() {
    _remoteAgent.interrupt();
    _messages.add(ChatMessage(
      role: ChatRole.assistant,
      text: '已向远程 Agent 发送中断（Ctrl+C）。',
    ));
    _busy = false;
    notifyListeners();
  }

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
    await _memory.refresh();
    if (_remote.hasAny) {
      _backend = AgentBackend.remoteNative;
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
      final cfg = await _store.loadLlmConfig();
      final key = (await _store.loadLlmApiKey()) ?? '';
      final hasKey = cfg.isConfigured && key.trim().isNotEmpty;
      final connected = _ssh.isConnected;

      // ── Remote native agent (needs host + CLI) ──────────────────────────
      if (_backend == AgentBackend.remoteNative) {
        if (!connected) {
          _messages.add(ChatMessage(
            role: ChatRole.assistant,
            text:
                '当前是「远程 Agent」模式，需要先连接你的服务器。\n'
                '也可以把右上角后端改成「内置 Agent」，用 API Key 先聊天。',
          ));
          return;
        }
        await _sendViaRemoteNative(text.trim());
        return;
      }

      // ── Builtin agent (BYOK) ────────────────────────────────────────────
      if (!hasKey) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text:
              '请先在「设置」填写 Base URL / 模型 / API Key。\n'
              '若服务器已装 Claude/Codex/OpenCode，可切换到「远程 Agent」。',
        ));
        return;
      }

      // Pure chat without SSH: no tools, just LLM conversation.
      // With SSH: full tool loop (Claude-like).
      final useTools = connected;
      if (!connected) {
        // Soft notice once per turn is enough via assistant reply if tools needed;
        // for pure Q&A we just chat.
      }

      await for (final event in _runtime.run(
        userText: text.trim(),
        mode: useTools ? _mode : AgentMode.plan, // plan still may filter tools
        config: cfg,
        apiKey: key,
        history: [
          for (final m in _messages)
            if (m.id != userMsg.id) m,
        ],
        onApprove: (req) async {
          final completer = Completer<bool>();
          _approvalWaiters[req.id] = completer;
          notifyListeners();
          return completer.future;
        },
        enableTools: useTools,
      )) {
        _handleEvent(event, userMsg.text);
      }

      if (!connected) {
        // If the model still tried tools, runtime won't execute them when
        // enableTools=false; add a tip only if last assistant mentions tools.
      }
    } catch (e, st) {
      debugPrint('sendMessage error: $e\n$st');
      _messages.add(ChatMessage(
        role: ChatRole.assistant,
        text: '对话出错：$e\n\n请检查网络、API Key 与 Base URL。',
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
        '[Ask mode — explain before running commands; wait for confirmation]\n$text',
      AgentMode.auto => text,
      AgentMode.bypass =>
        '[Autonomous mode — proceed carefully]\n$text',
    };

    // Ask mode: user confirms before anything is sent to the host agent.
    if (_mode == AgentMode.ask) {
      _pendingRemotePreview = text;
      _remoteSendConfirm = Completer<bool>();
      notifyListeners();
      final ok = await _remoteSendConfirm!.future;
      _pendingRemotePreview = null;
      _remoteSendConfirm = null;
      if (!ok) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '已取消发送到远程 Agent。',
        ));
        return;
      }
    }

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
        await Future<void>.delayed(const Duration(milliseconds: 1200));
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

      // Wait until idle gap, prompt-like waiting, or timeout.
      await _waitRemoteTurnIdle(timeout: const Duration(minutes: 8));
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
        // Cap bubble size for mobile UI.
        var next = '${prev.text}$text';
        if (next.length > 120000) {
          next = '${next.substring(next.length - 100000)}\n…(截断旧输出)';
        }
        _messages[idx] = ChatMessage(
          id: prev.id,
          role: ChatRole.assistant,
          text: next,
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

  /// Heuristic turn end: quiet period, or agent looks like it's waiting for input.
  Future<void> _waitRemoteTurnIdle({
    required Duration timeout,
    Duration quiet = const Duration(seconds: 4),
    Duration minWait = const Duration(seconds: 2),
  }) async {
    final start = DateTime.now();
    await Future<void>.delayed(minWait);
    var lastLen = _remoteAgent.outputLength;
    var stableSince = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_remoteAgent.isRunning) return;
      final len = _remoteAgent.outputLength;
      if (len != lastLen) {
        lastLen = len;
        stableSince = DateTime.now();
      } else if (len > 0) {
        final idle = DateTime.now().difference(stableSince);
        if (idle >= quiet) return;
        // Prompt-like ending with a shorter quiet window.
        if (idle >= const Duration(seconds: 2) &&
            _remoteAgent.looksLikeWaitingForInput) {
          return;
        }
      }
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
                  name: t.name,
                  command: (t.arguments['command'] as String?) ??
                      (t.arguments['path'] as String?) ??
                      (t.arguments['pattern'] as String?) ??
                      t.name,
                  rationale: t.arguments['rationale'] as String?,
                  arguments: t.arguments,
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
                  name: t.name,
                  command: (t.arguments['command'] as String?) ??
                      (t.arguments['path'] as String?) ??
                      (t.arguments['pattern'] as String?) ??
                      t.name,
                  rationale: t.arguments['rationale'] as String?,
                  arguments: t.arguments,
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
    if (awaitingRemoteSendConfirm) {
      resolveRemoteSendConfirm(false);
    }
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
