import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Horizontal mobile-friendly key strip for sending special keys into a
/// [Terminal]. Ctrl is sticky: tap once to arm, next letter/key is sent with
/// ctrl and then Ctrl disarms.
class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({
    super.key,
    required this.terminal,
  });

  final Terminal terminal;

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  bool _ctrl = false;
  bool _alt = false;

  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(
      key,
      ctrl: _ctrl,
      alt: _alt,
    );
    if (_ctrl || _alt) {
      setState(() {
        _ctrl = false;
        _alt = false;
      });
    }
  }

  void _sendChar(String ch) {
    if (ch.isEmpty) return;
    final code = ch.toLowerCase().codeUnitAt(0);
    if (_ctrl || _alt) {
      widget.terminal.charInput(code, ctrl: _ctrl, alt: _alt);
      setState(() {
        _ctrl = false;
        _alt = false;
      });
    } else {
      widget.terminal.textInput(ch);
    }
  }

  void _toggleCtrl() => setState(() => _ctrl = !_ctrl);
  void _toggleAlt() => setState(() => _alt = !_alt);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF121816),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          children: [
            _modKey(
              label: 'Ctrl',
              active: _ctrl,
              onTap: _toggleCtrl,
              cs: cs,
            ),
            _modKey(
              label: 'Alt',
              active: _alt,
              onTap: _toggleAlt,
              cs: cs,
            ),
            _key('Esc', () => _sendKey(TerminalKey.escape)),
            _key('Tab', () => _sendKey(TerminalKey.tab)),
            _key('↑', () => _sendKey(TerminalKey.arrowUp)),
            _key('↓', () => _sendKey(TerminalKey.arrowDown)),
            _key('←', () => _sendKey(TerminalKey.arrowLeft)),
            _key('→', () => _sendKey(TerminalKey.arrowRight)),
            _key('Home', () => _sendKey(TerminalKey.home)),
            _key('End', () => _sendKey(TerminalKey.end)),
            _key('PgUp', () => _sendKey(TerminalKey.pageUp)),
            _key('PgDn', () => _sendKey(TerminalKey.pageDown)),
            _key('—', () => _sendKey(TerminalKey.minus)),
            // Common Ctrl combos as one-shots (also work via sticky Ctrl + letter).
            _key('^C', () {
              widget.terminal.charInput('c'.codeUnitAt(0), ctrl: true);
            }),
            _key('^D', () {
              widget.terminal.charInput('d'.codeUnitAt(0), ctrl: true);
            }),
            _key('^Z', () {
              widget.terminal.charInput('z'.codeUnitAt(0), ctrl: true);
            }),
            _key('^L', () {
              widget.terminal.charInput('l'.codeUnitAt(0), ctrl: true);
            }),
            // Letters for sticky Ctrl/Alt (horizontal scroll).
            for (final ch in 'abcdefghijklmnopqrstuvwxyz'.split(''))
              _key(ch, () => _sendChar(ch)),
          ],
        ),
      ),
    );
  }

  Widget _modKey({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active ? cs.primary.withValues(alpha: 0.25) : const Color(0xFF1C2622),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: const Color(0xFF1C2622),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
