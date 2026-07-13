import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/agent_service.dart';
import '../services/secure_store.dart';
import '../services/ssh_service.dart';

/// Chat + tool-approval state for the AI screen.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required SecureStore store,
    required SshService ssh,
    AgentService? agent,
  })  : _store = store,
        _ssh = ssh,
        _agent = agent ?? AgentService(sshService: ssh);

  final SecureStore _store;
  final SshService _ssh;
  final AgentService _agent;

  final List<ChatMessage> _messages = [];
  bool _busy = false;
  String? _error;

  /// Pending approval gates keyed by ToolCall.id.
  /// AgentService's onApprove awaits these; UI resolves them via
  /// approveToolCall / declineToolCall.
  final Map<String, Completer<bool>> _approvalWaiters = {};

  /// IDs that have already been resolved (approved or declined) so that
  /// rapid double-taps don't re-complete an already-completed Completer.
  final Set<String> _resolvedToolCalls = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isBusy => _busy;
  bool get sending => _busy;
  String? get error => _error;

  /// Returns true while the agent loop is still waiting for the user to
  /// approve or decline the given tool call id.  The UI uses this to decide
  /// whether to show the approve/decline buttons.
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

      try {
        await for (final msg in _agent.run(
          userText: text.trim(),
          config: cfg,
          apiKey: key,
          history: [
            for (final m in _messages)
              if (m.id != userMsg.id) m,
          ],
          onApprove: (call) async {
            // Create a Completer for this tool call and wait.
            // approveToolCall / declineToolCall resolve it from the UI.
            final completer = Completer<bool>();
            _approvalWaiters[call.id] = completer;
            // Notify the UI so it can show the approve/decline buttons
            // (the assistant message with toolCalls has already been added
            //  to _messages by the stream loop below when we reach here).
            notifyListeners();
            return completer.future;
          },
        )) {
          // Skip duplicate user message that AgentService re-emits.
          if (msg.role == ChatRole.user && msg.text == userMsg.text) continue;

          // AgentService already yields declined tool results; add them
          // so the user sees the "已拒绝" chip.  No need to filter them out.
          _messages.add(msg);
          notifyListeners();
        }
      } catch (e) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text:
              'AI 暂时不可用：$e\n\n演示模式：我可以帮你在已连接的主机上执行命令。例如发送包含 "ls" 的消息会弹出待批准命令。',
          toolCalls: text.toLowerCase().contains('ls')
              ? const [
                  ToolCall(
                    id: 'demo-ls',
                    command: 'ls -la ~',
                    rationale: '列出主目录',
                  ),
                ]
              : const [],
        ));
      }
    } finally {
      _busy = false;
      // Cancel any waiters that never got resolved (e.g. stream error).
      _cancelPendingWaiters();
      notifyListeners();
    }
  }

  /// Called by the UI when the user taps 批准.
  /// Resolves the Completer so AgentService proceeds to execute the command
  /// and yield the tool-result message back into the stream.
  Future<void> approveToolCall(ToolCall call) async {
    if (!_ssh.isConnected) {
      _error = '请先连接 SSH 主机';
      notifyListeners();
      // Decline so the agent loop can continue rather than hanging forever.
      _resolveWaiter(call.id, false);
      return;
    }
    _resolveWaiter(call.id, true);
  }

  /// Called by the UI when the user taps 拒绝.
  /// Resolves the Completer with false; AgentService will yield a declined
  /// ToolResult and the stream loop will add it to _messages — no need to
  /// write an extra message here.
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
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _resolveWaiter(String id, bool approved) {
    if (_resolvedToolCalls.contains(id)) return; // guard rapid double-tap
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
