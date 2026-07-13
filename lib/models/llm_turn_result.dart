import 'chat_message.dart';

/// The result of a single LLM API call.
///
/// [text] is the assistant's natural-language reply (may be empty when the
/// model responds with tool calls only).  [toolCalls] lists any `run_command`
/// invocations the model requested.  Both fields can be non-empty when the
/// model mixes prose with tool use.
class LlmTurnResult {
  /// Natural-language content from the assistant. Empty string when the model
  /// only emitted tool calls.
  final String text;

  /// Tool calls requested by the model in this turn.
  final List<ToolCall> toolCalls;

  /// Raw stop reason string as returned by the provider
  /// (`"stop"`, `"tool_use"`, `"end_turn"`, `"max_tokens"`, …).
  final String? stopReason;

  const LlmTurnResult({
    this.text = '',
    this.toolCalls = const [],
    this.stopReason,
  });

  /// True when the model requested at least one tool invocation.
  bool get hasToolCalls => toolCalls.isNotEmpty;

  /// True when the model produced natural-language text.
  bool get hasText => text.isNotEmpty;
}

/// Incremental events from [LlmService.completeStream].
sealed class LlmStreamEvent {
  const LlmStreamEvent();
}

/// A UTF-8 text delta for the assistant reply.
class LlmTextDelta extends LlmStreamEvent {
  final String delta;
  const LlmTextDelta(this.delta);
}

/// Stream finished; [result] is the full turn (text + tool calls).
class LlmStreamDone extends LlmStreamEvent {
  final LlmTurnResult result;
  const LlmStreamDone(this.result);
}
