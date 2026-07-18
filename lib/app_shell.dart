import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/ssh_connection_state.dart';
import 'providers/session_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';

/// Chat-first shell (Doubao / Claude App style).
///
/// Tabs: 对话 (home) · 服务器 · 终端(高级) · 设置
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 0 = 对话 (default home)
  int _index = 0;

  static const _titles = ['对话', '服务器', '终端', '设置'];

  void goToServers() => setState(() => _index = 1);
  void goToChat() => setState(() => _index = 0);
  void goToSettings() => setState(() => _index = 3);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final connected = session.isConnected;
    final connecting = session.isConnecting;
    final cs = Theme.of(context).colorScheme;

    // Chat-first page order
    final pages = <Widget>[
      ChatScreen(
        onOpenServers: goToServers,
        onOpenSettings: goToSettings,
      ),
      ProfilesScreen(onConnected: goToChat),
      const TerminalScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Compact host status — secondary to chat, not a heavy ops bar.
          Material(
            color: connected
                ? const Color(0xFF0D2A22)
                : connecting
                    ? const Color(0xFF2A2410)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      connected
                          ? Icons.cloud_done_rounded
                          : connecting
                              ? Icons.cloud_sync_rounded
                              : Icons.cloud_off_rounded,
                      size: 16,
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
                            ? '远程主机 · ${session.activeProfileLabel ?? "已连接"}'
                            : connecting
                                ? '正在连接远程主机…'
                                : session.error != null
                                    ? '主机连接失败'
                                    : '未连接远程主机 · AI 可先聊天',
                        style: TextStyle(
                          fontSize: 12,
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
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('断开', style: TextStyle(fontSize: 12)),
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
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '重连',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )
                    else if (!connecting)
                      TextButton(
                        onPressed: goToServers,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5A0),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('配置主机', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (session.error != null &&
              session.state == SshConnectionState.error)
            Material(
              color: cs.errorContainer.withValues(alpha: 0.9),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: cs.onErrorContainer),
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
                    TextButton(
                      onPressed: goToServers,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onErrorContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('去处理'),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 16, color: cs.onErrorContainer),
                      onPressed: () => session.disconnect(),
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
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: _titles[0],
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: connected,
              smallSize: 8,
              backgroundColor: const Color(0xFF00E5A0),
              child: const Icon(Icons.dns_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: connected,
              smallSize: 8,
              backgroundColor: const Color(0xFF00E5A0),
              child: const Icon(Icons.dns),
            ),
            label: _titles[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.terminal_outlined),
            selectedIcon: const Icon(Icons.terminal),
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
