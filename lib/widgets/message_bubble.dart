import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.onCopy,
  });

  final ChatMessage message;
  final void Function(ToolCall)? onApprove;
  final void Function(ToolCall)? onDecline;
  final void Function(String text)? onCopy;

  Future<void> _copy(BuildContext context, String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
    onCopy?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch (message.role) {
      case ChatRole.user:
        return _UserBubble(
          text: message.text,
          cs: cs,
          onLongPress: () => _copy(context, message.text),
        );

      case ChatRole.assistant:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.isNotEmpty)
              message.isRemoteProcess
                  ? _RemoteProcessBubble(
                      text: message.text,
                      cs: cs,
                      onLongPress: () => _copy(context, message.text),
                    )
                  : _AssistantBubble(
                      text: message.text,
                      cs: cs,
                      onLongPress: () => _copy(context, message.text),
                    ),
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
        return ToolTimelineTile(result: result);

      case ChatRole.system:
        return const SizedBox.shrink();
    }
  }
}

/// Doubao-style collapsible "process" for remote Claude/Codex stream.
class _RemoteProcessBubble extends StatefulWidget {
  const _RemoteProcessBubble({
    required this.text,
    required this.cs,
    this.onLongPress,
  });
  final String text;
  final ColorScheme cs;
  final VoidCallback? onLongPress;

  @override
  State<_RemoteProcessBubble> createState() => _RemoteProcessBubbleState();
}

class _RemoteProcessBubbleState extends State<_RemoteProcessBubble> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final preview = text.length <= 280 ? text : '${text.substring(0, 280)}…';
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF121816),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: widget.cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _expanded ? '远程 Agent 输出（点击收起）' : '远程 Agent 输出（点击展开）',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.cs.primary,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: widget.cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SelectableText(
                  _expanded ? text : preview,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.35,
                    color: Color(0xFFD4D4D4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.text,
    required this.cs,
    this.onLongPress,
  });
  final String text;
  final ColorScheme cs;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
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
          child: SelectableText(
            text,
            style: TextStyle(color: cs.onPrimaryContainer, height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.text,
    required this.cs,
    this.onLongPress,
  });
  final String text;
  final ColorScheme cs;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(color: cs.onSurface, fontSize: 14, height: 1.4);
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
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
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              codeblockPadding: const EdgeInsets.all(10),
              blockquoteDecoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
