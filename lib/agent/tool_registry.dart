import 'agent_mode.dart';
import 'tool.dart';

/// Registry of [AgentTool]s filtered by [AgentMode].
class ToolRegistry {
  ToolRegistry([List<AgentTool>? tools]) : _tools = [...?tools];

  final List<AgentTool> _tools;

  void register(AgentTool tool) {
    _tools.removeWhere((t) => t.name == tool.name);
    _tools.add(tool);
  }

  AgentTool? operator [](String name) {
    for (final t in _tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  List<AgentTool> toolsFor(AgentMode mode) {
    return _tools.where((t) => t.allowedModes.contains(mode)).toList();
  }

  /// OpenAI-style tools array for the subset visible in [mode].
  List<Map<String, dynamic>> openAiToolsPayload(AgentMode mode) {
    return [
      for (final t in toolsFor(mode))
        {
          'type': 'function',
          'function': {
            'name': t.name,
            'description': t.description,
            'parameters': t.parametersSchema,
          },
        },
    ];
  }
}
