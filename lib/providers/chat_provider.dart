import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/llm_provider_config.dart';
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

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isBusy => _busy;
  bool get sending => _busy;
  String? get error => _error;

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

      // Real agent loop. Tool cards are shown; we auto-pause by declining
      // immediate execution and let the user tap 批准 on the card instead.
      // For a smooth first-run demo when the LLM is unreachable, fall back.
      try {
        await for (final msg in _agent.run(
          userText: text.trim(),
          config: cfg,
          apiKey: key,
          history: [
            for (final m in _messages)
              if (m.id != userMsg.id) m,
          ],
          onApprove: (_) async => false,
        )) {
          if (msg.role == ChatRole.user && msg.text == userMsg.text) continue;
          // Skip auto-declined tool result spam; keep assistant toolCalls cards.
          if (msg.role == ChatRole.tool && msg.toolResult?.declined == true) {
            continue;
          }
          _messages.add(msg);
          notifyListeners();
        }
      } catch (e) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          text:
              'AI 暂时不可用：$e\n\n演示模式：我可以帮你在已连接的主机上执行命令。例如发送包含 “ls” 的消息会弹出待批准命令。',
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
      notifyListeners();
    }
  }

  Future<void> approveToolCall(ToolCall call) async {
    if (!_ssh.isConnected) {
      _error = '请先连接 SSH 主机';
      notifyListeners();
      return;
    }

    final pending = ChatMessage(
      role: ChatRole.tool,
      toolResult: ToolResult(
        toolCallId: call.id,
        exitCode: 0,
        stdout: '（正在执行…）',
        stderr: '',
      ),
    );
    _messages.add(pending);
    notifyListeners();

    try {
      final result = await _ssh.exec(call.command);
      final idx = _messages.lastIndexWhere(
        (m) => m.toolResult?.toolCallId == call.id,
      );
      if (idx != -1) {
        _messages[idx] = ChatMessage(
          role: ChatRole.tool,
          toolResult: ToolResult(
            toolCallId: call.id,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        );
      }
    } catch (e) {
      _error = '命令执行失败: $e';
    }
    notifyListeners();
  }

  void declineToolCall(ToolCall call) {
    _messages.add(ChatMessage(
      role: ChatRole.tool,
      toolResult: ToolResult(
        toolCallId: call.id,
        exitCode: -1,
        stdout: '',
        stderr: '',
        declined: true,
      ),
    ));
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
