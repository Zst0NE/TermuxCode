import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../services/ssh_service.dart';
import '../../services/ssh_shell_session.dart';
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

  /// Host-side native CLI over a dedicated SSH PTY (P2).
  remoteNative,
}

extension AgentBackendLabel on AgentBackend {
  String get labelZh => switch (this) {
        AgentBackend.remoteNative => '远程 Agent',
        AgentBackend.builtin => '内置 Agent',
      };
}

/// Strip common ANSI / OSC sequences so chat stays readable.
String stripAnsi(String input) {
  var s = input;
  s = s.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '');
  s = s.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
  s = s.replaceAll(RegExp(r'\x1B[()][0-9A-Za-z]'), '');
  s = s.replaceAll(RegExp(r'\x1B.'), '');
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s;
}

/// Long-lived PTY session running a native coding agent on the SSH host.
///
/// Separate from user terminal tabs: chat drives this pipe only.
class RemoteAgentSession extends ChangeNotifier {
  RemoteAgentSession(this._ssh);

  final SshService _ssh;

  SshShellSession? _session;
  StreamSubscription<Uint8List>? _outSub;
  final _controller = StreamController<RemoteAgentEvent>.broadcast();

  RemoteCliKind? _kind;
  bool _running = false;
  final _rawBuf = StringBuffer();
  DateTime _lastOutputAt = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<RemoteAgentEvent> get events => _controller.stream;
  bool get isRunning => _running;
  RemoteCliKind? get kind => _kind;
  DateTime get lastOutputAt => _lastOutputAt;
  int get outputLength => _rawBuf.length;

  Future<void> start(RemoteCliKind kind) async {
    if (!_ssh.isConnected) {
      throw StateError('SSH not connected');
    }
    await stop();
    _kind = kind;
    _rawBuf.clear();
    _session = await _ssh.openShell(cols: 120, rows: 40);
    _running = true;
    _lastOutputAt = DateTime.now();
    notifyListeners();

    _outSub = _session!.stdout.listen((data) {
      final chunk = utf8.decode(data, allowMalformed: true);
      if (chunk.isEmpty) return;
      final clean = stripAnsi(chunk);
      if (clean.isEmpty) return;
      _rawBuf.write(clean);
      _lastOutputAt = DateTime.now();
      _controller.add(RemoteAgentText(clean));
    });

    _session!.done.then((_) {
      _running = false;
      _controller.add(const RemoteAgentExit(null));
      notifyListeners();
    });

    _session!.writeString('export TERM=xterm-256color\n');
    _session!.writeString('export NO_COLOR=1\n');
    _session!.writeString(_launchCommand(kind));
    _controller.add(RemoteAgentStatus('在主机 PTY 启动 ${kind.label}…'));
  }

  String _launchCommand(RemoteCliKind kind) {
    return switch (kind) {
      RemoteCliKind.claude =>
        'if command -v claude >/dev/null 2>&1; then claude; else echo "claude not found"; fi\n',
      RemoteCliKind.codex =>
        'if command -v codex >/dev/null 2>&1; then codex; else echo "codex not found"; fi\n',
      RemoteCliKind.opencode =>
        'if command -v opencode >/dev/null 2>&1; then opencode; else echo "opencode not found"; fi\n',
      RemoteCliKind.unknown => 'echo "unknown agent"; exit 1\n',
    };
  }

  void send(String text) {
    final s = _session;
    if (s == null || !_running) {
      _controller.add(const RemoteAgentError('远端 Agent 未运行'));
      return;
    }
    s.writeString(text.endsWith('\n') ? text : '$text\n');
    _lastOutputAt = DateTime.now();
  }

  void interrupt() => _session?.writeString('\x03');

  Future<void> stop() async {
    await _outSub?.cancel();
    _outSub = null;
    try {
      _session?.writeString('\x03');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _session?.close();
    } catch (_) {}
    _session = null;
    _running = false;
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
