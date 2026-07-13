import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
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

    final needsSsh = chat.mode != AgentMode.chat;
    final canSend = !chat.isBusy &&
        settings.isConfigured &&
        (!needsSsh || session.isConnected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TermuxCode'),
        actions: [
          IconButton(
            tooltip: '探测远端 CLI',
            onPressed: chat.isBusy || !session.isConnected
                ? null
                : () async {
                    await chat.remoteCli.detect();
                    if (!context.mounted) return;
                    final avail = chat.remoteCli.available;
                    final text = avail.isEmpty
                        ? '未检测到 opencode / claude / codex'
                        : avail.entries
                            .map((e) => '${e.key.label}: ${e.value}')
                            .join('\n');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(text)),
                    );
                  },
            icon: const Icon(Icons.dns_outlined),
          ),
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空对话',
              onPressed: chat.isBusy ? null : () => chat.clearMessages(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<AgentMode>(
              segments: [
                for (final m in AgentMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(m.label),
                    tooltip: m.descriptionZh,
                  ),
              ],
              selected: {chat.mode},
              onSelectionChanged:
                  chat.isBusy ? null : (s) => chat.setMode(s.first),
            ),
          ),
          if (needsSsh && !session.isConnected)
            _Banner(
              icon: Icons.link_off,
              message: '未连接 SSH — Plan/Build 需要主机（Chat 可纯对话）',
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
                ? _EmptyChat(cs: cs, mode: chat.mode)
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
              // Prefix: /cli ... → host OpenCode/Claude/Codex adapter
              if (text.startsWith('/cli ')) {
                chat.runRemoteCli(text.substring(5));
              } else if (text == '/cli') {
                chat.remoteCli.detect().then((_) {
                  if (!context.mounted) return;
                  final avail = chat.remoteCli.available;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        avail.isEmpty
                            ? '未检测到远端 CLI'
                            : '可用: ${avail.keys.map((k) => k.label).join(", ")}',
                      ),
                    ),
                  );
                });
              } else {
                chat.sendMessage(text);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.cs, required this.mode});
  final ColorScheme cs;
  final AgentMode mode;

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
              'TermuxCode Agent',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${mode.label}：${mode.descriptionZh}\nChat / Plan / Build 可在上方切换',
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
          Expanded(
            child:
                Text(message, style: TextStyle(color: textColor, fontSize: 13)),
          ),
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
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
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
                hintText: '描述任务，例如：查看磁盘占用并给出建议',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: canSend ? onSend : null,
            icon: const Icon(Icons.send),
            style: IconButton.styleFrom(
              backgroundColor:
                  canSend ? cs.primary : cs.surfaceContainerHighest,
              foregroundColor: canSend ? cs.onPrimary : cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}
