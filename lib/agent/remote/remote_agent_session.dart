import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../services/ssh_service.dart';
import '../../services/ssh_shell_session.dart';
import 'remote_cli_adapter.dart';
import 'remote_cli_kind.dart';

/// High-level events from a remote native agent session (Claude/Codex/OpenCode).
sealed class RemoteAgentEvent {
  const RemoteAgentEvent();
}

class RemoteAgentText extends RemoteAgentEvent {
  final String text;
  const RemoteAgentText(this.text);
}

class RemoteAgentStatus extends RemoteAgentEvent {
  final String message;
  const RemoteAgentStatus(this.message);
}

class RemoteAgentExit extends RemoteAgentEvent {
  final int? code;
  const RemoteAgentExit(this.code);
}

class RemoteAgentError extends RemoteAgentEvent {
  final String message;
  const RemoteAgentError(this.message);
}

/// Which brain handles the chat turn.
enum AgentBackend {
  /// Phone-side AgentRuntime + BYOK LLM + SSH tools.
  builtin,

  /// Host-side native CLI (Claude/Codex/OpenCode) — non-interactive print/exec.
  remoteNative,
}

extension AgentBackendLabel on AgentBackend {
  String get labelZh => switch (this) {
        AgentBackend.remoteNative => '远程 Agent',
        AgentBackend.builtin => '内置 Agent',
      };
}

/// Strip terminal control sequences that are NOT agent content.
/// Keeps real model text intact; removes CSI/Kitty keyboard crumbs like `7u`.
String cleanPtyText(String input) {
  var s = input;
  s = s.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
  s = s.replaceAll(RegExp(r'\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]'), '');
  s = s.replaceAll(RegExp(r'\x1B[NO]'), '');
  s = s.replaceAll(RegExp(r'\x1B.'), '');
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  // Orphan keyboard-protocol tokens when ESC was lost
  s = s.replaceAll(RegExp(r'(?<![A-Za-z0-9])[?>]?\d{1,3}u(?![A-Za-z0-9])'), '');
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  return s;
}

/// Drives host-side Claude / Codex / OpenCode for chat turns.
///
/// **Not** interactive TUI (Codex refuses TERM=dumb and TUI is noisy).
/// Each [runTurn] runs a **non-interactive** one-shot (`claude -p`, `codex exec`,
/// `opencode run`) so the full model response returns as clean text.
class RemoteAgentSession extends ChangeNotifier {
  RemoteAgentSession(this._ssh);

  final SshService _ssh;

  SshShellSession? _session;
  StreamSubscription<Uint8List>? _outSub;
  final _controller = StreamController<RemoteAgentEvent>.broadcast();

  RemoteCliKind? _kind;
  bool _running = false;
  bool _turnActive = false;
  final _cleanBuf = StringBuffer();
  DateTime _lastOutputAt = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _turnDone;

  Stream<RemoteAgentEvent> get events => _controller.stream;
  bool get isRunning => _running;
  bool get turnActive => _turnActive;
  RemoteCliKind? get kind => _kind;
  DateTime get lastOutputAt => _lastOutputAt;
  int get outputLength => _cleanBuf.length;
  String get transcript => _cleanBuf.toString();

  String get tailText {
    final s = _cleanBuf.toString();
    if (s.length <= 500) return s;
    return s.substring(s.length - 500);
  }

  bool get looksLikeWaitingForInput {
    // Non-interactive turns finish with process exit; idle heuristic secondary.
    return !_turnActive && _cleanBuf.isNotEmpty;
  }

  /// Bind preferred CLI kind (does not start a TUI).
  Future<void> start(RemoteCliKind kind) async {
    if (!_ssh.isConnected) {
      throw StateError('SSH not connected');
    }
    await stop();
    _kind = kind;
    _running = true;
    _cleanBuf.clear();
    _controller.add(RemoteAgentStatus(
      '已选择 ${kind.label}（非交互 print/exec，完整返回）',
    ));
    notifyListeners();
  }

  /// Run one chat turn via non-interactive host CLI; streams cleaned stdout.
  Future<void> runTurn(String userText) async {
    final kind = _kind;
    if (kind == null || kind == RemoteCliKind.unknown) {
      _controller.add(const RemoteAgentError('未选择远程 CLI'));
      return;
    }
    if (!_ssh.isConnected) {
      _controller.add(const RemoteAgentError('SSH 未连接'));
      return;
    }
    if (_turnActive) {
      _controller.add(const RemoteAgentError('上一轮远程调用尚未结束'));
      return;
    }

    _turnActive = true;
    _cleanBuf.clear();
    _lastOutputAt = DateTime.now();
    notifyListeners();

    final cmd = RemoteCliAdapter.buildCommand(kind, userText);
    // Wrap so we always exit the temp shell.
    final script = '''
set +e
export TERM=xterm-256color
export NO_COLOR=1
$cmd
CODE=\$?
exit \$CODE
''';

    try {
      _session = await _ssh.openShell(cols: 120, rows: 40);
      final done = Completer<void>();
      _turnDone = done;

      _outSub = _session!.stdout.listen((data) {
        final chunk = utf8.decode(data, allowMalformed: true);
        if (chunk.isEmpty) return;
        final clean = cleanPtyText(chunk);
        if (clean.isEmpty) return;
        _cleanBuf.write(clean);
        _lastOutputAt = DateTime.now();
        _controller.add(RemoteAgentText(clean));
      });

      _session!.done.then((_) {
        if (!done.isCompleted) done.complete();
      });

      _session!.writeString(script);

      // Wait for shell exit or timeout
      await done.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          try {
            _session?.writeString('\x03');
            _session?.close();
          } catch (_) {}
        },
      );
    } catch (e) {
      _controller.add(RemoteAgentError('$e'));
    } finally {
      await _outSub?.cancel();
      _outSub = null;
      try {
        _session?.close();
      } catch (_) {}
      _session = null;
      _turnActive = false;
      _turnDone = null;
      _controller.add(const RemoteAgentExit(null));
      notifyListeners();
    }
  }

  /// Back-compat: treat send as a full non-interactive turn.
  void send(String text) {
    // Fire-and-forget; caller should await runTurn when possible.
    unawaited(runTurn(text));
  }

  void interrupt() {
    try {
      _session?.writeString('\x03');
      _session?.close();
    } catch (_) {}
  }

  Future<void> stop() async {
    interrupt();
    await _outSub?.cancel();
    _outSub = null;
    try {
      _session?.close();
    } catch (_) {}
    _session = null;
    _running = false;
    _turnActive = false;
    _kind = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    if (!_controller.isClosed) _controller.close();
    super.dispose();
  }
}
