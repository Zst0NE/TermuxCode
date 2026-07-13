import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

/// Wraps a dartssh2 [SSHSession] opened in PTY mode and exposes a clean API
/// for the xterm bridge to consume.
///
/// Obtain instances exclusively through [SshShellSession.open]; never
/// construct directly.
class SshShellSession {
  SshShellSession._({
    required SSHSession session,
    required int cols,
    required int rows,
  })  : _session = session,
        _cols = cols,
        _rows = rows;

  final SSHSession _session;
  int _cols;
  int _rows;

  bool _closed = false;

  /// Subscription created by [attachTerminal]; cancelled on [close].
  StreamSubscription<Uint8List>? _terminalSub;

  // ------------------------------------------------------------------
  // Factory
  // ------------------------------------------------------------------

  /// Alias for [open]; satisfies the `SshShellSession.start(...)` API contract.
  static Future<SshShellSession> start(
    SSHClient client, {
    int cols = 80,
    int rows = 24,
    String terminalType = 'xterm-256color',
  }) =>
      open(client, cols: cols, rows: rows, terminalType: terminalType);

  static Future<SshShellSession> open(
    SSHClient client, {
    int cols = 80,
    int rows = 24,
    String terminalType = 'xterm-256color',
  }) async {
    final session = await client.shell(
      pty: SSHPtyConfig(
        width: cols,
        height: rows,
        type: terminalType,
      ),
    );
    return SshShellSession._(session: session, cols: cols, rows: rows);
  }

  // ------------------------------------------------------------------
  // Streams
  // ------------------------------------------------------------------

  /// Raw bytes arriving from the remote shell (stdout + stderr merged by PTY).
  Stream<Uint8List> get stdout => _session.stdout;

  /// Completes when the remote shell process exits.
  Future<void> get done => _session.done;

  // ------------------------------------------------------------------
  // Input
  // ------------------------------------------------------------------

  /// Write raw bytes to the remote shell's stdin.
  void write(Uint8List data) {
    if (_closed) return;
    _session.write(data);
  }

  /// Write a UTF-8 encoded string to the remote shell's stdin.
  void writeString(String data) => write(Uint8List.fromList(utf8.encode(data)));

  // ------------------------------------------------------------------
  // Terminal resize
  // ------------------------------------------------------------------

  /// Notify the remote PTY of a terminal size change.
  void resize(int cols, int rows) {
    if (_closed || (_cols == cols && _rows == rows)) return;
    _cols = cols;
    _rows = rows;
    _session.resizeTerminal(cols, rows);
  }

  int get cols => _cols;
  int get rows => _rows;

  // ------------------------------------------------------------------
  // xterm bridge
  // ------------------------------------------------------------------

  /// Wire this session to an xterm [Terminal] widget.
  ///
  /// - Remote output (stdout) is decoded as UTF-8 and forwarded to
  ///   [terminal.write].
  /// - Key/paste input from the terminal is encoded as UTF-8 and sent to the
  ///   remote shell via [write].
  /// - Terminal resize events are forwarded to [resize].
  ///
  /// Calling [attachTerminal] a second time on the same session replaces the
  /// previous binding (the old subscription is cancelled first).  The binding
  /// is automatically released when [close] is called.
  void attachTerminal(Terminal terminal) {
    // Cancel any existing subscription before rebinding.
    _terminalSub?.cancel();
    _terminalSub = null;

    if (_closed) return;

    // Remote -> terminal: forward raw bytes decoded as UTF-8.
    _terminalSub = _session.stdout.listen(
      (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      onDone: () {
        // Session ended; nothing to do — callers should observe done future.
      },
    );

    // Terminal -> remote: encode user input and send to the shell.
    terminal.onOutput = (data) => write(Uint8List.fromList(utf8.encode(data)));

    // Terminal resize -> PTY resize.
    terminal.onResize = (w, h, pw, ph) => resize(w, h);
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Whether the session is still open (not yet closed).
  bool get isOpen => !_closed;

  /// Whether the session has been closed.
  bool get isClosed => _closed;

  /// Close the shell session.  Safe to call multiple times.
  ///
  /// Cancels any [attachTerminal] subscription and clears terminal callbacks
  /// before closing the underlying SSH session.
  void close() {
    if (_closed) return;
    _closed = true;
    _terminalSub?.cancel();
    _terminalSub = null;
    _session.close();
  }
}
