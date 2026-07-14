import 'package:flutter/material.dart';

import '../models/chat_message.dart';

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

enum _ToolStatus { success, failure, declined, timedOut, truncated }

_ToolStatus _statusOf(ToolResult r) {
  if (r.declined) return _ToolStatus.declined;
  if (r.timedOut) return _ToolStatus.timedOut;
  if (r.exitCode != 0) return _ToolStatus.failure;
  // Success but output was cut — surface it so the user knows.
  if (r.truncated) return _ToolStatus.truncated;
  return _ToolStatus.success;
}

const _kMaxCollapsedLines = 12;

class _StatusStyle {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusStyle(this.label, this.icon, this.color);
}

_StatusStyle _styleOf(_ToolStatus s, ColorScheme cs) {
  switch (s) {
    case _ToolStatus.success:
      return const _StatusStyle('成功', Icons.check_circle_outline,
          Color(0xFF3FB950));
    case _ToolStatus.failure:
      return _StatusStyle('失败', Icons.error_outline, cs.error);
    case _ToolStatus.declined:
      return _StatusStyle('已拒绝', Icons.block_outlined, cs.onSurfaceVariant);
    case _ToolStatus.timedOut:
      return const _StatusStyle(
          '超时', Icons.timer_off_outlined, Color(0xFFD29922));
    case _ToolStatus.truncated:
      return const _StatusStyle(
          '截断', Icons.compress_outlined, Color(0xFF79C0FF));
  }
}

// ---------------------------------------------------------------------------
// ToolTimelineTile
// ---------------------------------------------------------------------------

/// Renders a [ToolResult] as a timeline tile with:
///
/// - Coloured left border accent keyed to execution status.
/// - Status chip (成功 / 失败 / 已拒绝 / 超时 / 截断).
/// - Collapsible stdout/stderr: first [_kMaxCollapsedLines] lines visible; a
///   "展开" button reveals the rest without leaving the scroll position.
/// - exit_code row when non-zero or when stderr is present.
class ToolTimelineTile extends StatefulWidget {
  const ToolTimelineTile({super.key, required this.result});

  final ToolResult result;

  @override
  State<ToolTimelineTile> createState() => _ToolTimelineTileState();
}

class _ToolTimelineTileState extends State<ToolTimelineTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _statusOf(widget.result);
    final style = _styleOf(status, cs);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent border
            Container(
              width: 4,
              color: style.color.withValues(alpha: 0.75),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: icon + "执行结果" label + status chip
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.45)),
                        const SizedBox(width: 5),
                        Text(
                          '执行结果',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChipInline(style: style),
                      ],
                    ),

                    // Declined: no further output to show.
                    if (status == _ToolStatus.declined) ...[
                      const SizedBox(height: 6),
                      Text(
                        '命令已被拒绝执行，AI 将不会重试此命令。',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else ...[
                      // exit_code (always show when non-zero; also show stderr row)
                      if (widget.result.exitCode != 0 ||
                          widget.result.stderr.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _ExitCodeRow(
                            exitCode: widget.result.exitCode, cs: cs),
                      ],

                      // stdout
                      if (widget.result.stdout.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _CollapsibleOutput(
                          label: 'stdout',
                          text: widget.result.stdout,
                          textColor: const Color(0xFF7EE787),
                          expanded: _expanded,
                          onToggle: () =>
                              setState(() => _expanded = !_expanded),
                          cs: cs,
                        ),
                      ],

                      // stderr (always fully visible — usually short)
                      if (widget.result.stderr.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _OutputBlock(
                          label: 'stderr',
                          text: widget.result.stderr,
                          textColor: const Color(0xFFF85149),
                          cs: cs,
                        ),
                      ],

                      // Truncation notice
                      if (widget.result.truncated) ...[
                        const SizedBox(height: 6),
                        Text(
                          '输出已截断（超过大小限制）',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF79C0FF)
                                .withValues(alpha: 0.75),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],

                      // Timeout notice
                      if (widget.result.timedOut) ...[
                        const SizedBox(height: 6),
                        Text(
                          '命令超时，输出可能不完整。',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFFD29922)
                                .withValues(alpha: 0.85),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _StatusChipInline extends StatelessWidget {
  const _StatusChipInline({required this.style});
  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 11, color: style.color),
          const SizedBox(width: 3),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
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

class _ExitCodeRow extends StatelessWidget {
  const _ExitCodeRow({required this.exitCode, required this.cs});
  final int exitCode;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isErr = exitCode != 0;
    final color = isErr ? const Color(0xFFF85149) : const Color(0xFF7EE787);
    return Row(
      children: [
        Text(
          'exit_code: ',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        Text(
          '$exitCode',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// An output block (label + monospace text). No collapse logic.
class _OutputBlock extends StatelessWidget {
  const _OutputBlock({
    required this.label,
    required this.text,
    required this.textColor,
    required this.cs,
  });
  final String label;
  final String text;
  final Color textColor;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: textColor,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// stdout block: collapses to [_kMaxCollapsedLines] lines with an expand toggle.
class _CollapsibleOutput extends StatelessWidget {
  const _CollapsibleOutput({
    required this.label,
    required this.text,
    required this.textColor,
    required this.expanded,
    required this.onToggle,
    required this.cs,
  });

  final String label;
  final String text;
  final Color textColor;
  final bool expanded;
  final VoidCallback onToggle;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final needsCollapse = lines.length > _kMaxCollapsedLines;
    final visibleLines =
        (!needsCollapse || expanded) ? lines : lines.take(_kMaxCollapsedLines).toList();
    final visibleText = visibleLines.join('\n');
    final hiddenCount = lines.length - _kMaxCollapsedLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          visibleText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: textColor,
            height: 1.4,
          ),
        ),
        if (needsCollapse) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: cs.primary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 3),
                Text(
                  expanded
                      ? '收起'
                      : '展开（还有 $hiddenCount 行）',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.primary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
