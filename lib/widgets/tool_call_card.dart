import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Card shown when the AI requests permission to run a shell command.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          if (onApprove != null || onDecline != null) ...[
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
                      side: BorderSide(color: cs.error.withOpacity(0.6)),
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
    );
  }
}
