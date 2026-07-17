import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

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

/// Long-lived PTY session running a native coding agent on the SSH host.
///
/// Design: one extra PTY channel (not the user's interactive terminal tabs)
/// runs `claude` / `codex` / `opencode`. Phone sends text lines; stdout is
/// streamed back as [RemoteAgentEvent]s for the chat UI.
class RemoteAgentSession extends ChangeNotifier {
  RemoteAgentSession(this._ssh);

  final SshService _ssh;

  SshShellSession? _session;
  Terminal? _terminal;
  StreamSubscription<Uint8List>? _outSub;
  final _controller = StreamController<RemoteAgentEvent>.broadcast();

  RemoteCliKind? _kind;
  bool _running = false;
  final _buf = StringBuffer();

  Stream<RemoteAgentEvent> get events => _controller.stream;
  bool get isRunning => _running;
  RemoteCliKind? get kind => _kind;
  Terminal? get terminal => _terminal;

  /// Start native agent on host. Requires active SSH.
  Future<void> start(RemoteCliKind kind) async {
    if (!_ssh.isConnected) {
      throw StateError('SSH not connected');
    }
    await stop();
    _kind = kind;
    _terminal = Terminal();
    _session = await _ssh.openShell(cols: 120, rows: 40);
    _session!.attachTerminal(_terminal!);
    _running = true;
    notifyListeners();

    _outSub = _session!.stdout.listen((data) {
      final chunk = utf8.decode(data, allowMalformed: true);
      if (chunk.isEmpty) return;
      _buf.write(chunk);
      _controller.add(RemoteAgentText(chunk));
    });

    _session!.done.then((_) {
      _running = false;
      _controller.add(const RemoteAgentExit(null));
      notifyListeners();
    });

    // Launch CLI in the PTY (interactive). User text is sent via [send].
    final launch = switch (kind) {
      RemoteCliKind.claude => 'claude\n',
      RemoteCliKind.codex => 'codex\n',
      RemoteCliKind.opencode => 'opencode\n',
      RemoteCliKind.unknown => 'echo "unknown agent"; exit 1\n',
    };
    _controller.add(RemoteAgentStatus('启动远端 ${kind.label}…'));
    _session!.writeString(launch);
  }

  /// Send a user line into the remote agent PTY (as if typed + Enter).
  void send(String text) {
    final s = _session;
    if (s == null || !_running) {
      _controller.add(const RemoteAgentError('远端 Agent 未运行'));
      return;
    }
    final line = text.endsWith('\n') ? text : '$text\n';
    s.writeString(line);
  }

  Future<void> stop() async {
    await _outSub?.cancel();
    _outSub = null;
    try {
      _session?.writeString('\x03'); // Ctrl+C
      _session?.close();
    } catch (_) {}
    _session = null;
    _terminal = null;
    _running = false;
    _kind = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _controller.close();
    super.dispose();
  }
}
