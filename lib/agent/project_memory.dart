import 'package:flutter/foundation.dart';

import '../../services/ssh_service.dart';

/// Loads project memory files from the remote host (Claude.md / AISH.md style).
class ProjectMemory {
  ProjectMemory(this._ssh);

  final SshService _ssh;
  String _text = '';
  String _cwd = '~';

  String get text => _text;
  String get cwd => _cwd;

  bool get hasMemory => _text.trim().isNotEmpty;

  /// Best-effort load; never throws to caller for missing files.
  Future<void> refresh() async {
    if (!_ssh.isConnected) {
      _text = '';
      _cwd = '~';
      return;
    }
    try {
      final cwdRes = await _ssh.exec('pwd', timeout: const Duration(seconds: 10));
      _cwd = cwdRes.stdout.trim().isEmpty ? '~' : cwdRes.stdout.trim();
    } catch (_) {
      _cwd = '~';
    }

    const script = r'''
set +e
for f in \
  "./AISH.md" "./CLAUDE.md" "./.termuxcode/AISH.md" \
  "$HOME/AISH.md" "$HOME/CLAUDE.md" \
  "./README.md"
do
  if [ -f "$f" ]; then
    echo "===== FILE:$f ====="
    head -n 120 "$f" 2>/dev/null
    echo
  fi
done
''';
    try {
      final res = await _ssh.exec(script, timeout: const Duration(seconds: 20));
      var body = res.combinedOutput.trim();
      if (body.length > 12000) {
        body = '${body.substring(0, 12000)}\n…(memory truncated)';
      }
      _text = body;
    } catch (e) {
      debugPrint('ProjectMemory.refresh failed: $e');
      _text = '';
    }
  }

  String asSystemSuffix() {
    if (_text.isEmpty) {
      return '\nWorking directory on host: $_cwd\n';
    }
    return '''

Working directory on host: $_cwd

# Project memory (from host files if present)
$_text
''';
  }
}
