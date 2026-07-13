import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_state.dart';
import '../models/ssh_profile.dart';
import '../services/secure_store.dart';
import '../services/ssh_service.dart';
import '../services/ssh_shell_session.dart';

/// Manages a single active SSH session (connect / disconnect / shell).
class SessionProvider extends ChangeNotifier {
  SessionProvider(this._store, [SshService? ssh]) : _ssh = ssh ?? SshService();

  final SecureStore _store;
  final SshService _ssh;

  SshProfile? _activeProfile;
  SshShellSession? _shell;
  Terminal? _terminal;
  SshConnectionState _state = SshConnectionState.disconnected;
  String? _error;

  SshService get ssh => _ssh;
  SshProfile? get activeProfile => _activeProfile;
  String? get activeProfileId => _activeProfile?.id;
  String? get activeProfileLabel => _activeProfile?.label;
  SshShellSession? get shellSession => _shell;
  SshConnectionState get state => _state;
  bool get isConnected => _state == SshConnectionState.connected;
  bool get isConnecting => _state == SshConnectionState.connecting;
  String? get error => _error;

  /// The xterm Terminal instance for the current shell session.
  Terminal? get terminal => _terminal;

  /// Connect to [profile] and open an interactive shell.
  ///
  /// [onUnknownHostKey] / [onHostKeyMismatch] are forwarded to [SshService]
  /// so the UI can prompt the user during host-key verification.
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
    notifyListeners();

    try {
      await _ssh.connect(
        profile,
        _store,
        onUnknownHostKey: onUnknownHostKey,
        onHostKeyMismatch: onHostKeyMismatch,
      );

      final term = Terminal();
      _terminal = term;
      _shell = await _ssh.openShell(cols: 80, rows: 24);
      _shell!.attachTerminal(term);

      _state = SshConnectionState.connected;
      notifyListeners();

      _shell!.done.then((_) {
        _onShellDone();
      });
    } catch (e) {
      _error = e.toString();
      _state = SshConnectionState.error;
      _activeProfile = null;
      _shell = null;
      _terminal = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Open (or re-open) an interactive shell on the current connection.
  Future<SshShellSession> openShell({int cols = 80, int rows = 24}) async {
    if (!isConnected) {
      throw StateError('openShell called while not connected');
    }
    _shell?.close();
    final term = Terminal();
    _terminal = term;
    _shell = await _ssh.openShell(cols: cols, rows: rows);
    _shell!.attachTerminal(term);
    notifyListeners();
    _shell!.done.then((_) => _onShellDone());
    return _shell!;
  }

  void _onShellDone() {
    if (_state == SshConnectionState.disconnected) return;
    _shell = null;
    // Keep TCP session; only shell channel ended.
    notifyListeners();
  }

  Future<void> disconnect() async {
    _shell?.close();
    _shell = null;
    _terminal = null;
    await _ssh.disconnect();
    _activeProfile = null;
    _state = SshConnectionState.disconnected;
    _error = null;
    notifyListeners();
  }

  /// Resize the PTY when the terminal widget changes size.
  void resize(int cols, int rows) => _shell?.resize(cols, rows);

  @override
  void dispose() {
    _shell?.close();
    _ssh.dispose();
    super.dispose();
  }
}
