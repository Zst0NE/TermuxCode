import '../../services/ssh_service.dart';
import 'remote_cli_kind.dart';

/// Runs a single non-interactive prompt against a host-side coding CLI over SSH.
///
/// Prefer single-quoted remote strings to avoid shell expansion. Interactive TUIs
/// should still use the Terminal / PTY page.
class RemoteCliAdapter {
  RemoteCliAdapter(this._ssh);

  final SshService _ssh;

  /// POSIX single-quote escaping: end quote, escaped quote, reopen.
  /// Example: `it's` → `'it'\''s'`
  static String shellSingleQuote(String input) {
    return "'${input.replaceAll("'", "'\\''")}'";
  }

  /// Build best-effort non-interactive command for [kind].
  ///
  /// OpenCode: try `run`, then `exec`, then print-style flags.
  /// Claude Code: `-p` / `--print`.
  /// Codex: `exec`.
  static String buildCommand(RemoteCliKind kind, String prompt) {
    final q = shellSingleQuote(prompt);
    return switch (kind) {
      RemoteCliKind.opencode => '''
set +e
PROMPT=$q
if ! command -v opencode >/dev/null 2>&1; then
  echo "TermuxCode: 主机未找到 opencode"
  exit 127
fi
# Prefer non-interactive print/run paths for full text responses.
if opencode run --help >/dev/null 2>&1; then
  opencode run "\$PROMPT" 2>&1
  exit \$?
fi
if opencode --help 2>&1 | grep -qE -- '--print|\\s-p(\\s|\$)'; then
  opencode -p "\$PROMPT" 2>&1
  exit \$?
fi
# Last resort: some builds accept positional prompt
opencode "\$PROMPT" 2>&1
exit \$?
''',
      RemoteCliKind.claude => '''
set +e
PROMPT=$q
if ! command -v claude >/dev/null 2>&1; then
  echo "TermuxCode: 主机未找到 claude"
  exit 127
fi
# Claude Code print mode — full response, no TUI
if claude -p --help >/dev/null 2>&1 || claude --help 2>&1 | grep -qE -- '--print|\\s-p(\\s|\$)'; then
  claude -p "\$PROMPT" 2>&1
  exit \$?
fi
if claude --print --help >/dev/null 2>&1; then
  claude --print "\$PROMPT" 2>&1
  exit \$?
fi
echo "TermuxCode: claude 不支持 -p/--print，无法非交互调用"
claude --help 2>&1 | head -n 30
exit 2
''',
      RemoteCliKind.codex => '''
set +e
PROMPT=$q
if ! command -v codex >/dev/null 2>&1; then
  echo "TermuxCode: 主机未找到 codex"
  exit 127
fi
# Never start interactive TUI from chat — Codex rejects dumb TERM and TUI is noisy.
if codex exec --help >/dev/null 2>&1; then
  codex exec "\$PROMPT" 2>&1
  exit \$?
fi
if codex --help 2>&1 | grep -qE 'exec| -- '; then
  codex exec "\$PROMPT" 2>&1
  exit \$?
fi
echo "TermuxCode: codex 未找到非交互 exec 入口"
codex --help 2>&1 | head -n 40
exit 2
''',
      RemoteCliKind.unknown => 'echo "unknown CLI"; exit 1',
    };
  }

  /// Execute prompt; currently one aggregated chunk (SSH exec).
  Stream<String> runPrompt(
    RemoteCliKind kind,
    String prompt, {
    Duration timeout = const Duration(minutes: 8),
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
      maxOutputBytes: 2 * 1024 * 1024,
    );
    final body = result.combinedOutput.trim();
    if (body.isEmpty) {
      yield '(no output, exit ${result.exitCode}'
          '${result.timedOut ? ', timed out' : ''})';
    } else {
      yield body;
      if (result.timedOut) {
        yield '\n\n⏱ 命令在客户端超时截断（${timeout.inMinutes} 分钟）。';
      }
      if (result.truncated) {
        yield '\n\n… 输出过长，已截断。';
      }
      if (result.exitCode != 0 && !result.timedOut) {
        yield '\n\n(exit ${result.exitCode})';
      }
    }
  }
}
