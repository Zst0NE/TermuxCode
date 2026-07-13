import 'agent_mode.dart';
import 'tool.dart';

/// Events emitted by [AgentRuntime].
sealed class AgentEvent {
  const AgentEvent();
}

class AgentUserMessage extends AgentEvent {
  final String text;
  const AgentUserMessage(this.text);
}

class AgentAssistantText extends AgentEvent {
  final String text;
  final List<ToolCallRequest> toolCalls;
  const AgentAssistantText(this.text, {this.toolCalls = const []});
}

/// Permission required before a tool runs (UI should resolve via completer).
class AgentPermissionRequest extends AgentEvent {
  final ToolCallRequest request;
  final ToolRisk risk;
  const AgentPermissionRequest(this.request, this.risk);
}

class AgentToolFinished extends AgentEvent {
  final ToolResultPayload result;
  const AgentToolFinished(this.result);
}

class AgentTurnDone extends AgentEvent {
  const AgentTurnDone();
}

class AgentTurnError extends AgentEvent {
  final String message;
  const AgentTurnError(this.message);
}

class AgentModeInfo extends AgentEvent {
  final AgentMode mode;
  const AgentModeInfo(this.mode);
}
