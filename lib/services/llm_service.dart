import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/llm_provider_config.dart';
import '../models/llm_turn_result.dart';

/// Low-level LLM API client.
///
/// Supports [LlmProviderKind.openai] (any `/chat/completions`-compatible
/// endpoint) and [LlmProviderKind.anthropic] (`/v1/messages`).
///
/// The API key is accepted per-call so it is never stored inside this object.
class LlmService {
  LlmService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  // ── single tool definition ──────────────────────────────────────────────

  static const _runCommandToolName = 'run_command';

  /// OpenAI-style function schema for `run_command`.
  static const _openAiTool = {
    'type': 'function',
    'function': {
      'name': _runCommandToolName,
      'description':
          'Execute a shell command on the connected remote Linux/Termux host '
          'via SSH and return its stdout, stderr, and exit code.',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The exact shell command to run.',
          },
          'rationale': {
            'type': 'string',
            'description':
                'Brief explanation of why this command is needed (shown to the user for approval).',
          },
        },
        'required': ['command'],
      },
    },
  };

  /// Anthropic-style tool schema for `run_command`.
  static const _anthropicTool = {
    'name': _runCommandToolName,
    'description':
        'Execute a shell command on the connected remote Linux/Termux host '
        'via SSH and return its stdout, stderr, and exit code.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'The exact shell command to run.',
        },
        'rationale': {
          'type': 'string',
          'description':
              'Brief explanation of why this command is needed (shown to the user for approval).',
        },
      },
      'required': ['command'],
    },
  };

  // ── public API ──────────────────────────────────────────────────────────

  /// Send [messages] to the provider and return the model's next turn.
  ///
  /// [config] supplies the endpoint, model, and sampling settings.
  /// [apiKey] is passed in headers and never logged or stored.
  /// [systemPrompt] is prepended as a system-role message (OpenAI) or the
  /// top-level `system` field (Anthropic).
  ///
  /// Throws a descriptive [LlmException] on non-2xx responses or parse errors.
  Future<LlmTurnResult> complete({
    required LlmProviderConfig config,
    required String apiKey,
    required List<ChatMessage> messages,
    required String systemPrompt,
  }) async {
    switch (config.kind) {
      case LlmProviderKind.openai:
        return _completeOpenAi(config, apiKey, messages, systemPrompt);
      case LlmProviderKind.anthropic:
        return _completeAnthropic(config, apiKey, messages, systemPrompt);
    }
  }

  // ── OpenAI ──────────────────────────────────────────────────────────────

  Future<LlmTurnResult> _completeOpenAi(
    LlmProviderConfig config,
    String apiKey,
    List<ChatMessage> messages,
    String systemPrompt,
  ) async {
    final url = _openAiUrl(config.baseUrl);

    final body = jsonEncode({
      'model': config.model,
      'temperature': config.temperature,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ..._toOpenAiMessages(messages),
      ],
      'tools': [_openAiTool],
      'tool_choice': 'auto',
    });

    final response = await _post(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    final Map<String, dynamic> json =
        jsonDecode(response) as Map<String, dynamic>;

    final choices = json['choices'] as List<dynamic>;
    if (choices.isEmpty) {
      throw LlmException('OpenAI response contained no choices');
    }
    final message = choices[0]['message'] as Map<String, dynamic>;
    final stopReason = choices[0]['finish_reason'] as String?;

    final text = (message['content'] as String?) ?? '';
    final rawCalls = message['tool_calls'] as List<dynamic>? ?? [];

    final toolCalls = rawCalls.map((tc) {
      final fn = tc['function'] as Map<String, dynamic>;
      final args = jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
      return ToolCall(
        id: tc['id'] as String,
        command: args['command'] as String,
        rationale: args['rationale'] as String?,
      );
    }).toList();

    return LlmTurnResult(
      text: text,
      toolCalls: toolCalls,
      stopReason: stopReason,
    );
  }

  /// Build the `/chat/completions` endpoint URL.
  ///
  /// If [baseUrl] already ends with `/chat/completions` it is used verbatim;
  /// otherwise the path is appended.
  Uri _openAiUrl(String baseUrl) {
    final trimmed = baseUrl.trimRight().replaceAll(RegExp(r'/$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse('$trimmed/chat/completions');
  }

  List<Map<String, dynamic>> _toOpenAiMessages(List<ChatMessage> messages) {
    final result = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          // Handled separately as the leading system message.
          break;

        case ChatRole.user:
          result.add({'role': 'user', 'content': m.text});

        case ChatRole.assistant:
          if (m.hasToolCalls) {
            result.add({
              'role': 'assistant',
              'content': m.text.isEmpty ? null : m.text,
              'tool_calls': m.toolCalls
                  .map((tc) => {
                        'id': tc.id,
                        'type': 'function',
                        'function': {
                          'name': _runCommandToolName,
                          'arguments': jsonEncode({
                            'command': tc.command,
                            if (tc.rationale != null)
                              'rationale': tc.rationale,
                          }),
                        },
                      })
                  .toList(),
            });
          } else {
            result.add({'role': 'assistant', 'content': m.text});
          }

        case ChatRole.tool:
          final tr = m.toolResult;
          if (tr != null) {
            result.add({
              'role': 'tool',
              'tool_call_id': tr.toolCallId,
              'content': tr.toModelString(),
            });
          }
      }
    }
    return result;
  }

  // ── Anthropic ───────────────────────────────────────────────────────────

  Future<LlmTurnResult> _completeAnthropic(
    LlmProviderConfig config,
    String apiKey,
    List<ChatMessage> messages,
    String systemPrompt,
  ) async {
    final url = _anthropicUrl(config.baseUrl);

    final body = jsonEncode({
      'model': config.model,
      'max_tokens': 4096,
      'temperature': config.temperature,
      'system': systemPrompt,
      'tools': [_anthropicTool],
      'messages': _toAnthropicMessages(messages),
    });

    final response = await _post(
      url: url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    );

    final Map<String, dynamic> json =
        jsonDecode(response) as Map<String, dynamic>;

    final stopReason = json['stop_reason'] as String?;
    final content = json['content'] as List<dynamic>;

    final textBuf = StringBuffer();
    final toolCalls = <ToolCall>[];

    for (final block in content) {
      final type = (block as Map<String, dynamic>)['type'] as String;
      if (type == 'text') {
        textBuf.write(block['text'] as String);
      } else if (type == 'tool_use') {
        final input = block['input'] as Map<String, dynamic>;
        toolCalls.add(ToolCall(
          id: block['id'] as String,
          command: input['command'] as String,
          rationale: input['rationale'] as String?,
        ));
      }
    }

    return LlmTurnResult(
      text: textBuf.toString(),
      toolCalls: toolCalls,
      stopReason: stopReason,
    );
  }

  /// Build the `/v1/messages` endpoint URL.
  ///
  /// Smart-splices the path: if [baseUrl] already contains `/v1/messages`
  /// it is returned verbatim; if it contains `/v1` (but not the messages
  /// segment) `/messages` is appended; otherwise `/v1/messages` is appended.
  Uri _anthropicUrl(String baseUrl) {
    final trimmed = baseUrl.trimRight().replaceAll(RegExp(r'/$'), '');
    if (trimmed.contains('/v1/messages')) return Uri.parse(trimmed);
    if (trimmed.endsWith('/v1')) return Uri.parse('$trimmed/messages');
    return Uri.parse('$trimmed/v1/messages');
  }

  List<Map<String, dynamic>> _toAnthropicMessages(List<ChatMessage> messages) {
    final result = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          // Passed as the top-level `system` field, not in messages array.
          break;

        case ChatRole.user:
          result.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': m.text}
            ],
          });

        case ChatRole.assistant:
          final contentBlocks = <Map<String, dynamic>>[];
          if (m.text.isNotEmpty) {
            contentBlocks.add({'type': 'text', 'text': m.text});
          }
          for (final tc in m.toolCalls) {
            contentBlocks.add({
              'type': 'tool_use',
              'id': tc.id,
              'name': _runCommandToolName,
              'input': {
                'command': tc.command,
                if (tc.rationale != null) 'rationale': tc.rationale,
              },
            });
          }
          if (contentBlocks.isNotEmpty) {
            result.add({'role': 'assistant', 'content': contentBlocks});
          }

        case ChatRole.tool:
          final tr = m.toolResult;
          if (tr != null) {
            result.add({
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': tr.toolCallId,
                  'content': tr.toModelString(),
                }
              ],
            });
          }
      }
    }
    return result;
  }

  // ── HTTP helper ─────────────────────────────────────────────────────────

  Future<String> _post({
    required Uri url,
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(url, headers: headers, body: body)
          .timeout(timeout);
    } on TimeoutException {
      throw LlmException('请求超时（${timeout.inSeconds}s）: ${url.host}');
    } catch (e) {
      throw LlmException('Network error contacting ${url.host}: ${e.runtimeType}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Extract provider error message without echoing auth headers.
      String detail;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final err = json['error'];
        if (err is Map) {
          detail = (err['message'] as String?) ?? response.body;
        } else {
          detail = response.body;
        }
      } catch (_) {
        detail = response.body;
      }
      // Cap detail length so a multi-KB HTML error page doesn't fill the UI.
      if (detail.length > 400) detail = '${detail.substring(0, 400)}…';
      throw LlmException(
        'HTTP ${response.statusCode} from ${url.host}: $detail',
        statusCode: response.statusCode,
      );
    }

    return response.body;
  }

  /// Release the underlying HTTP client.
  void dispose() => _http.close();
}

// ── Exception ─────────────────────────────────────────────────────────────

/// Thrown by [LlmService] for API errors, network failures, and parse errors.
class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode});

  final String message;

  /// HTTP status code when the error originated from a non-2xx response;
  /// `null` for network or parse errors.
  final int? statusCode;

  @override
  String toString() => statusCode != null
      ? 'LlmException($statusCode): $message'
      : 'LlmException: $message';
}
