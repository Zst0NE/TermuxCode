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
if command -v opencode >/dev/null 2>&1; then
  # Newer CLIs often expose a non-interactive "run" subcommand.
  if opencode run --help >/dev/null 2>&1; then
    opencode run "\$PROMPT"
    exit \$?
  fi
  if opencode exec --help >/dev/null 2>&1; then
    opencode exec "\$PROMPT"
    exit \$?
  fi
  HELP=\$(opencode --help 2>&1 | head -n 80)
  if echo "\$HELP" | grep -qE -- '--print|\\s-p(\\s|\$)'; then
    opencode -p "\$PROMPT"
    exit \$?
  fi
  echo "TermuxCode: OpenCode 已安装，但未找到非交互入口（run/exec/-p）。"
  echo "请在「终端」页交互运行: opencode"
  echo "----- opencode --help (截断) -----"
  echo "\$HELP"
  exit 2
else
  echo "TermuxCode: 主机未找到 opencode"
  exit 127
fi
''',
      RemoteCliKind.claude => '''
set +e
PROMPT=$q
if command -v claude >/dev/null 2>&1; then
  HELP=\$(claude --help 2>&1 | head -n 80)
  if echo "\$HELP" | grep -qE -- '--print|\\s-p(\\s|\$)' || claude -p --help >/dev/null 2>&1; then
    claude -p "\$PROMPT"
    exit \$?
  fi
  if claude --print --help >/dev/null 2>&1; then
    claude --print "\$PROMPT"
    exit \$?
  fi
  echo "TermuxCode: Claude Code 已安装，但未找到 -p/--print 非交互模式。"
  echo "请在「终端」页运行: claude"
  echo "----- claude --help (截断) -----"
  echo "\$HELP"
  exit 2
else
  echo "TermuxCode: 主机未找到 claude"
  exit 127
fi
''',
      RemoteCliKind.codex => '''
set +e
PROMPT=$q
if command -v codex >/dev/null 2>&1; then
  if codex exec --help >/dev/null 2>&1; then
    codex exec "\$PROMPT"
    exit \$?
  fi
  HELP=\$(codex --help 2>&1 | head -n 80)
  if echo "\$HELP" | grep -q exec; then
    codex exec "\$PROMPT"
    exit \$?
  fi
  echo "TermuxCode: Codex 已安装，但未找到非交互 exec 入口。"
  echo "请在「终端」页运行: codex"
  echo "----- codex --help (截断) -----"
  echo "\$HELP"
  exit 2
else
  echo "TermuxCode: 主机未找到 codex"
  exit 127
fi
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
