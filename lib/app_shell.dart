import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/ssh_connection_state.dart';
import 'providers/session_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';

/// Bottom-nav host for the four primary surfaces.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = ['连接', '终端', 'Agent', '设置'];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final connected = session.isConnected;
    final connecting = session.isConnecting;
    final cs = Theme.of(context).colorScheme;

    final pages = <Widget>[
      const ProfilesScreen(),
      const TerminalScreen(),
      const ChatScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Global session strip — visible on every tab.
          Material(
            color: connected
                ? const Color(0xFF0D2A22)
                : connecting
                    ? const Color(0xFF2A2410)
                    : const Color(0xFF1A1F1D),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      connected
                          ? Icons.cloud_done
                          : connecting
                              ? Icons.cloud_sync
                              : Icons.cloud_off,
                      size: 18,
                      color: connected
                          ? const Color(0xFF00E5A0)
                          : connecting
                              ? const Color(0xFFF5C542)
                              : cs.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        connected
                            ? '已连接 · ${session.activeProfileLabel ?? "SSH"}'
                            : connecting
                                ? '正在连接…'
                                : session.error != null
                                    ? '连接异常 · 点「连接」重试'
                                    : '未连接 · TermuxCode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: connected
                              ? const Color(0xFF00E5A0)
                              : connecting
                                  ? const Color(0xFFF5C542)
                                  : cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (connected)
                      TextButton(
                        onPressed: () => session.disconnect(),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('断开'),
                      )
                    else if (!connecting && session.lastProfile != null)
                      TextButton(
                        onPressed: () async {
                          try {
                            await session.reconnect();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('重连失败：$e'),
                                backgroundColor: Colors.red[800],
                              ),
                            );
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5A0),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text('重连 ${session.lastProfile!.label}'),
                      )
                    else if (!connecting)
                      TextButton(
                        onPressed: () => setState(() => _index = 0),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5A0),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('去连接'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (session.error != null &&
              session.state == SshConnectionState.error)
            Material(
              color: cs.errorContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: cs.onErrorContainer),
                      onPressed: () {
                        // clear by reconnecting state via disconnect noop path
                        session.disconnect();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dns_outlined),
            selectedIcon: const Icon(Icons.dns),
            label: _titles[0],
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: connected,
              smallSize: 8,
              backgroundColor: const Color(0xFF00E5A0),
              child: const Icon(Icons.terminal_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: connected,
              smallSize: 8,
              backgroundColor: const Color(0xFF00E5A0),
              child: const Icon(Icons.terminal),
            ),
            label: _titles[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.smart_toy_outlined),
            selectedIcon: const Icon(Icons.smart_toy),
            label: _titles[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: _titles[3],
          ),
        ],
      ),
    );
  }
}
