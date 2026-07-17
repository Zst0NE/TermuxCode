import 'package:flutter/foundation.dart';

/// In-session todo list (Claude Code TodoWrite-style, lightweight).
class AgentTodo {
  AgentTodo({
    required this.id,
    required this.content,
    this.status = AgentTodoStatus.pending,
  });

  final String id;
  String content;
  AgentTodoStatus status;
}

enum AgentTodoStatus { pending, inProgress, completed, cancelled }

extension AgentTodoStatusX on AgentTodoStatus {
  String get label => switch (this) {
        AgentTodoStatus.pending => '待办',
        AgentTodoStatus.inProgress => '进行中',
        AgentTodoStatus.completed => '完成',
        AgentTodoStatus.cancelled => '取消',
      };
}

class TodoStore extends ChangeNotifier {
  final List<AgentTodo> _items = [];
  int _seq = 0;

  List<AgentTodo> get items => List.unmodifiable(_items);

  String get summary {
    if (_items.isEmpty) return '';
    final lines = _items.map((t) {
      final mark = switch (t.status) {
        AgentTodoStatus.completed => 'x',
        AgentTodoStatus.inProgress => '>',
        AgentTodoStatus.cancelled => '-',
        AgentTodoStatus.pending => ' ',
      };
      return '[$mark] ${t.content}';
    });
    return 'Todos:\n${lines.join('\n')}';
  }

  void replaceAll(List<({String content, AgentTodoStatus status})> next) {
    _items
      ..clear()
      ..addAll([
        for (final e in next)
          AgentTodo(
            id: 't${++_seq}',
            content: e.content,
            status: e.status,
          ),
      ]);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
