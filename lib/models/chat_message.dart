import 'package:uuid/uuid.dart';

/// Role of a message in the agent conversation.
enum ChatRole { system, user, assistant, tool }

/// A request from the model to run a shell command on the connected host.
///
/// This is our single tool: `run_command`. The model emits one (or more) of
/// these; the app asks the user to approve, executes over SSH, then feeds the
/// [ToolResult] back into the conversation.
class ToolCall {
  /// Provider-assigned id used to correlate the result back to the call.
  final String id;

  /// The shell command the model wants to run.
  final String command;

  /// Model's own short explanation of why it wants to run this. Optional;
  /// populated from the tool arguments when present.
  final String? rationale;

  const ToolCall({
    required this.id,
    required this.command,
    this.rationale,
  });
}

/// The outcome of executing a [ToolCall] over SSH.
class ToolResult {
  final String toolCallId;
  final int exitCode;
  final String stdout;
  final String stderr;

  /// True when the user declined to run the command.
  final bool declined;

  const ToolResult({
    required this.toolCallId,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.declined = false,
  });

  /// Compact text handed back to the model. We cap size so a runaway `cat`
  /// of a huge file cannot blow up the context window.
  String toModelString({int maxChars = 8000}) {
    if (declined) {
      return 'The user declined to run this command. Do not retry it; '
          'ask for guidance or propose an alternative.';
    }
    final buf = StringBuffer('exit_code: $exitCode\n');
    if (stdout.isNotEmpty) buf.write('stdout:\n$stdout\n');
    if (stderr.isNotEmpty) buf.write('stderr:\n$stderr\n');
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

  ChatMessage({
    String? id,
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolResult,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get hasToolCalls => toolCalls.isNotEmpty;
}
