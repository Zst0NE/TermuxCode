import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Card shown when the AI requests permission to run a shell command.
///
/// When [onApprove] or [onDecline] is non-null the call is still pending user
/// action; a prominent "等待批准" badge is shown and a left amber accent border
/// signals that attention is required. Once resolved the buttons disappear and
/// the border reverts to the normal primary tint.
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({
    super.key,
    required this.toolCall,
    this.onApprove,
    this.onDecline,
  });

  final ToolCall toolCall;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  bool get _isPending => onApprove != null || onDecline != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Pending = amber accent; resolved = muted primary tint.
    const pendingColor = Color(0xFFD29922);
    final accentColor = _isPending ? pendingColor : cs.primary;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent border
            Container(
              width: 4,
              color: accentColor.withValues(alpha: _isPending ? 0.85 : 0.45),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Icon(Icons.terminal, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          'AI 请求执行命令',
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isPending) ...[
                          const SizedBox(width: 8),
                          _PendingBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Command block
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        toolCall.command,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFF79C0FF),
                        ),
                      ),
                    ),
                    if (toolCall.rationale != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        toolCall.rationale!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_isPending) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (onDecline != null)
                            OutlinedButton.icon(
                              onPressed: onDecline,
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('拒绝'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.error,
                                side: BorderSide(
                                    color: cs.error.withValues(alpha: 0.6)),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (onApprove != null)
                            FilledButton.icon(
                              onPressed: onApprove,
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('批准执行'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated "等待批准" badge shown when a tool call is pending approval.
class _PendingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFD29922);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.hourglass_top_rounded, size: 11, color: color),
          SizedBox(width: 3),
          Text(
            '等待批准',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
