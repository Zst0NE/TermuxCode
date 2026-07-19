import 'package:uuid/uuid.dart';

/// Role of a message in the agent conversation.
enum ChatRole { system, user, assistant, tool }

/// A tool invocation requested by the model (Claude Code style multi-tool).
///
/// [command] is kept for shell/`run_command` UI compatibility.
class ToolCall {
  /// Provider-assigned id used to correlate the result back to the call.
  final String id;

  /// Tool name: shell, read, list, glob, grep, write, todo, run_command, …
  final String name;

  /// The shell command when [name] is shell/run_command; else a short display.
  final String command;

  /// Model's own short explanation (optional).
  final String? rationale;

  /// Full JSON arguments for non-shell tools.
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    this.name = 'shell',
    required this.command,
    this.rationale,
    this.arguments = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        if (rationale != null) 'rationale': rationale,
        if (arguments.isNotEmpty) 'arguments': arguments,
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'shell',
        command: json['command'] as String? ?? '',
        rationale: json['rationale'] as String?,
        arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ??
            const {},
      );
}

/// The outcome of executing a [ToolCall] over SSH.
class ToolResult {
  final String toolCallId;
  final int exitCode;
  final String stdout;
  final String stderr;

  /// True when the user declined to run the command.
  final bool declined;

  /// True when the remote command hit the client-side timeout.
  final bool timedOut;

  /// True when stdout/stderr were truncated due to max output size.
  final bool truncated;

  const ToolResult({
    required this.toolCallId,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.declined = false,
    this.timedOut = false,
    this.truncated = false,
  });

  Map<String, dynamic> toJson() => {
        'toolCallId': toolCallId,
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'declined': declined,
        'timedOut': timedOut,
        'truncated': truncated,
      };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
        toolCallId: json['toolCallId'] as String? ?? '',
        exitCode: json['exitCode'] as int? ?? -1,
        stdout: json['stdout'] as String? ?? '',
        stderr: json['stderr'] as String? ?? '',
        declined: json['declined'] as bool? ?? false,
        timedOut: json['timedOut'] as bool? ?? false,
        truncated: json['truncated'] as bool? ?? false,
      );

  /// Compact text handed back to the model. We cap size so a runaway `cat`
  /// of a huge file cannot blow up the context window.
  String toModelString({int maxChars = 8000}) {
    if (declined) {
      return 'The user declined to run this command. Do not retry it; '
          'ask for guidance or propose an alternative.';
    }
    final buf = StringBuffer();
    if (timedOut) {
      buf.writeln('status: timed_out');
      buf.writeln(
        'note: command exceeded the client timeout; output may be partial.',
      );
    }
    buf.writeln('exit_code: $exitCode');
    if (stdout.isNotEmpty) buf.write('stdout:\n$stdout\n');
    if (stderr.isNotEmpty) buf.write('stderr:\n$stderr\n');
    if (truncated) {
      buf.writeln('note: output truncated due to size limit');
    }
    var out = buf.toString();
    if (out.length > maxChars) {
      out = '${out.substring(0, maxChars)}\n...[truncated, output too long]';
    }
    return out;
  }
}

/// A single turn in the agent conversation. Depending on [role] and content,
/// this renders as a user bubble, assistant text, a tool-call card, or a
/// tool-result block.
class ChatMessage {
  final String id;
  final ChatRole role;

  /// Natural-language text. Empty for pure tool-call / tool-result turns.
  final String text;

  /// Populated when the assistant requested command execution.
  final List<ToolCall> toolCalls;

  /// Populated on [ChatRole.tool] messages.
  final ToolResult? toolResult;

  final DateTime createdAt;

  /// `remote` = host Claude/Codex/OpenCode process stream (collapsible in UI).
  final String? source;

  ChatMessage({
    String? id,
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolResult,
    DateTime? createdAt,
    this.source,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get isRemoteProcess => source == 'remote';

  static String _clip(String s, [int max = 50000]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  Map<String, dynamic> toJson() {
    Map<String, dynamic>? trJson;
    final tr = toolResult;
    if (tr != null) {
      trJson = ToolResult(
        toolCallId: tr.toolCallId,
        exitCode: tr.exitCode,
        stdout: _clip(tr.stdout),
        stderr: _clip(tr.stderr),
        declined: tr.declined,
        timedOut: tr.timedOut,
        truncated: tr.truncated,
      ).toJson();
    }
    return {
      'id': id,
      'role': role.name,
      'text': _clip(text),
      'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
      if (trJson != null) 'toolResult': trJson,
      'createdAt': createdAt.toIso8601String(),
      if (source != null) 'source': source,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? 'assistant';
    final role = ChatRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => ChatRole.assistant,
    );
    final rawCalls = json['toolCalls'] as List<dynamic>? ?? const [];
    final tr = json['toolResult'];
    return ChatMessage(
      id: json['id'] as String?,
      role: role,
      text: json['text'] as String? ?? '',
      toolCalls: rawCalls
          .map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolResult: tr is Map<String, dynamic> ? ToolResult.fromJson(tr) : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String?,
    );
  }
}
