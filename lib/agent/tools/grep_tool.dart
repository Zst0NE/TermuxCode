import '../../services/ssh_service.dart';
import '../agent_mode.dart';
import '../tool.dart';
import 'shell_tool.dart';

/// Search file contents on the remote host (`grep -R`).
class GrepTool extends AgentTool {
  GrepTool(this._shell);

  final ShellTool _shell;

  @override
  String get name => 'grep';

  @override
  String get description =>
      'Search for a text pattern in files on the remote host (grep -RIn).';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Text/regex to search',
          },
          'path': {
            'type': 'string',
            'description': 'Directory or file (default .)',
          },
        },
        'required': ['pattern'],
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
    final pattern = (request.arguments['pattern'] as String?)?.trim() ?? '';
    final path = (request.arguments['path'] as String?)?.trim() ?? '.';
    if (pattern.isEmpty) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'pattern required',
        isError: true,
      );
    }
    if (path.contains('\n') || path.contains(';') || path.contains('|')) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'invalid path',
        isError: true,
      );
    }
    final p = path.replaceAll("'", r"'\''");
    final pat = pattern.replaceAll("'", r"'\''");
    final cmd =
        "grep -RIn --exclude-dir=.git --exclude-dir=node_modules "
        "--exclude-dir=.dart_tool -e '$pat' '$p' 2>/dev/null | head -n 80";
    return _shell.execute(ToolCallRequest(
      id: request.id,
      name: 'shell',
      arguments: {'command': cmd},
    ));
  }
}
