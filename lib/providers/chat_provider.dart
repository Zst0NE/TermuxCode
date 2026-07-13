import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/secure_store.dart';
import '../services/ssh_service.dart';

/// Chat + Agent Harness state for the AI screen.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required SecureStore store,
    required SshService ssh,
    LlmService? llm,
  })  : _store = store,
        _ssh = ssh,
        _llm = llm ?? LlmService() {
    final stack = buildDefaultAgentStack(_ssh, mode: PermissionMode.ask);
    _runtime = AgentRuntime(
      llm: _llm,
      registry: stack.registry,
      gate: stack.gate,
    );
  }

  final SecureStore _store;
  final SshService _ssh;
  final LlmService _llm;
  late final AgentRuntime _runtime;

  final List<ChatMessage> _messages = [];
  bool _busy = false;
  String? _error;
  AgentMode _mode = AgentMode.build;

  final Map<String, Completer<bool>> _approvalWaiters = {};
  final Set<String> _resolvedToolCalls = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isBusy => _busy;
  bool get sending => _busy;
  String? get error => _error;
  AgentMode get mode => _mode;

  void setMode(AgentMode mode) {
    if (_mode == mode || _busy) return;
    _mode = mode;
    notifyListeners();
  }

  bool isAwaitingApproval(String id) =>
      _approvalWaiters.containsKey(id) && !_resolvedToolCalls.contains(id);

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _busy) return;
    _error = null;

    final userMsg = ChatMessage(role: ChatRole.user, text: text.trim());
    _messages.add(userMsg);
    _busy = true;
    notifyListeners();

    try {
      final cfg = await _store.loadLlmConfig();
      final key = (await _store.loadLlmApiKey()) ?? '';

      if (!cfg.isConfigured || key.trim().isEmpty) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '请先在「设置」配置 LLM Base URL / 模型 / API Key。',
        ));
        return;
      }

      if (_mode != AgentMode.chat && !_ssh.isConnected) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text: '当前模式为 ${_mode.label}，需要先连接 SSH 主机（或切换到 Chat 纯对话）。',
        ));
        return;
      }

      try {
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
      }
    } finally {
      _busy = false;
      _cancelPendingWaiters();
      notifyListeners();
    }
  }

  void _handleEvent(AgentEvent event, String userText) {
    switch (event) {
      case AgentUserMessage(:final text):
        if (text == userText) return;
        _messages.add(ChatMessage(role: ChatRole.user, text: text));
      case AgentAssistantText(:final text, :final toolCalls):
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
      case AgentPermissionRequest():
        // Buttons appear via isAwaitingApproval; assistant tool cards already shown.
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
  }

  Future<void> approveToolCall(ToolCall call) async {
    if (!_ssh.isConnected && _mode != AgentMode.chat) {
      _error = '请先连接 SSH 主机';
      notifyListeners();
      _resolveWaiter(call.id, false);
      return;
    }
    _resolveWaiter(call.id, true);
  }

  void declineToolCall(ToolCall call) {
    _resolveWaiter(call.id, false);
  }

  void clearMessages() {
    _cancelPendingWaiters();
    _messages.clear();
    _resolvedToolCalls.clear();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
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
