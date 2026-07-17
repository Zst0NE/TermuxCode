import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_state.dart';
import '../models/ssh_profile.dart';
import '../services/secure_store.dart';
import '../services/ssh_service.dart';
import '../services/ssh_shell_session.dart';

/// One interactive PTY tab on the shared SSH connection.
class TerminalTab {
  TerminalTab({
    required this.id,
    required this.title,
    required this.session,
    required this.terminal,
  });

  final String id;
  String title;
  final SshShellSession session;
  final Terminal terminal;
}

/// SSH connection + **multiple** interactive shells on the same server.
class SessionProvider extends ChangeNotifier {
  SessionProvider(this._store, [SshService? ssh]) : _ssh = ssh ?? SshService();

  final SecureStore _store;
  final SshService _ssh;
  static const _uuid = Uuid();

  SshProfile? _activeProfile;
  SshProfile? _lastProfile;
  SshConnectionState _state = SshConnectionState.disconnected;
  String? _error;

  final List<TerminalTab> _tabs = [];
  int _activeTabIndex = 0;

  SshService get ssh => _ssh;
  SshProfile? get activeProfile => _activeProfile;
  String? get activeProfileId => _activeProfile?.id;
  String? get activeProfileLabel => _activeProfile?.label;
  SshProfile? get lastProfile => _lastProfile;
  SshConnectionState get state => _state;
  bool get isConnected => _state == SshConnectionState.connected;
  bool get isConnecting => _state == SshConnectionState.connecting;
  String? get error => _error;

  List<TerminalTab> get tabs => List.unmodifiable(_tabs);
  int get activeTabIndex => _activeTabIndex;
  TerminalTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];

  /// Back-compat for single-terminal callers.
  SshShellSession? get shellSession => activeTab?.session;
  Terminal? get terminal => activeTab?.terminal;

  Future<void> connect(
    SshProfile profile, {
    Future<bool> Function(
      String host,
      int port,
      String keyType,
      String fingerprintDisplay,
    )? onUnknownHostKey,
    Future<bool> Function(
      String host,
      int port,
      String keyType,
      String fingerprintDisplay,
      String previousFingerprint,
    )? onHostKeyMismatch,
  }) async {
    _error = null;
    _state = SshConnectionState.connecting;
    _activeProfile = profile;
    _lastProfile = profile;
    notifyListeners();

    try {
      await _ssh.connect(
        profile,
        _store,
        onUnknownHostKey: onUnknownHostKey,
        onHostKeyMismatch: onHostKeyMismatch,
      );

      await _closeAllTabs();
      await openNewTerminal(title: 'shell-1');

      _state = SshConnectionState.connected;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _state = SshConnectionState.error;
      _activeProfile = null;
      await _closeAllTabs();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reconnect({
    Future<bool> Function(
      String host,
      int port,
      String keyType,
      String fingerprintDisplay,
    )? onUnknownHostKey,
    Future<bool> Function(
      String host,
      int port,
      String keyType,
      String fingerprintDisplay,
      String previousFingerprint,
    )? onHostKeyMismatch,
  }) async {
    final profile = _lastProfile;
    if (profile == null) {
      throw StateError('没有可重连的主机配置');
    }
    await connect(
      profile,
      onUnknownHostKey: onUnknownHostKey,
      onHostKeyMismatch: onHostKeyMismatch,
    );
  }

  /// Open another PTY on the **same** SSH server (multi-terminal).
  Future<TerminalTab> openNewTerminal({String? title, int cols = 80, int rows = 24}) async {
    if (!_ssh.isConnected) {
      throw StateError('openNewTerminal while not connected');
    }

    final n = _tabs.length + 1;
    final term = Terminal();
    final session = await _ssh.openShell(cols: cols, rows: rows);
    session.attachTerminal(term);
    final tab = TerminalTab(
      id: _uuid.v4(),
      title: title ?? 'shell-$n',
      session: session,
      terminal: term,
    );
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
    notifyListeners();

    session.done.then((_) {
      _onTabDone(tab.id);
    });
    return tab;
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeTabIndex = index;
    notifyListeners();
  }

  Future<void> closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    try {
      tab.session.close();
    } catch (_) {}
    if (_tabs.isEmpty) {
      _activeTabIndex = 0;
    } else if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    } else if (index < _activeTabIndex) {
      _activeTabIndex -= 1;
    }
    notifyListeners();
  }

  void _onTabDone(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tabs.removeAt(i);
    if (_tabs.isEmpty) {
      _activeTabIndex = 0;
    } else if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  Future<void> _closeAllTabs() async {
    for (final t in _tabs) {
      try {
        t.session.close();
      } catch (_) {}
    }
    _tabs.clear();
    _activeTabIndex = 0;
  }

  /// Legacy: open/replace single shell — now opens a **new** tab.
  Future<SshShellSession> openShell({int cols = 80, int rows = 24}) async {
    final tab = await openNewTerminal(cols: cols, rows: rows);
    return tab.session;
  }

  Future<void> disconnect() async {
    await _closeAllTabs();
    await _ssh.disconnect();
    _activeProfile = null;
    _state = SshConnectionState.disconnected;
    _error = null;
    notifyListeners();
  }

  void resize(int cols, int rows) => activeTab?.session.resize(cols, rows);

  @override
  void dispose() {
    _closeAllTabs();
    _ssh.dispose();
    super.dispose();
  }
}
