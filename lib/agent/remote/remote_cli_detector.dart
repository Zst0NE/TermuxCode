import '../../services/ssh_service.dart';
import 'remote_cli_kind.dart';

/// Probe which coding CLIs exist on the connected SSH host.
class RemoteCliDetector {
  RemoteCliDetector(this._ssh);

  final SshService _ssh;

  /// Returns path/version summary per kind when found.
  Future<Map<RemoteCliKind, String>> detect() async {
    if (!_ssh.isConnected) {
      throw StateError('SSH not connected');
    }

    final out = <RemoteCliKind, String>{};
    for (final kind in [
      RemoteCliKind.opencode,
      RemoteCliKind.claude,
      RemoteCliKind.codex,
    ]) {
      final name = kind.cliName;
      final result = await _ssh.exec(
        'command -v $name 2>/dev/null || which $name 2>/dev/null; '
        '($name --version 2>/dev/null || $name version 2>/dev/null || true) | head -n 3',
        timeout: const Duration(seconds: 20),
      );
      final text = result.combinedOutput.trim();
      if (text.isEmpty) continue;
      // Heuristic: first non-empty line looks like a path or contains the name.
      final lines =
          text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty);
      final joined = lines.join(' | ');
      if (joined.contains('/') ||
          joined.toLowerCase().contains(name) ||
          result.exitCode == 0) {
        // Ignore pure "not found" noise.
        if (joined.toLowerCase().contains('not found')) continue;
        out[kind] = joined.length > 300 ? '${joined.substring(0, 300)}…' : joined;
      }
    }
    return out;
  }
}
