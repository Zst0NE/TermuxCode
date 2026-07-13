import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../providers/session_provider.dart';
import '../models/ssh_connection_state.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Terminal? _terminal;
  bool _attached = false;

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
                Text('未连接', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text(
                  '请先在"连接"页面连接到 SSH 主机',
                  style: TextStyle(color: cs.outline, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If we have an active shell session, attach terminal once.
    final shellSession = session.shellSession;
    if (shellSession != null && !_attached) {
      _terminal ??= Terminal();
      shellSession.attachTerminal(_terminal!);
      _attached = true;
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
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('打开终端失败：$e'), backgroundColor: Colors.red[800]),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(session.activeProfileLabel ?? '终端'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新打开终端',
            onPressed: () async {
              _attached = false;
              setState(() => _terminal = null);
              try {
                await session.openShell();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('重新打开失败：$e'), backgroundColor: Colors.red[800]),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _terminal != null
          ? TerminalView(
              _terminal!,
              theme: TerminalTheme(
                cursor: const Color(0xFF00FF88),
                selection: const Color(0xFF264F78),
                foreground: const Color(0xFFD4D4D4),
                background: const Color(0xFF0C0C0C),
                black: const Color(0xFF0C0C0C),
                red: const Color(0xFFCD3131),
                green: const Color(0xFF0DBC79),
                yellow: const Color(0xFFE5E510),
                blue: const Color(0xFF2472C8),
                magenta: const Color(0xFFBC3FBC),
                cyan: const Color(0xFF11A8CD),
                white: const Color(0xFFE5E5E5),
                brightBlack: const Color(0xFF666666),
                brightRed: const Color(0xFFF14C4C),
                brightGreen: const Color(0xFF23D18B),
                brightYellow: const Color(0xFFF5F543),
                brightBlue: const Color(0xFF3B8EEA),
                brightMagenta: const Color(0xFFD670D6),
                brightCyan: const Color(0xFF29B8DB),
                brightWhite: const Color(0xFFFFFFFF),
                searchHitBackground: const Color(0xFFFFFFAA),
                searchHitBackgroundCurrent: const Color(0xFFFF8800),
                searchHitForeground: const Color(0xFF000000),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
