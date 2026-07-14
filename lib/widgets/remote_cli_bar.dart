import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/remote/remote_cli_kind.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';

/// Compact strip: detect host CLIs + select which one `/cli` and the send path use.
class RemoteCliBar extends StatelessWidget {
  const RemoteCliBar({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final chat = context.watch<ChatProvider>();
    final remote = chat.remoteCli;
    final cs = Theme.of(context).colorScheme;

    if (!session.isConnected) {
      return const SizedBox.shrink();
    }

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.terminal, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              '远端 CLI',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: remote.detecting
                  ? const Text('探测中…', style: TextStyle(fontSize: 12))
                  : remote.hasAny
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final e in remote.available.entries)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      e.key.label,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: remote.selected == e.key,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: chat.isBusy
                                        ? null
                                        : (_) => remote.select(e.key),
                                    tooltip: e.value,
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Text(
                          remote.lastError ?? '未探测 · 点右侧扫描',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
            ),
            IconButton(
              tooltip: '重新探测',
              visualDensity: VisualDensity.compact,
              onPressed: chat.isBusy || remote.detecting
                  ? null
                  : () async {
                      await remote.detect();
                      if (!context.mounted) return;
                      final n = remote.available.length;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            n == 0
                                ? '未找到 opencode / claude / codex'
                                : '找到 $n 个 CLI：${remote.available.keys.map((k) => k.label).join(", ")}',
                          ),
                        ),
                      );
                    },
              icon: remote.detecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper for empty-state tip.
String remoteCliHint(RemoteCliKind? selected, bool hasAny) {
  if (!hasAny) {
    return '输入 /cli 探测远端 CLI，或点上方雷达图标。\n'
        '安装 OpenCode 后可用：/cli 解释当前仓库结构';
  }
  final name = selected?.label ?? 'CLI';
  return '已选 $name。发送：/cli 你的任务\n'
      '或在输入框用 /cli 前缀把任务交给远端 CLI（非内置 Agent）。';
}
