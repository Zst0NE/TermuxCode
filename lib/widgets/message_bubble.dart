import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_message.dart';
import 'tool_call_card.dart';
import 'tool_timeline_tile.dart';

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
            if (message.text.isNotEmpty)
              _AssistantBubble(text: message.text, cs: cs),
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
        // ToolTimelineTile handles all statuses, including declined.
        return ToolTimelineTile(result: result);

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
    final baseStyle = TextStyle(color: cs.onSurface, fontSize: 14, height: 1.35);
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
        child: MarkdownBody(
          data: text,
          selectable: true,
          softLineBreak: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: baseStyle,
            h1: baseStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
            h2: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
            h3: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
            listBullet: baseStyle,
            code: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: Color(0xFF79C0FF),
              backgroundColor: Color(0xFF0D1117),
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            codeblockPadding: const EdgeInsets.all(10),
            blockquoteDecoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
            ),
          ),
        ),
      ),
    );
  }
}

