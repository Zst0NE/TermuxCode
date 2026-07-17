import '../agent_mode.dart';
import '../tool.dart';
import 'shell_tool.dart';

/// Find files by glob-ish pattern on the remote host (`find`).
class GlobTool extends AgentTool {
  GlobTool(this._shell);

  final ShellTool _shell;

  @override
  String get name => 'glob';

  @override
  String get description =>
      'Find files on the remote host. pattern e.g. "*.dart", "**/*.md" (mapped to find).';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Filename pattern, e.g. *.py or package.json',
          },
          'path': {
            'type': 'string',
            'description': 'Root directory (default .)',
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
    if (_unsafe(path) || _unsafe(pattern)) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'invalid path/pattern',
        isError: true,
      );
    }
    final p = path.replaceAll("'", r"'\''");
    final name = pattern.replaceAll("'", r"'\''");
    // Use -name for simple patterns; strip **/
    final simple = name.replaceAll('**/', '').replaceAll('**', '*');
    final cmd =
        "find '$p' -type f -name '$simple' 2>/dev/null | head -n 200";
    return _shell.execute(ToolCallRequest(
      id: request.id,
      name: 'shell',
      arguments: {'command': cmd},
    ));
  }

  bool _unsafe(String s) =>
      s.contains('\n') || s.contains(';') || s.contains('|') || s.contains('`');
}
