import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    final pages = <Widget>[
      const ProfilesScreen(),
      const TerminalScreen(),
      const ChatScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
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
