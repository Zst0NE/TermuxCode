import '../../services/ssh_service.dart';
import '../permission_gate.dart';
import '../todo_store.dart';
import '../tool_registry.dart';
import 'glob_tool.dart';
import 'grep_tool.dart';
import 'list_tool.dart';
import 'read_tool.dart';
import 'shell_tool.dart';
import 'todo_tool.dart';
import 'write_tool.dart';

/// Default tools + permission gate for TermuxCode (Claude-like subset).
({ToolRegistry registry, PermissionGate gate, ShellTool shell, TodoStore todos})
    buildDefaultAgentStack(
  SshService ssh, {
  PermissionMode mode = PermissionMode.auto,
  TodoStore? todos,
}) {
  final shell = ShellTool(ssh);
  final todoStore = todos ?? TodoStore();
  final registry = ToolRegistry([
    shell,
    ReadTool(shell),
    ListTool(shell),
    GlobTool(shell),
    GrepTool(shell),
    WriteTool(shell.execute),
    TodoTool(todoStore),
  ]);
  final gate = PermissionGate(mode: mode);
  return (
    registry: registry,
    gate: gate,
    shell: shell,
    todos: todoStore,
  );
}
