import 'package:flutter/foundation.dart';

import '../../services/ssh_service.dart';
import 'remote_cli_adapter.dart';
import 'remote_cli_detector.dart';
import 'remote_cli_kind.dart';

/// Holds detection results and runs prompts against a selected host CLI.
class RemoteCliSession extends ChangeNotifier {
  RemoteCliSession(this._ssh)
      : _detector = RemoteCliDetector(_ssh),
        _adapter = RemoteCliAdapter(_ssh);

  final SshService _ssh;
  final RemoteCliDetector _detector;
  final RemoteCliAdapter _adapter;

  Map<RemoteCliKind, String> _available = {};
  RemoteCliKind? _selected;
  bool _detecting = false;
  String? _lastError;
  final List<String> _log = [];

  Map<RemoteCliKind, String> get available => Map.unmodifiable(_available);
  RemoteCliKind? get selected => _selected;
  bool get detecting => _detecting;
  String? get lastError => _lastError;
  List<String> get log => List.unmodifiable(_log);
  bool get hasAny => _available.isNotEmpty;

  Future<void> detect() async {
    if (!_ssh.isConnected) {
      _lastError = 'SSH not connected';
      _available = {};
      _selected = null;
      notifyListeners();
      return;
    }
    _detecting = true;
    _lastError = null;
    notifyListeners();
    try {
      _available = await _detector.detect();
      _selected ??= _available.keys.isEmpty ? null : _available.keys.first;
    } catch (e) {
      _lastError = '$e';
      _available = {};
    } finally {
      _detecting = false;
      notifyListeners();
    }
  }

  void select(RemoteCliKind kind) {
    if (!_available.containsKey(kind)) return;
    _selected = kind;
    notifyListeners();
  }

  /// Append a prompt run into [log] (simple UI feed).
  Future<void> runSelected(String prompt) async {
    final kind = _selected;
    if (kind == null) {
      _lastError = 'No CLI selected';
      notifyListeners();
      return;
    }
    _log.add('> [${kind.label}] $prompt');
    notifyListeners();
    await for (final chunk in _adapter.runPrompt(kind, prompt)) {
      _log.add(chunk);
      notifyListeners();
    }
  }

  void clearLog() {
    _log.clear();
    notifyListeners();
  }
}
