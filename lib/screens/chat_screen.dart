import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/remote_cli_bar.dart';

/// Primary surface: Doubao / Claude App style conversation.
/// AI can run commands on the user's remote host (SSH) with approval.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.onOpenServers});

  /// Jump to server list (configured by [AppShell]).
  final VoidCallback? onOpenServers;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  bool _wasConnected = false;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _syncRemoteCliOnConnect(SessionProvider session, ChatProvider chat) {
    final connected = session.isConnected;
    if (connected && !_wasConnected) {
      _wasConnected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || chat.isBusy) return;
        await chat.onHostConnected();
      });
    } else if (!connected && _wasConnected) {
      _wasConnected = false;
      chat.remoteCli.reset();
      chat.remoteAgent.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final session = context.watch<SessionProvider>();
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    _syncRemoteCliOnConnect(session, chat);
    if (chat.messages.isNotEmpty) _scrollToBottom();

    final canSend = !chat.isBusy &&
        session.isConnected &&
        (chat.backend == AgentBackend.remoteNative ||
            settings.isConfigured);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F0E),
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TermuxCode',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            Text(
              session.isConnected
                  ? (chat.backend == AgentBackend.remoteNative
                      ? '远程 ${chat.remoteCli.selected?.label ?? "Agent"} · ${chat.mode.label}'
                      : '内置 Agent · ${chat.mode.label} · ${session.activeProfileLabel ?? "主机"}')
                  : '对话式 AI · 连接主机后可远程执行',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          // Backend: remote native agent vs builtin
          PopupMenuButton<AgentBackend>(
            tooltip: '执行后端',
            initialValue: chat.backend,
            onSelected: chat.isBusy ? null : chat.setBackend,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: AgentBackend.remoteNative,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_sync, size: 20),
                  title: const Text('远程 Agent'),
                  subtitle: const Text(
                    '控制主机上的 Claude / Codex / OpenCode',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: chat.backend == AgentBackend.remoteNative
                      ? Icon(Icons.check, color: cs.primary, size: 18)
                      : null,
                ),
              ),
              PopupMenuItem(
                value: AgentBackend.builtin,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_android, size: 20),
                  title: const Text('内置 Agent'),
                  subtitle: const Text(
                    '手机 BYOK + 远程执行工具',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: chat.backend == AgentBackend.builtin
                      ? Icon(Icons.check, color: cs.primary, size: 18)
                      : null,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  chat.backend == AgentBackend.remoteNative ? '远程' : '内置',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          // Soft mode menu (Plan / Ask / Auto / Bypass)
          PopupMenuButton<AgentMode>(
            tooltip: '权限模式',
            initialValue: chat.mode,
            onSelected: chat.isBusy ? null : chat.setMode,
            itemBuilder: (ctx) => [
              for (final m in AgentMode.values)
                PopupMenuItem(
                  value: m,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (m) {
                        AgentMode.plan => Icons.map_outlined,
                        AgentMode.ask => Icons.front_hand_outlined,
                        AgentMode.auto => Icons.bolt_outlined,
                        AgentMode.bypass => Icons.flash_on,
                      },
                      size: 20,
                    ),
                    title: Text(m.label),
                    subtitle: Text(
                      m.descriptionZh,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: chat.mode == m
                        ? Icon(Icons.check, color: cs.primary, size: 18)
                        : null,
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(
                visualDensity: VisualDensity.compact,
                label:
                    Text(chat.mode.label, style: const TextStyle(fontSize: 12)),
                avatar: Icon(
                  switch (chat.mode) {
                    AgentMode.plan => Icons.map_outlined,
                    AgentMode.ask => Icons.front_hand_outlined,
                    AgentMode.auto => Icons.bolt_outlined,
                    AgentMode.bypass => Icons.flash_on,
                  },
                  size: 16,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _showAdvanced ? '收起高级' : '高级（CLI）',
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(
              _showAdvanced ? Icons.expand_less : Icons.tune,
              size: 22,
            ),
          ),
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '新对话',
              onPressed: chat.isBusy ? null : () => chat.clearMessages(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!session.isConnected)
            _SoftBanner(
              icon: Icons.link_off_rounded,
              message: '连接你的服务器后，我才能在上面执行命令',
              actionLabel: '去配置',
              onAction: widget.onOpenServers,
              color: cs.surfaceContainerHighest,
              textColor: cs.onSurfaceVariant,
            ),
          if (!settings.isConfigured &&
              chat.backend == AgentBackend.builtin)
            _SoftBanner(
              icon: Icons.key_outlined,
              message: '内置 Agent 需要 API Key；有远程 Claude/Codex 可切到「远程」',
              actionLabel: '设置',
              onAction: null,
              color: cs.surfaceContainerHighest,
              textColor: cs.onSurfaceVariant,
            ),
          if (_showAdvanced) const RemoteCliBar(),
          if (chat.awaitingRemoteSendConfirm)
            Material(
              color: const Color(0xFF2A2410),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ask 模式：确认发送到远程 Agent？',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chat.pendingRemotePreview ?? '',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                chat.resolveRemoteSendConfirm(false),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                chat.resolveRemoteSendConfirm(true),
                            child: const Text('发送到远程'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (chat.isBusy &&
              chat.backend == AgentBackend.remoteNative &&
              chat.remoteAgent.isRunning)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: chat.interruptRemoteAgent,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('中断远程 Agent'),
              ),
            ),
          Expanded(
            child: chat.messages.isEmpty
                ? _EmptyChat(
                    cs: cs,
                    mode: chat.mode,
                    onOpenServers: widget.onOpenServers,
                    onQuick: (prompt) {
                      if (prompt == '/cli') {
                        if (!session.isConnected) {
                          widget.onOpenServers?.call();
                          return;
                        }
                        chat.remoteCli.detect();
                        return;
                      }
                      if (!settings.isConfigured) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请先在设置里填写 API Key')),
                        );
                        return;
                      }
                      if (!session.isConnected) {
                        widget.onOpenServers?.call();
                        return;
                      }
                      chat.sendMessage(prompt);
                    },
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, i) {
                      final msg = chat.messages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
              minHeight: 2,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          _Composer(
            controller: _inputCtrl,
            focusNode: _focus,
            canSend: canSend,
            hint: session.isConnected
                ? '有什么可以帮你的？可让我在远程主机上执行…'
                : '先聊聊，或配置主机后让我远程执行命令…',
            onSend: () => _handleSend(chat, session, settings),
          ),
        ],
      ),
    );
  }

  void _handleSend(
    ChatProvider chat,
    SessionProvider session,
    SettingsProvider settings,
  ) {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();

    if (text == '/cli' || text.startsWith('/cli ')) {
      if (text == '/cli') {
        if (!session.isConnected) {
          widget.onOpenServers?.call();
          return;
        }
        chat.remoteCli.detect().then((_) {
          if (!mounted) return;
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
        chat.runRemoteCli(text.substring(5));
      }
      return;
    }

    if (!settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置配置 API Key')),
      );
      return;
    }
    if (!session.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('执行命令需要先连接你的服务器'),
          action: SnackBarAction(
            label: '去配置',
            onPressed: () => widget.onOpenServers?.call(),
          ),
        ),
      );
      return;
    }
    chat.sendMessage(text);
  }
}

class _SoftBanner extends StatelessWidget {
  const _SoftBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.textColor,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final Color color;
  final Color textColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 12.5),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00E5A0),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.cs,
    required this.mode,
    required this.onQuick,
    this.onOpenServers,
  });

  final ColorScheme cs;
  final AgentMode mode;
  final void Function(String prompt) onQuick;
  final VoidCallback? onOpenServers;

  static const _quick = <(String, String, IconData)>[
    ('看看磁盘', '查看磁盘使用情况并用通俗语言解释', Icons.storage_outlined),
    ('系统概况', '用简洁中文汇总系统、内存、磁盘和当前用户', Icons.computer_outlined),
    ('帮我排查', '帮我找出最可能的问题日志并给出下一步', Icons.troubleshoot_outlined),
    ('配置主机', '__servers__', Icons.dns_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 36,
                color: Color(0xFF00E5A0),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '你好，我是 TermuxCode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '像豆包 / Claude 一样对话。\n'
              '连上你的服务器后，优先控制主机上的 Claude / Codex / OpenCode。\n'
              '没有原生 Agent 时，用内置 Agent + 你的 API Key。',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '当前能力：${mode.label} · ${mode.descriptionZh}',
              style: TextStyle(color: cs.outline, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final (label, prompt, icon) in _quick)
                  ActionChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    onPressed: () {
                      if (prompt == '__servers__') {
                        onOpenServers?.call();
                        return;
                      }
                      onQuick(prompt);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.onSend,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final VoidCallback onSend;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: const Color(0xFF101615),
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, bottom + 12),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A2220),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FilledButton(
                  onPressed: canSend ? onSend : null,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                    backgroundColor: const Color(0xFF00E5A0),
                    foregroundColor: const Color(0xFF042018),
                    disabledBackgroundColor: cs.surfaceContainerHighest,
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
