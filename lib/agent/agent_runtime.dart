import '../models/chat_message.dart';
import '../models/llm_provider_config.dart';
import '../models/llm_turn_result.dart';
import '../services/llm_service.dart';
import 'agent_events.dart';
import 'agent_mode.dart';
import 'context_builder.dart';
import 'permission_gate.dart';
import 'project_memory.dart';
import 'todo_store.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// Coding-agent harness loop (Claude Code / OpenCode style).
class AgentRuntime {
  AgentRuntime({
    required this.llm,
    required this.registry,
    required this.gate,
    this.contextBuilder = const ContextBuilder(),
    this.memory,
    this.todos,
  });

  final LlmService llm;
  final ToolRegistry registry;
  final PermissionGate gate;
  final ContextBuilder contextBuilder;
  final ProjectMemory? memory;
  final TodoStore? todos;

  /// Run one user turn under [mode].
  ///
  /// [enableTools] false = pure chat (no tool schemas), for offline/no-SSH Q&A.
  Stream<AgentEvent> run({
    required String userText,
    required AgentMode mode,
    required LlmProviderConfig config,
    required String apiKey,
    required Future<bool> Function(ToolCallRequest request) onApprove,
    List<ChatMessage> history = const [],
    bool enableTools = true,
  }) async* {
    yield AgentModeInfo(mode);
    yield AgentUserMessage(userText);

    final conversation = <ChatMessage>[
      ...history,
      ChatMessage(role: ChatRole.user, text: userText),
    ];

    final todoHint =
        (todos != null && todos!.summary.isNotEmpty) ? '\n${todos!.summary}\n' : '';
    final mem = memory?.asSystemSuffix() ?? '';
    var system = '${contextBuilder.systemPrompt(mode)}$todoHint$mem';
    if (!enableTools) {
      system = '''
$system

# Important
Tools are DISABLED for this turn (no remote host connected).
Answer helpfully in natural language only. Do not pretend to run commands.
If the user needs remote execution, ask them to connect a server first.
''';
    }
    final maxSteps = enableTools ? config.maxSteps : 1;
    var steps = 0;
    final tools =
        enableTools ? registry.openAiToolsPayload(mode) : <Map<String, dynamic>>[];

    try {
      while (steps < maxSteps) {
        steps++;
        LlmTurnResult? turn;
        await for (final ev in llm.completeStream(
          config: config,
          apiKey: apiKey,
          messages: conversation,
          systemPrompt: system,
          tools: tools.isEmpty ? const [] : tools,
        )) {
          switch (ev) {
            case LlmTextDelta(:final delta):
              yield AgentAssistantDelta(delta);
            case LlmStreamDone(:final result):
              turn = result;
          }
        }
        turn ??= const LlmTurnResult();

        final mapped = enableTools
            ? <ToolCallRequest>[
                for (final tc in turn.toolCalls)
                  ToolCallRequest(
                    id: tc.id,
                    name: tc.name.isEmpty ? 'shell' : tc.name,
                    arguments: tc.arguments.isNotEmpty
                        ? tc.arguments
                        : {
                            if (tc.command.isNotEmpty) 'command': tc.command,
                            if (tc.rationale != null) 'rationale': tc.rationale,
                          },
                  ),
              ]
            : <ToolCallRequest>[];

        yield AgentAssistantText(turn.text, toolCalls: mapped);

        conversation.add(ChatMessage(
          role: ChatRole.assistant,
          text: turn.text,
          toolCalls: enableTools ? turn.toolCalls : const [],
        ));

        if (!enableTools || mapped.isEmpty) {
          yield const AgentTurnDone();
          return;
        }

        // Plan: only read/list/glob/grep/todo
        final effective = mode == AgentMode.plan
            ? mapped
                .where((r) =>
                    r.name == 'read' ||
                    r.name == 'list' ||
                    r.name == 'glob' ||
                    r.name == 'grep' ||
                    r.name == 'todo')
                .toList()
            : mapped;

        if (effective.isEmpty) {
          yield const AgentTurnDone();
          return;
        }

        gate.mode = switch (mode) {
          AgentMode.plan => PermissionMode.ask,
          AgentMode.ask => PermissionMode.ask,
          AgentMode.auto => PermissionMode.auto,
          AgentMode.bypass => PermissionMode.bypass,
        };

        for (final req in effective) {
          final tool = registry[req.name] ??
              (req.name == 'run_command' ? registry['shell'] : null);
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
