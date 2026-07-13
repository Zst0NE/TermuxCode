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

    // One round-trip: print path per known binary.
    final batch = await _ssh.exec(
      r'''
set +e
for c in opencode claude codex; do
  p=$(command -v "$c" 2>/dev/null || which "$c" 2>/dev/null)
  if [ -n "$p" ]; then
    ver=$("$c" --version 2>/dev/null | head -n 1)
    [ -z "$ver" ] && ver=$("$c" version 2>/dev/null | head -n 1)
    echo "FOUND|$c|$p|${ver:-}"
  else
    echo "MISS|$c"
  fi
done
''',
      timeout: const Duration(seconds: 25),
    );

    final out = <RemoteCliKind, String>{};
    for (final line in batch.combinedOutput.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (!t.startsWith('FOUND|')) continue;
      final parts = t.split('|');
      if (parts.length < 3) continue;
      final name = parts[1];
      final path = parts[2];
      final ver = parts.length > 3 ? parts.sublist(3).join('|') : '';
      final kind = switch (name) {
        'opencode' => RemoteCliKind.opencode,
        'claude' => RemoteCliKind.claude,
        'codex' => RemoteCliKind.codex,
        _ => RemoteCliKind.unknown,
      };
      if (kind == RemoteCliKind.unknown) continue;
      final summary = ver.isEmpty ? path : '$path ($ver)';
      out[kind] = summary.length > 300 ? '${summary.substring(0, 300)}…' : summary;
    }
    return out;
  }
}
