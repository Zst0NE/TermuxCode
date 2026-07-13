/// Immutable result of a single SSH command execution.
class SshCommandResult {
  final String stdout;
  final String stderr;

  /// Exit code reported by the remote process. `-1` when [timedOut] is true.
  final int exitCode;

  /// Whether the command was terminated because it exceeded the timeout.
  final bool timedOut;

  /// Whether the output was cut off due to a size limit.
  final bool truncated;

  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.timedOut,
    required this.truncated,
  });

  bool get succeeded => !timedOut && exitCode == 0;

  /// Concatenates stdout and stderr, separated by a newline when both are
  /// non-empty.  Useful for surfaces that want a single text blob.
  String get combinedOutput {
    if (stderr.isEmpty) return stdout;
    if (stdout.isEmpty) return stderr;
    return '$stdout\n$stderr';
  }

  @override
  String toString() =>
      'SshCommandResult(exitCode: $exitCode, timedOut: $timedOut, '
      'truncated: $truncated, stdout: ${stdout.length} chars)';
}
