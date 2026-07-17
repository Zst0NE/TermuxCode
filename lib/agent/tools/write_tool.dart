import 'dart:convert';

import '../agent_mode.dart';
import '../tool.dart';

/// Write a small text file on the remote host via base64 + shell.
class WriteTool extends AgentTool {
  WriteTool(this._sshExec);

  final Future<ToolResultPayload> Function(ToolCallRequest request) _sshExec;

  @override
  String get name => 'write';

  @override
  String get description =>
      'Write content to a file on the remote host (creates/overwrites). '
      'Prefer small configs/scripts; not for huge binaries.';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute or home-relative path',
          },
          'content': {
            'type': 'string',
            'description': 'Full file contents',
          },
        },
        'required': ['path', 'content'],
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
    final path = (request.arguments['path'] as String?)?.trim() ?? '';
    final content = request.arguments['content'] as String? ?? '';
    if (path.isEmpty) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'path required',
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
    if (content.length > 200000) {
      return ToolResultPayload(
        toolCallId: request.id,
        content: 'content too large (>200KB)',
        isError: true,
      );
    }
    final p = path.replaceAll("'", r"'\''");
    final b64 = base64Encode(utf8.encode(content));
    final cmd =
        "echo '$b64' | base64 -d > '$p' && wc -c -- '$p' && echo OK_WRITE";
    return _sshExec(ToolCallRequest(
      id: request.id,
      name: 'shell',
      arguments: {
        'command': cmd,
        'rationale': 'write file $path',
      },
    ));
  }
}
