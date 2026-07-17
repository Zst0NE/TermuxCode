import '../agent_mode.dart';
import '../todo_store.dart';
import '../tool.dart';

/// Update session todos (Claude Code TodoWrite-like).
class TodoTool extends AgentTool {
  TodoTool(this._store);

  final TodoStore _store;

  @override
  String get name => 'todo';

  @override
  String get description =>
      'Replace the session todo list. Pass items as a JSON array of '
      '{content, status} where status is pending|in_progress|completed|cancelled.';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'description': 'Full todo list to replace with',
            'items': {
              'type': 'object',
              'properties': {
                'content': {'type': 'string'},
                'status': {
                  'type': 'string',
                  'enum': [
                    'pending',
                    'in_progress',
                    'completed',
                    'cancelled',
                  ],
                },
              },
              'required': ['content'],
            },
          },
        },
        'required': ['items'],
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
    final raw = request.arguments['items'];
    if (raw is! List) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'items must be an array',
        isError: true,
      );
    }
    final parsed = <({String content, AgentTodoStatus status})>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final content = (e['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) continue;
      final st = (e['status'] as String?)?.toLowerCase() ?? 'pending';
      final status = switch (st) {
        'in_progress' || 'in-progress' || 'doing' => AgentTodoStatus.inProgress,
        'completed' || 'done' => AgentTodoStatus.completed,
        'cancelled' || 'canceled' => AgentTodoStatus.cancelled,
        _ => AgentTodoStatus.pending,
      };
      parsed.add((content: content, status: status));
    }
    _store.replaceAll(parsed);
    return ToolResultPayload(
      toolCallId: request.id,
      content: _store.summary.isEmpty ? '(todos cleared)' : _store.summary,
    );
  }
}
