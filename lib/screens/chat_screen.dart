import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final session = context.watch<SessionProvider>();
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    if (chat.messages.isNotEmpty) _scrollToBottom();

    final canSend = !chat.isBusy &&
        session.isConnected &&
        settings.isConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空对话',
              onPressed: () => chat.clearMessages(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!session.isConnected)
            _Banner(
              icon: Icons.link_off,
              message: '未连接 SSH，AI 无法执行命令',
              color: cs.errorContainer,
              textColor: cs.onErrorContainer,
            ),
          if (!settings.isConfigured)
            _Banner(
              icon: Icons.key_off_outlined,
              message: '未配置 API Key，请前往设置',
              color: cs.tertiaryContainer,
              textColor: cs.onTertiaryContainer,
            ),
          Expanded(
            child: chat.messages.isEmpty
                ? _EmptyChat(cs: cs)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, i) {
                      final msg = chat.messages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MessageBubble(
                          message: msg,
                          onApprove: msg.role == ChatRole.assistant
                              ? (tc) {
                                  if (chat.isAwaitingApproval(tc.id)) {
                                    chat.approveToolCall(tc);
                                  }
                                }
                              : null,
                          onDecline: msg.role == ChatRole.assistant
                              ? (tc) {
                                  if (chat.isAwaitingApproval(tc.id)) {
                                    chat.declineToolCall(tc);
                                  }
                                }
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          if (chat.isBusy)
            LinearProgressIndicator(
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          _InputBar(
            controller: _inputCtrl,
            canSend: canSend,
            onSend: () {
              final text = _inputCtrl.text.trim();
              if (text.isEmpty) return;
              _inputCtrl.clear();
              chat.sendMessage(text);
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              '和 AI 对话来管理远程主机',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '先连接 SSH 主机并配置 API Key，\n然后输入你想做的事',
              style: TextStyle(color: cs.outline, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    required this.textColor,
  });
  final IconData icon;
  final String message;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Text(message, style: TextStyle(color: textColor, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 8, top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: canSend ? (_) => onSend() : null,
              decoration: InputDecoration(
                hintText: '输入指令，例如：列出磁盘使用情况',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: canSend ? onSend : null,
            icon: const Icon(Icons.send),
            style: IconButton.styleFrom(
              backgroundColor: canSend ? cs.primary : cs.surfaceContainerHighest,
              foregroundColor: canSend ? cs.onPrimary : cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}
