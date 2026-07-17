import '../agent_mode.dart';
import '../tool.dart';
import 'shell_tool.dart';

/// Read a remote file via `head`/`cat` through [ShellTool]'s SSH session.
class ReadTool extends AgentTool {
  ReadTool(this._shell);

  final ShellTool _shell;

  @override
  String get name => 'read';

  @override
  String get description =>
      'Read a text file on the host (first ~200 lines). Path must be absolute or ~.';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'File path to read',
          },
        },
        'required': ['path'],
      };

  @override
  ToolRisk get risk => ToolRisk.low;

  @override
  Set<AgentMode> get allowedModes => {
        AgentMode.plan,
        AgentMode.ask,
        AgentMode.auto,
        AgentMode.bypass,
      };

  @override
  Future<ToolResultPayload> execute(ToolCallRequest request) async {
    final path = (request.arguments['path'] as String?)?.trim() ?? '';
    if (path.isEmpty) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'path required',
        isError: true,
      );
    }
    // Avoid trivial injection by rejecting newlines / command separators.
    if (path.contains('\n') || path.contains(';') || path.contains('|')) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'invalid path',
        isError: true,
      );
    }
    final quoted = path.replaceAll("'", r"'\''");
    final nested = ToolCallRequest(
      id: request.id,
      name: 'shell',
      arguments: {
        'command': "head -n 200 -- '$quoted' 2>&1 | head -c 32000",
      },
    );
    return _shell.execute(nested);
  }
}
