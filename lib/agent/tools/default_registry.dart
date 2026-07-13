import '../../services/ssh_service.dart';
import '../permission_gate.dart';
import '../tool_registry.dart';
import 'list_tool.dart';
import 'read_tool.dart';
import 'shell_tool.dart';

/// Default tools + permission gate for TermuxCode.
({ToolRegistry registry, PermissionGate gate, ShellTool shell})
    buildDefaultAgentStack(SshService ssh, {PermissionMode mode = PermissionMode.ask}) {
  final shell = ShellTool(ssh);
  final registry = ToolRegistry([
    shell,
    ReadTool(shell),
    ListTool(shell),
  ]);
  final gate = PermissionGate(mode: mode);
  return (registry: registry, gate: gate, shell: shell);
}
