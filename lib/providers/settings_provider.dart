import 'package:flutter/foundation.dart';

import '../models/llm_provider_config.dart';
import '../services/secure_store.dart';

/// Manages LLM provider configuration and API key persistence.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._store);

  final SecureStore _store;

  LlmProviderConfig _config = LlmProviderConfig.defaults;
  String _apiKey = '';

  LlmProviderConfig get config => _config;
  String get apiKey => _apiKey;

  /// Masked form for display in text fields (never show full key by default).
  String get maskedApiKey {
    final k = _apiKey.trim();
    if (k.isEmpty) return '';
    if (k.length <= 8) return '••••••••';
    return '${k.substring(0, 3)}••••${k.substring(k.length - 4)}';
  }

  bool get isConfigured =>
      _config.isConfigured && _apiKey.trim().isNotEmpty;

  Future<void> load() async {
    _config = await _store.loadLlmConfig();
    _apiKey = (await _store.loadLlmApiKey()) ?? '';
    notifyListeners();
  }

  Future<void> updateConfig(LlmProviderConfig config) async {
    _config = config;
    notifyListeners();
    await _store.saveLlmConfig(config);
  }

  Future<void> updateApiKey(String key) async {
    _apiKey = key;
    notifyListeners();
    await _store.saveLlmApiKey(key);
  }

  /// Combined save used by SettingsScreen.
  Future<void> saveConfig({
    required LlmProviderConfig config,
    String? apiKey,
  }) async {
    _config = config;
    await _store.saveLlmConfig(config);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      // Ignore masked placeholder re-saves.
      if (!apiKey.contains('••••')) {
        _apiKey = apiKey.trim();
        await _store.saveLlmApiKey(_apiKey);
      }
    }
    notifyListeners();
  }
}
