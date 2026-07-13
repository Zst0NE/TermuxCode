import '../agent_mode.dart';
import '../tool.dart';
import 'shell_tool.dart';

/// List a directory via `ls -la`.
class ListTool extends AgentTool {
  ListTool(this._shell);

  final ShellTool _shell;

  @override
  String get name => 'list';

  @override
  String get description => 'List directory contents (ls -la).';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Directory path (default .)',
          },
        },
      };

  @override
  ToolRisk get risk => ToolRisk.low;

  @override
  Set<AgentMode> get allowedModes => {AgentMode.plan, AgentMode.build};

  @override
  Future<ToolResultPayload> execute(ToolCallRequest request) async {
    final path = (request.arguments['path'] as String?)?.trim() ?? '.';
    if (path.contains('\n') || path.contains(';') || path.contains('|')) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'invalid path',
        isError: true,
      );
    }
    final quoted = path.replaceAll("'", r"'\''");
    return _shell.execute(ToolCallRequest(
      id: request.id,
      name: 'shell',
      arguments: {'command': "ls -la -- '$quoted' 2>&1 | head -n 200"},
    ));
  }
}
