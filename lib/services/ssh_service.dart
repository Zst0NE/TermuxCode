import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_command_result.dart';
import '../models/ssh_connection_state.dart';
import '../models/ssh_exception.dart';
import '../models/ssh_profile.dart';
import 'secure_store.dart';
import 'ssh_shell_session.dart';

/// Manages a single SSH connection lifecycle and provides exec / shell APIs.
///
/// Usage:
/// ```dart
/// final svc = SshService();
/// await svc.connect(profile, store);
/// final result = await svc.exec('ls -la');
/// await svc.disconnect();
/// svc.dispose();
/// ```
class SshService {
  SSHClient? _client;

  final _stateController =
      StreamController<SshConnectionState>.broadcast();

  SshConnectionState _state = SshConnectionState.disconnected;

  // ------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------

  /// Stream of connection lifecycle transitions.
  Stream<SshConnectionState> get stateStream => _stateController.stream;

  /// Current connection state.
  SshConnectionState get state => _state;

  /// Whether the client is currently authenticated and usable.
  bool get isConnected => _state == SshConnectionState.connected;

  void _setState(SshConnectionState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  // ------------------------------------------------------------------
  // connect
  // ------------------------------------------------------------------

  /// Establish an SSH connection for [profile], loading secrets from [store].
  ///
  /// If already connected, the existing session is cleanly disconnected first.
  /// Throws [SshAuthException] on authentication failure and [SshException]
  /// for transport / configuration errors.  Secrets are never included in
  /// exception messages.
  Future<void> connect(SshProfile profile, SecureStore store) async {
    if (isConnected || _state == SshConnectionState.connecting) {
      await disconnect();
    }

    _setState(SshConnectionState.connecting);

    SSHSocket? socket;
    SSHClient? client;
    try {
      // 1. Open TCP socket.
      socket = await SSHSocket.connect(profile.host, profile.port).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw SshTimeoutException(
          'Connection to ${profile.host}:${profile.port} timed out',
        ),
      );

      // 2. Load secrets from secure storage.
      final secrets = await store.loadProfileSecrets(profile.id);

      // 3. Build auth callbacks — never capture secret values in closures that
      //    outlive this method.
      List<SSHKeyPair>? identities;
      Future<String?> Function()? onPasswordRequest;

      switch (profile.authMethod) {
        case SshAuthMethod.password:
          final pw = secrets.password;
          if (pw == null || pw.isEmpty) {
            throw const SshAuthException('No password stored for this profile');
          }
          onPasswordRequest = () async => pw;

        case SshAuthMethod.privateKey:
          final pem = secrets.privateKey;
          if (pem == null || pem.isEmpty) {
            throw const SshAuthException(
                'No private key stored for this profile');
          }
          try {
            identities = SSHKeyPair.fromPem(pem, secrets.passphrase ?? '');
          } catch (e) {
            throw SshAuthException(
              'Failed to parse private key',
              cause: e.runtimeType, // type only — not the raw error text
            );
          }
      }

      // 4. Handshake + authenticate.
      // Keep client in a local variable until authentication succeeds so that
      // the catch block can close it without touching _client.
      client = SSHClient(
        socket,
        username: profile.username,
        onPasswordRequest: onPasswordRequest,
        identities: identities ?? [],
      );

      // Wait for the authentication exchange to settle.
      await client.authenticated;

      _client = client;
      _setState(SshConnectionState.connected);
    } on SshException {
      // Close the SSHClient if it was created before auth failed; swallow
      // double-close errors so the caller only sees the original exception.
      try { client?.close(); } catch (_) {}
      socket?.destroy();
      _client = null;
      _setState(SshConnectionState.error);
      _setState(SshConnectionState.disconnected);
      rethrow;
    } catch (e) {
      try { client?.close(); } catch (_) {}
      socket?.destroy();
      _client = null;
      _setState(SshConnectionState.error);
      _setState(SshConnectionState.disconnected);
      throw SshException(
        'Failed to connect to ${profile.host}:${profile.port}',
        cause: e.runtimeType,
      );
    }
  }

  // ------------------------------------------------------------------
  // disconnect
  // ------------------------------------------------------------------

  /// Close the active SSH session.  Safe to call when already disconnected.
  Future<void> disconnect() async {
    if (_state == SshConnectionState.disconnected) return;

    _setState(SshConnectionState.disconnecting);
    try {
      _client?.close();
    } catch (_) {
      // Suppress errors during teardown.
    } finally {
      _client = null;
      _setState(SshConnectionState.disconnected);
    }
  }

  // ------------------------------------------------------------------
  // exec  (AI single-command API — Task #3)
  // ------------------------------------------------------------------

  /// Execute a single non-interactive command and return the aggregated output.
  ///
  /// - [timeout]: maximum wall-clock time for the command (default 60 s).
  /// - [maxOutputBytes]: combined stdout+stderr cap; output is truncated when
  ///   exceeded (default 512 KiB).
  ///
  /// Throws [SshNotConnectedException] if not connected, or [SshException] on
  /// transport errors.  The result carries [SshCommandResult.timedOut] /
  /// [SshCommandResult.truncated] flags instead of throwing for those cases.
  Future<SshCommandResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 60),
    int maxOutputBytes = 512 * 1024,
  }) async {
    final client = _client;
    if (!isConnected || client == null) {
      throw SshNotConnectedException(
        'exec called while not connected',
      );
    }

    SSHSession? session;
    try {
      session = await client.execute(command);
    } catch (e) {
      throw SshException(
        'Failed to start remote command',
        cause: e.runtimeType,
      );
    }

    final stdoutBuf = <int>[];
    final stderrBuf = <int>[];
    bool truncated = false;

    void append(List<int> buf, Uint8List chunk) {
      final remaining = maxOutputBytes - stdoutBuf.length - stderrBuf.length;
      if (remaining <= 0) {
        truncated = true;
        return;
      }
      final take = chunk.length <= remaining ? chunk : chunk.sublist(0, remaining);
      buf.addAll(take);
      if (take.length < chunk.length) truncated = true;
    }

    final stdoutSub = session.stdout.listen((d) => append(stdoutBuf, d));
    final stderrSub = session.stderr.listen((d) => append(stderrBuf, d));

    bool timedOut = false;
    int exitCode = -1;

    try {
      await session.done.timeout(timeout);
      exitCode = session.exitCode ?? -1;
    } on TimeoutException {
      timedOut = true;
      try { session.close(); } catch (_) {}
      exitCode = -1;
    } finally {
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }

    return SshCommandResult(
      stdout: utf8.decode(stdoutBuf, allowMalformed: true),
      stderr: utf8.decode(stderrBuf, allowMalformed: true),
      exitCode: timedOut ? -1 : exitCode,
      timedOut: timedOut,
      truncated: truncated,
    );
  }

  // ------------------------------------------------------------------
  // openShell
  // ------------------------------------------------------------------

  /// Open an interactive PTY shell session for the xterm bridge.
  ///
  /// Returns a [SshShellSession] which owns the session lifecycle — call
  /// [SshShellSession.close] when done.  Does NOT share stdin/stdout with
  /// [exec]; each call creates an independent channel.
  Future<SshShellSession> openShell({
    int cols = 80,
    int rows = 24,
    String terminalType = 'xterm-256color',
  }) async {
    final client = _client;
    if (!isConnected || client == null) {
      throw SshNotConnectedException('openShell called while not connected');
    }

    try {
      return await SshShellSession.open(
        client,
        cols: cols,
        rows: rows,
        terminalType: terminalType,
      );
    } catch (e) {
      throw SshException('Failed to open shell session', cause: e.runtimeType);
    }
  }

  // ------------------------------------------------------------------
  // dispose
  // ------------------------------------------------------------------

  /// Release all resources.  The service must not be used after this call.
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
  }
}
