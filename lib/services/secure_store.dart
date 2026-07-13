import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/llm_provider_config.dart';
import '../models/ssh_profile.dart';

/// Thin wrapper over [FlutterSecureStorage] that persists:
///  - SSH connection profiles (non-secret metadata) as a JSON list,
///  - per-profile secrets (password / private key / passphrase),
///  - the LLM provider config (non-secret) and its API key.
///
/// Everything goes through the OS keystore (Android Keystore / iOS Keychain),
/// so secrets never touch plain SharedPreferences.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  // --- keys ------------------------------------------------------------
  static const _kProfiles = 'ssh_profiles_v1';
  static const _kLlmConfig = 'llm_config_v1';
  static const _kLlmApiKey = 'llm_api_key_v1';

  String _pwKey(String id) => 'ssh_pw_$id';
  String _keyKey(String id) => 'ssh_key_$id';
  String _passphraseKey(String id) => 'ssh_passphrase_$id';

  // --- SSH profiles ----------------------------------------------------

  Future<List<SshProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _kProfiles);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SshProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfiles(List<SshProfile> profiles) async {
    final raw = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(key: _kProfiles, value: raw);
  }

  /// Persist a profile's secret material. Pass only what the auth method needs.
  Future<void> saveProfileSecrets(
    String profileId, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    if (password != null) {
      await _storage.write(key: _pwKey(profileId), value: password);
    }
    if (privateKey != null) {
      await _storage.write(key: _keyKey(profileId), value: privateKey);
    }
    if (passphrase != null) {
      await _storage.write(key: _passphraseKey(profileId), value: passphrase);
    }
  }

  Future<({String? password, String? privateKey, String? passphrase})>
      loadProfileSecrets(String profileId) async {
    return (
      password: await _storage.read(key: _pwKey(profileId)),
      privateKey: await _storage.read(key: _keyKey(profileId)),
      passphrase: await _storage.read(key: _passphraseKey(profileId)),
    );
  }

  Future<void> deleteProfileSecrets(String profileId) async {
    await _storage.delete(key: _pwKey(profileId));
    await _storage.delete(key: _keyKey(profileId));
    await _storage.delete(key: _passphraseKey(profileId));
  }

  // --- LLM config + key ------------------------------------------------

  Future<LlmProviderConfig> loadLlmConfig() async {
    final raw = await _storage.read(key: _kLlmConfig);
    if (raw == null || raw.isEmpty) return LlmProviderConfig.defaults;
    return LlmProviderConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLlmConfig(LlmProviderConfig config) async {
    await _storage.write(key: _kLlmConfig, value: jsonEncode(config.toJson()));
  }

  Future<String?> loadLlmApiKey() => _storage.read(key: _kLlmApiKey);

  Future<void> saveLlmApiKey(String key) async {
    await _storage.write(key: _kLlmApiKey, value: key);
  }
}
