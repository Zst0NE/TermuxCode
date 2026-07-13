import '../models/chat_message.dart';
import '../models/llm_provider_config.dart';
import '../models/llm_turn_result.dart';
import '../services/llm_service.dart';
import 'agent_events.dart';
import 'agent_mode.dart';
import 'context_builder.dart';
import 'permission_gate.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// Coding-agent harness loop (Claude Code / OpenCode style).
///
/// Emits [AgentEvent]s. For [PermissionDecision.ask], emits
/// [AgentPermissionRequest] and waits on [onApprove].
class AgentRuntime {
  AgentRuntime({
    required this.llm,
    required this.registry,
    required this.gate,
    this.contextBuilder = const ContextBuilder(),
  });

  final LlmService llm;
  final ToolRegistry registry;
  final PermissionGate gate;
  final ContextBuilder contextBuilder;

  /// Run one user turn under [mode].
  Stream<AgentEvent> run({
    required String userText,
    required AgentMode mode,
    required LlmProviderConfig config,
    required String apiKey,
    required Future<bool> Function(ToolCallRequest request) onApprove,
    List<ChatMessage> history = const [],
  }) async* {
    yield AgentModeInfo(mode);
    yield AgentUserMessage(userText);

    final conversation = <ChatMessage>[
      ...history,
      ChatMessage(role: ChatRole.user, text: userText),
    ];

    final system = contextBuilder.systemPrompt(mode);
    final maxSteps = config.maxSteps;
    var steps = 0;

    // Chat mode: single completion without tools (LlmService still sends tool
    // schema today — model is instructed not to call tools).
    try {
      while (steps < maxSteps) {
        steps++;
        LlmTurnResult? turn;
        await for (final ev in llm.completeStream(
          config: config,
          apiKey: apiKey,
          messages: conversation,
          systemPrompt: system,
        )) {
          switch (ev) {
            case LlmTextDelta(:final delta):
              yield AgentAssistantDelta(delta);
            case LlmStreamDone(:final result):
              turn = result;
          }
        }
        turn ??= const LlmTurnResult();

        // Map LlmService run_command tool calls → shell ToolCallRequest.
        final mapped = <ToolCallRequest>[
          for (final tc in turn.toolCalls)
            ToolCallRequest(
              id: tc.id,
              name: 'shell',
              arguments: {
                'command': tc.command,
                if (tc.rationale != null) 'rationale': tc.rationale,
              },
            ),
        ];

        // Finalize assistant message (full text + tool cards).
        yield AgentAssistantText(turn.text, toolCalls: mapped);

        conversation.add(ChatMessage(
          role: ChatRole.assistant,
          text: turn.text,
          toolCalls: turn.toolCalls,
        ));

        if (mode == AgentMode.chat || mapped.isEmpty) {
          yield const AgentTurnDone();
          return;
        }

        // Plan mode: only allow read/list; strip shell.
        final effective = mode == AgentMode.plan
            ? mapped
                .where((r) => r.name == 'read' || r.name == 'list')
                .toList()
            : mapped;

        if (effective.isEmpty) {
          // Model asked for shell in plan — surface text only.
          yield const AgentTurnDone();
          return;
        }

        for (final req in effective) {
          final tool = registry[req.name];
          final risk = tool?.risk ?? ToolRisk.high;
          final decision = gate.evaluate(req, risk);

          var approved = decision == PermissionDecision.allow;
          if (decision == PermissionDecision.deny) {
            final denied = ToolResultPayload(
              toolCallId: req.id,
              content: 'Permission denied by policy for tool `${req.name}`.',
              isError: true,
            );
            yield AgentToolFinished(denied);
            conversation.add(ChatMessage(
              role: ChatRole.tool,
              toolResult: ToolResult(
                toolCallId: req.id,
                exitCode: -1,
                stdout: '',
                stderr: denied.content,
                declined: true,
              ),
            ));
            continue;
          }
          if (decision == PermissionDecision.ask) {
            yield AgentPermissionRequest(req, risk);
            approved = await onApprove(req);
          }

          if (!approved) {
            final declined = ToolResultPayload(
              toolCallId: req.id,
              content: 'User declined tool `${req.name}`.',
              isError: false,
            );
            yield AgentToolFinished(declined);
            conversation.add(ChatMessage(
              role: ChatRole.tool,
              toolResult: ToolResult(
                toolCallId: req.id,
                exitCode: -1,
                stdout: '',
                stderr: '',
                declined: true,
              ),
            ));
            continue;
          }

          if (tool == null) {
            final missing = ToolResultPayload(
              toolCallId: req.id,
              content: 'Unknown tool: ${req.name}',
              isError: true,
            );
            yield AgentToolFinished(missing);
            conversation.add(ChatMessage(
              role: ChatRole.tool,
              toolResult: ToolResult(
                toolCallId: req.id,
                exitCode: -1,
                stdout: '',
                stderr: missing.content,
              ),
            ));
            continue;
          }

          final result = await tool.execute(req);
          yield AgentToolFinished(result);
          conversation.add(ChatMessage(
            role: ChatRole.tool,
            toolResult: ToolResult(
              toolCallId: req.id,
              exitCode: result.isError ? 1 : 0,
              stdout: result.content,
              stderr: result.isError ? result.content : '',
              timedOut: result.timedOut,
              truncated: result.truncated,
            ),
          ));
        }

        final stop = turn.stopReason;
        if (stop != null &&
            stop != 'tool_use' &&
            stop != 'tool_calls') {
          yield const AgentTurnDone();
          return;
        }
      }

      yield AgentAssistantText(
        'Reached max steps ($maxSteps). Review output above.',
      );
      yield const AgentTurnDone();
    } catch (e) {
      yield AgentTurnError('$e');
    }
  }
}
