import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'tool_call_card.dart';

/// Renders a single chat turn: user text, assistant text, or tool-call cards.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onApprove,
    this.onDecline,
  });

  final ChatMessage message;
  final void Function(ToolCall)? onApprove;
  final void Function(ToolCall)? onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    switch (message.role) {
      case ChatRole.user:
        return _UserBubble(text: message.text, cs: cs);

      case ChatRole.assistant:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.isNotEmpty) _AssistantBubble(text: message.text, cs: cs),
            for (final tc in message.toolCalls)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ToolCallCard(
                  toolCall: tc,
                  onApprove: onApprove != null ? () => onApprove!(tc) : null,
                  onDecline: onDecline != null ? () => onDecline!(tc) : null,
                ),
              ),
          ],
        );

      case ChatRole.tool:
        final result = message.toolResult;
        if (result == null) return const SizedBox.shrink();
        if (result.declined) {
          return _StatusChip(label: '已拒绝执行命令', color: cs.error);
        }
        return _ToolResultBubble(result: result, cs: cs);

      case ChatRole.system:
        return const SizedBox.shrink();
    }
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.cs});
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(text, style: TextStyle(color: cs.onPrimaryContainer)),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text, required this.cs});
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(text, style: TextStyle(color: cs.onSurface)),
      ),
    );
  }
}

class _ToolResultBubble extends StatelessWidget {
  const _ToolResultBubble({required this.result, required this.cs});
  final ToolResult result;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final output = result.toModelString(maxChars: 1200);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Text(
        output,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Color(0xFF7EE787),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
