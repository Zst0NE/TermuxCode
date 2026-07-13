/// Which wire protocol the LLM endpoint speaks.
///
/// [openai] covers any OpenAI-compatible `/chat/completions` endpoint
/// (OpenAI, DeepSeek, Kimi/Moonshot, Groq, local Ollama/LM Studio, ...).
/// [anthropic] covers the Anthropic `/v1/messages` endpoint.
enum LlmProviderKind { openai, anthropic }

extension LlmProviderKindLabel on LlmProviderKind {
  String get label => switch (this) {
        LlmProviderKind.openai => 'OpenAI 兼容',
        LlmProviderKind.anthropic => 'Anthropic',
      };
}

/// LLM connection settings. The API key itself is NOT stored here; it lives in
/// secure storage under a fixed key. This object only holds non-secret config.
class LlmProviderConfig {
  final LlmProviderKind kind;

  /// Base URL WITHOUT a trailing slash, e.g. `https://api.openai.com/v1`
  /// or `https://api.anthropic.com`.
  final String baseUrl;

  /// Model id, e.g. `gpt-4o`, `deepseek-chat`, `claude-sonnet-4-6`.
  final String model;

  final double temperature;

  /// Max tool-call iterations before the agent loop gives up.
  final int maxSteps;

  const LlmProviderConfig({
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.temperature = 0.2,
    this.maxSteps = 12,
  });

  /// A sensible starting point shown on first launch.
  static const LlmProviderConfig defaults = LlmProviderConfig(
    kind: LlmProviderKind.openai,
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o',
  );

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  LlmProviderConfig copyWith({
    LlmProviderKind? kind,
    String? baseUrl,
    String? model,
    double? temperature,
    int? maxSteps,
  }) {
    return LlmProviderConfig(
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxSteps: maxSteps ?? this.maxSteps,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'baseUrl': baseUrl,
        'model': model,
        'temperature': temperature,
        'maxSteps': maxSteps,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderConfig(
      kind: LlmProviderKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => LlmProviderKind.openai,
      ),
      baseUrl: (json['baseUrl'] as String?) ?? defaults.baseUrl,
      model: (json['model'] as String?) ?? defaults.model,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      maxSteps: (json['maxSteps'] as int?) ?? 12,
    );
  }
}
