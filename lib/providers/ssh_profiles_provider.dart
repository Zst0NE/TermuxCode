import 'package:flutter/foundation.dart';

import '../models/ssh_profile.dart';
import '../services/secure_store.dart';

/// Manages the list of saved SSH connection profiles.
class SshProfilesProvider extends ChangeNotifier {
  SshProfilesProvider(this._store);

  final SecureStore _store;

  List<SshProfile> _profiles = [];
  bool _loading = false;
  String? _error;

  List<SshProfile> get profiles => List.unmodifiable(_profiles);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _profiles = await _store.loadProfiles();
    } catch (e) {
      _error = '加载连接配置失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Add a new profile from form fields (used by ProfilesScreen).
  Future<void> addProfile({
    required String label,
    required String host,
    int port = 22,
    required String username,
    required SshAuthMethod authMethod,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final profile = SshProfile.create(
      label: label,
      host: host,
      port: port,
      username: username,
      authMethod: authMethod,
    );
    _profiles = [..._profiles, profile];
    notifyListeners();
    await _store.saveProfiles(_profiles);
    await _store.saveProfileSecrets(
      profile.id,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  Future<void> updateProfile(
    SshProfile updated, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    _profiles = [
      for (final p in _profiles) p.id == updated.id ? updated : p,
    ];
    notifyListeners();
    await _store.saveProfiles(_profiles);
    if (password != null || privateKey != null || passphrase != null) {
      await _store.saveProfileSecrets(
        updated.id,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
    }
  }

  Future<void> deleteProfile(String profileId) async {
    _profiles = _profiles.where((p) => p.id != profileId).toList();
    notifyListeners();
    await _store.saveProfiles(_profiles);
    await _store.deleteProfileSecrets(profileId);
  }
}
