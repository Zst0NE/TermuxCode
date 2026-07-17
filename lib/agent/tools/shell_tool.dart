import '../../services/ssh_service.dart';
import '../agent_mode.dart';
import '../tool.dart';

/// Shell tool backed by [SshService.exec] (remote host for now).
class ShellTool extends AgentTool {
  ShellTool(this._ssh);

  final SshService _ssh;

  @override
  String get name => 'shell';

  @override
  String get description =>
      'Execute a shell command on the connected host and return stdout/stderr/exit code.';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to run',
          },
          'rationale': {
            'type': 'string',
            'description': 'Short reason shown to the user for approval',
          },
        },
        'required': ['command'],
      };

  @override
  ToolRisk get risk => ToolRisk.medium;

  @override
  Set<AgentMode> get allowedModes => {
        AgentMode.ask,
        AgentMode.auto,
        AgentMode.bypass,
      };

  @override
  Future<ToolResultPayload> execute(ToolCallRequest request) async {
    final cmd = (request.arguments['command'] as String?)?.trim() ?? '';
    if (cmd.isEmpty) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'empty command',
        isError: true,
      );
    }
    if (!_ssh.isConnected) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'SSH not connected',
        isError: true,
      );
    }
    try {
      final r = await _ssh.exec(cmd);
      final buf = StringBuffer()
        ..writeln('exit_code: ${r.exitCode}')
        ..write(r.combinedOutput);
      if (r.timedOut) buf.writeln('\nstatus: timed_out');
      if (r.truncated) buf.writeln('\nnote: truncated');
      return ToolResultPayload(
        toolCallId: request.id,
        content: buf.toString(),
        isError: r.exitCode != 0 && !r.timedOut,
        timedOut: r.timedOut,
        truncated: r.truncated,
      );
    } catch (e) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'exec failed: $e',
        isError: true,
      );
    }
  }
}
