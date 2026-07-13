import '../models/chat_message.dart';
import '../models/llm_provider_config.dart';
import 'llm_service.dart';
import 'ssh_service.dart';

/// System prompt handed to the model at the start of every agent loop.
const _kSystemPrompt = '''
You are an assistant for a remote Linux/Termux host connected over SSH.
You help the user by running shell commands via the run_command tool and
explaining the results in plain language.

Guidelines:
- Before running a destructive or irreversible command (rm, chmod, kill,
  package removal, etc.), briefly state what it does and why.
- Prefer targeted, minimal commands over broad ones.
- If a command fails, read the error output and try a corrective approach
  before asking the user for help.
- When the task is complete, summarise what was done in one or two sentences.
''';

/// Runs one complete user→agent interaction cycle.
///
/// The caller drives approval and rendering by listening to the returned
/// [Stream<ChatMessage>]:
///
/// ```dart
/// agentService.run(
///   userText: 'How much disk space is free?',
///   config: config,
///   apiKey: apiKey,
///   onApprove: (call) async => await showApprovalDialog(call),
/// ).listen((msg) => setState(() => messages.add(msg)));
/// ```
///
/// Emitted messages in order:
///   1. The user message itself ([ChatRole.user]).
///   2. For each LLM turn: an assistant message ([ChatRole.assistant]) whose
///      [ChatMessage.toolCalls] may be non-empty.
///   3. For each approved tool call: a tool-result message ([ChatRole.tool]).
///   4. A final assistant text message once the loop ends.
class AgentService {
  AgentService({
    required SshService sshService,
    LlmService? llmService,
  })  : _ssh = sshService,
        _llm = llmService ?? LlmService();

  final SshService _ssh;
  final LlmService _llm;

  /// Run the agent loop for a single user turn.
  ///
  /// [userText] is the raw user input.
  /// [config] and [apiKey] describe the LLM endpoint to call.
  /// [onApprove] is called once per [ToolCall] before execution; return `true`
  ///   to execute or `false` to decline.
  /// [history] is the existing conversation so the model has context; the
  ///   returned stream messages should be appended to it by the caller.
  ///
  /// The stream closes normally when the loop ends.  On unrecoverable errors
  /// (e.g. LLM unreachable, SSH disconnected) the stream closes with an error.
  Stream<ChatMessage> run({
    required String userText,
    required LlmProviderConfig config,
    required String apiKey,
    required Future<bool> Function(ToolCall call) onApprove,
    List<ChatMessage> history = const [],
  }) {
    // Use an async* generator so errors propagate naturally through the stream.
    return _run(
      userText: userText,
      config: config,
      apiKey: apiKey,
      onApprove: onApprove,
      history: history,
    );
  }

  Stream<ChatMessage> _run({
    required String userText,
    required LlmProviderConfig config,
    required String apiKey,
    required Future<bool> Function(ToolCall call) onApprove,
    required List<ChatMessage> history,
  }) async* {
    // 1. Emit the user message so the caller can add it to their list.
    final userMsg = ChatMessage(role: ChatRole.user, text: userText);
    yield userMsg;

    // Build the working conversation: prior history + this user turn.
    final conversation = [...history, userMsg];

    int steps = 0;
    final maxSteps = config.maxSteps;

    while (steps < maxSteps) {
      steps++;

      // 2. Call the LLM.
      final turn = await _llm.complete(
        config: config,
        apiKey: apiKey,
        messages: conversation,
        systemPrompt: _kSystemPrompt,
      );

      // 3. Emit the assistant message.
      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        text: turn.text,
        toolCalls: turn.toolCalls,
      );
      yield assistantMsg;
      conversation.add(assistantMsg);

      // 4. If no tool calls, the model is done.
      if (turn.toolCalls.isEmpty) break;

      // 5. Process each tool call sequentially.
      for (final call in turn.toolCalls) {
        final approved = await onApprove(call);

        final ToolResult result;
        if (!approved) {
          result = ToolResult(
            toolCallId: call.id,
            exitCode: -1,
            stdout: '',
            stderr: '',
            declined: true,
          );
        } else if (!_ssh.isConnected) {
          result = ToolResult(
            toolCallId: call.id,
            exitCode: -1,
            stdout: '',
            stderr: 'SSH not connected — cannot execute command.',
            declined: false,
          );
        } else {
          final sshResult = await _ssh.exec(call.command);
          result = ToolResult(
            toolCallId: call.id,
            exitCode: sshResult.exitCode,
            stdout: sshResult.stdout,
            stderr: sshResult.stderr,
            timedOut: sshResult.timedOut,
            truncated: sshResult.truncated,
          );
        }

        final toolMsg = ChatMessage(
          role: ChatRole.tool,
          toolResult: result,
        );
        yield toolMsg;
        conversation.add(toolMsg);
      }

      // 6. Check stop reason: if the model signalled end_turn or stop without
      //    tool calls in the previous block we already broke above; here we
      //    handle providers that set stop_reason = 'tool_use' to continue.
      final stopReason = turn.stopReason;
      if (stopReason != null &&
          stopReason != 'tool_use' &&
          stopReason != 'tool_calls') {
        break;
      }
    }

    // Emit a synthetic cap message when the safety limit is reached so the
    // user sees feedback rather than a silent stream close.
    if (steps >= maxSteps && conversation.last.role != ChatRole.assistant) {
      yield ChatMessage(
        role: ChatRole.assistant,
        text: 'Reached the maximum number of steps ($maxSteps). '
            'The task may be incomplete — please review the output above.',
      );
    }
  }
}
