import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/ssh_profiles_provider.dart';
import 'app_shell.dart';
import 'services/secure_store.dart';
import 'services/ssh_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TermuxCodeApp());
}

class TermuxCodeApp extends StatelessWidget {
  const TermuxCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SecureStore();
    final ssh = SshService();

    return MultiProvider(
      providers: [
        Provider<SecureStore>.value(value: store),
        Provider<SshService>.value(value: ssh),
        ChangeNotifierProvider(
          create: (_) => SshProfilesProvider(store)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => SessionProvider(store, ssh),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(store)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(store: store, ssh: ssh)..loadHistory(),
        ),
      ],
      child: MaterialApp(
        title: 'TermuxCode',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00E5A0),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0B0F0E),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            backgroundColor: Color(0xFF101615),
            elevation: 0,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}
