import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_state.dart';
import '../providers/session_provider.dart';
import '../widgets/terminal_key_bar.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Terminal? _terminal;
  bool _attached = false;
  double _fontSize = 13;

  static const _theme = TerminalTheme(
    cursor: Color(0xFF00FF88),
    selection: Color(0xFF264F78),
    foreground: Color(0xFFD4D4D4),
    background: Color(0xFF0C0C0C),
    black: Color(0xFF0C0C0C),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFFAA),
    searchHitBackgroundCurrent: Color(0xFFFF8800),
    searchHitForeground: Color(0xFF000000),
  );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final cs = Theme.of(context).colorScheme;

    if (session.state != SshConnectionState.connected) {
      return Scaffold(
        appBar: AppBar(title: const Text('终端')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 72, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  '未连接',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  '请先在「连接」页面连接到 SSH 主机',
                  style: TextStyle(color: cs.outline, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Prefer the Terminal instance owned by SessionProvider (created on connect).
    final sessionTerm = session.terminal;
    final shellSession = session.shellSession;

    if (shellSession != null) {
      if (sessionTerm != null) {
        _terminal = sessionTerm;
        _attached = true;
      } else if (!_attached) {
        _terminal ??= Terminal();
        shellSession.attachTerminal(_terminal!);
        _attached = true;
      }
      // Keep remote PTY size in sync when the view auto-resizes the Terminal.
      _terminal?.onResize = (w, h, pw, ph) => session.resize(w, h);
    }

    if (shellSession == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('终端')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await session.openShell();
                    setState(() {
                      _attached = true;
                      _terminal = session.terminal;
                    });
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('打开终端失败：$e'),
                          backgroundColor: Colors.red[800],
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开终端'),
              ),
            ],
          ),
        ),
      );
    }

    final term = _terminal;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.activeProfileLabel ?? '终端'),
        actions: [
          IconButton(
            tooltip: '缩小字体',
            onPressed: () {
              setState(() => _fontSize = (_fontSize - 1).clamp(10, 22));
            },
            icon: const Icon(Icons.text_decrease, size: 20),
          ),
          IconButton(
            tooltip: '放大字体',
            onPressed: () {
              setState(() => _fontSize = (_fontSize + 1).clamp(10, 22));
            },
            icon: const Icon(Icons.text_increase, size: 20),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新打开终端',
            onPressed: () async {
              _attached = false;
              setState(() => _terminal = null);
              try {
                await session.openShell();
                setState(() {
                  _terminal = session.terminal;
                  _attached = true;
                });
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重新打开失败：$e'),
                      backgroundColor: Colors.red[800],
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: term == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TerminalView(
                    term,
                    theme: _theme,
                    textStyle: TerminalStyle(
                      fontSize: _fontSize,
                      fontFamily: 'monospace',
                    ),
                    autofocus: true,
                    backgroundOpacity: 1,
                  ),
                ),
                TerminalKeyBar(terminal: term),
              ],
            ),
    );
  }
}
