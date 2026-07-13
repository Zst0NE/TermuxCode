import '../../services/ssh_service.dart';
import 'remote_cli_kind.dart';

/// Runs a single non-interactive prompt against a host-side coding CLI over SSH.
///
/// This is the Remote-first “wrap OpenCode/Claude/Codex” path. Interactive TUI
/// sessions should still use the Terminal page / PTY.
class RemoteCliAdapter {
  RemoteCliAdapter(this._ssh);

  final SshService _ssh;

  /// Shell-escape for double-quoted remote strings.
  static String shellQuote(String input) {
    return input.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\$', r'\$').replaceAll('`', r'\`');
  }

  /// Build a best-effort non-interactive command line for [kind].
  static String buildCommand(RemoteCliKind kind, String prompt) {
    final q = shellQuote(prompt);
    return switch (kind) {
      RemoteCliKind.opencode =>
        // Prefer print/run-style flags when present; fall back to help hint.
        'if opencode run --help >/dev/null 2>&1; then opencode run "$q"; '
            'elif opencode --help 2>&1 | grep -qE -- "--print|-p"; then opencode -p "$q"; '
            'else echo "TermuxCode: could not find non-interactive opencode flags. '
            'Run interactively in the Terminal tab."; opencode --help 2>&1 | head -n 40; fi',
      RemoteCliKind.claude =>
        // Claude Code commonly supports -p/--print for non-interactive.
        'if claude -p --help >/dev/null 2>&1 || claude --help 2>&1 | grep -q -- "-p"; then '
            'claude -p "$q"; else echo "TermuxCode: claude non-interactive (-p) unavailable"; '
            'claude --help 2>&1 | head -n 40; fi',
      RemoteCliKind.codex =>
        'if codex exec --help >/dev/null 2>&1; then codex exec "$q"; '
            'elif codex --help 2>&1 | grep -q exec; then codex exec "$q"; '
            'else echo "TermuxCode: codex non-interactive entry unknown"; '
            'codex --help 2>&1 | head -n 40; fi',
      RemoteCliKind.unknown => 'echo "unknown CLI"; exit 1',
    };
  }

  /// Execute prompt; yields one chunk (aggregated exec). Future: true streaming.
  Stream<String> runPrompt(
    RemoteCliKind kind,
    String prompt, {
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    if (!_ssh.isConnected) {
      yield 'Error: SSH not connected';
      return;
    }
    if (kind == RemoteCliKind.unknown) {
      yield 'Error: unknown CLI kind';
      return;
    }
    final cmd = buildCommand(kind, prompt);
    final result = await _ssh.exec(
      cmd,
      timeout: timeout,
      maxOutputBytes: 1024 * 1024,
    );
    final body = result.combinedOutput.trim();
    if (body.isEmpty) {
      yield '(no output, exit ${result.exitCode}'
          '${result.timedOut ? ', timed out' : ''})';
    } else {
      yield body;
      if (result.timedOut) yield '\n[timed out]';
      if (result.truncated) yield '\n[truncated]';
    }
  }
}
