import 'agent_mode.dart';

/// Risk level for a tool or a concrete invocation.
enum ToolRisk {
  /// Safe reads / metadata.
  low,

  /// May change workspace state or run mild commands.
  medium,

  /// Destructive or security-sensitive.
  high,
}

/// One tool invocation requested by the model (provider-agnostic).
class ToolCallRequest {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCallRequest({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Result of executing a tool, fed back into the model.
class ToolResultPayload {
  final String toolCallId;
  final String content;
  final bool isError;
  final bool timedOut;
  final bool truncated;

  const ToolResultPayload({
    required this.toolCallId,
    required this.content,
    this.isError = false,
    this.timedOut = false,
    this.truncated = false,
  });
}

/// A pluggable tool in the Agent Harness.
abstract class AgentTool {
  String get name;
  String get description;

  /// JSON-Schema-like map for the `parameters` object.
  Map<String, dynamic> get parametersSchema;

  ToolRisk get risk;

  /// Which modes may see this tool at all (permission still applies).
  Set<AgentMode> get allowedModes;

  Future<ToolResultPayload> execute(ToolCallRequest request);
}
