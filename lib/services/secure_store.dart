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
  static const _kChatHistory = 'agent_chat_history_v1';

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

  // --- SSH known hosts -------------------------------------------------

  static const _kKnownHosts = 'ssh_known_hosts_v1';

  String _hostKey(String host, int port) => '${host.toLowerCase()}:$port';

  Future<Map<String, dynamic>> loadKnownHosts() async {
    final raw = await _storage.read(key: _kKnownHosts);
    if (raw == null || raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveKnownHost(
    String host,
    int port, {
    required String type,
    required String fingerprint,
  }) async {
    final hosts = await loadKnownHosts();
    hosts[_hostKey(host, port)] = {'type': type, 'fingerprint': fingerprint};
    await _storage.write(key: _kKnownHosts, value: jsonEncode(hosts));
  }

  Future<void> deleteKnownHost(String host, int port) async {
    final hosts = await loadKnownHosts();
    hosts.remove(_hostKey(host, port));
    await _storage.write(key: _kKnownHosts, value: jsonEncode(hosts));
  }

  Future<({String type, String fingerprint})?> getKnownHost(
      String host, int port) async {
    final hosts = await loadKnownHosts();
    final entry = hosts[_hostKey(host, port)];
    if (entry == null) return null;
    return (
      type: entry['type'] as String,
      fingerprint: entry['fingerprint'] as String,
    );
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

  // --- Agent chat history (non-secret transcript) -------------------------

  /// Persist recent chat messages (JSON list). Keeps at most [maxMessages].
  Future<void> saveChatHistory(
    List<Map<String, dynamic>> messages, {
    int maxMessages = 100,
  }) async {
    final clipped = messages.length <= maxMessages
        ? messages
        : messages.sublist(messages.length - maxMessages);
    await _storage.write(key: _kChatHistory, value: jsonEncode(clipped));
  }

  Future<List<Map<String, dynamic>>> loadChatHistory() async {
    final raw = await _storage.read(key: _kChatHistory);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> clearChatHistory() async {
    await _storage.delete(key: _kChatHistory);
  }
}
