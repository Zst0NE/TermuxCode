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

/// Clean PTY noise while keeping real agent text intact.
///
/// Critically removes Kitty/fixterm keyboard protocol fragments like `7u`, `?0u`,
/// which otherwise show up as garbage replies in chat.
String cleanPtyText(String input, {bool keepAnsiColors = false}) {
  var s = input;
  // OSC (ESC ] ... BEL or ST)
  s = s.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
  // Full CSI: ESC [ (private?) params intermediates final
  // Covers: ESC[?7u  ESC[>1u  ESC[0m  ESC[2J  ESC[?2004h  etc.
  s = s.replaceAll(RegExp(r'\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]'), '');
  // SS2/SS3 / other two-byte ESC
  s = s.replaceAll(RegExp(r'\x1B[NO]'), '');
  // Remaining ESC + one byte
  s = s.replaceAll(RegExp(r'\x1B.'), '');
  // Bare control chars except \n \t
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  // Leftover keyboard-protocol crumbs sometimes split across chunks: "7u" "?0u" ">1u"
  s = s.replaceAll(RegExp(r'(?<![A-Za-z0-9])[?>]?\d{1,3}u(?![A-Za-z0-9])'), '');
  // Normalize newlines
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Collapse huge blank runs but keep structure
  s = s.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  return s;
}

/// Long-lived PTY session running a native coding agent on the SSH host.
class RemoteAgentSession extends ChangeNotifier {
  RemoteAgentSession(this._ssh);

  final SshService _ssh;

  SshShellSession? _session;
  StreamSubscription<Uint8List>? _outSub;
  final _controller = StreamController<RemoteAgentEvent>.broadcast();

  /// Incomplete CSI/ESC across TCP chunks.
  String _pendingEsc = '';

  RemoteCliKind? _kind;
  bool _running = false;
  final _rawBuf = StringBuffer();
  final _cleanBuf = StringBuffer();
  DateTime _lastOutputAt = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<RemoteAgentEvent> get events => _controller.stream;
  bool get isRunning => _running;
  RemoteCliKind? get kind => _kind;
  DateTime get lastOutputAt => _lastOutputAt;
  int get outputLength => _cleanBuf.length;

  /// Full cleaned transcript (for UI).
  String get transcript => _cleanBuf.toString();

  String get tailText {
    final s = _cleanBuf.toString();
    if (s.length <= 500) return s;
    return s.substring(s.length - 500);
  }

  bool get looksLikeWaitingForInput {
    final t = tailText.trimRight();
    if (t.isEmpty) return false;
    final lines = t.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return false;
    final last = lines.last.trim();
    if (RegExp(r'[❯>:%#$]\s*$').hasMatch(last)) return true;
    if (RegExp(r'(Human|User|You)\s*:\s*$', caseSensitive: false)
        .hasMatch(last)) {
      return true;
    }
    final low = last.toLowerCase();
    if (low.contains('waiting for') ||
        low.contains('press enter') ||
        last.contains('请输入') ||
        last.contains('等待')) {
      return true;
    }
    return false;
  }

  Future<void> start(RemoteCliKind kind) async {
    if (!_ssh.isConnected) {
      throw StateError('SSH not connected');
    }
    await stop();
    _kind = kind;
    _rawBuf.clear();
    _cleanBuf.clear();
    _pendingEsc = '';
    _session = await _ssh.openShell(cols: 120, rows: 40);
    _running = true;
    _lastOutputAt = DateTime.now();
    notifyListeners();

    _outSub = _session!.stdout.listen((data) {
      final chunk = utf8.decode(data, allowMalformed: true);
      if (chunk.isEmpty) return;
      _rawBuf.write(chunk);
      final joined = '$_pendingEsc$chunk';
      // Hold trailing incomplete ESC sequence for next chunk.
      final split = _splitIncompleteEsc(joined);
      _pendingEsc = split.$2;
      final clean = cleanPtyText(split.$1);
      if (clean.isEmpty) return;
      _cleanBuf.write(clean);
      _lastOutputAt = DateTime.now();
      _controller.add(RemoteAgentText(clean));
    });

    _session!.done.then((_) {
      // Flush remainder
      if (_pendingEsc.isNotEmpty) {
        final clean = cleanPtyText(_pendingEsc);
        _pendingEsc = '';
        if (clean.isNotEmpty) {
          _cleanBuf.write(clean);
          _controller.add(RemoteAgentText(clean));
        }
      }
      _running = false;
      _controller.add(const RemoteAgentExit(null));
      notifyListeners();
    });

    // Minimal env; avoid programs thinking we support fancy keyboard protocols.
    _session!.writeString('export TERM=dumb\n');
    _session!.writeString('export NO_COLOR=1\n');
    _session!.writeString('export COLORTERM=\n');
    _session!.writeString(_launchCommand(kind));
    _controller.add(RemoteAgentStatus('在主机启动 ${kind.label}…'));
  }

  /// If buffer ends with incomplete ESC sequence, keep it for next read.
  (String complete, String hold) _splitIncompleteEsc(String s) {
    final idx = s.lastIndexOf('\x1B');
    if (idx < 0) return (s, '');
    final tail = s.substring(idx);
    // Complete CSI ends with @-~ ; OSC ends with BEL or ST
    if (tail.startsWith('\x1B[')) {
      if (RegExp(r'\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]').hasMatch(tail)) {
        return (s, '');
      }
      return (s.substring(0, idx), tail);
    }
    if (tail.startsWith('\x1B]')) {
      if (tail.contains('\x07') || tail.contains('\x1B\\')) return (s, '');
      return (s.substring(0, idx), tail);
    }
    if (tail.length == 1) return (s.substring(0, idx), tail);
    return (s, '');
  }

  String _launchCommand(RemoteCliKind kind) {
    // Launch without extra interactive banners when possible.
    return switch (kind) {
      RemoteCliKind.claude =>
        'if command -v claude >/dev/null 2>&1; then claude 2>&1; else echo "claude not found"; fi\n',
      RemoteCliKind.codex =>
        'if command -v codex >/dev/null 2>&1; then codex 2>&1; else echo "codex not found"; fi\n',
      RemoteCliKind.opencode =>
        'if command -v opencode >/dev/null 2>&1; then opencode 2>&1; else echo "opencode not found"; fi\n',
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
    _pendingEsc = '';
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    if (!_controller.isClosed) _controller.close();
    super.dispose();
  }
}
