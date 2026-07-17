/// Agent operating modes — aligned with Claude Code / Codex style.
///
/// - [plan]: read-only exploration (Claude Code plan mode)
/// - [ask]: every shell command needs approval (safe default)
/// - [auto]: allowlist auto-run; others ask (acceptEdits / auto)
/// - [bypass]: auto-run except hard-deny patterns (bypass permissions)
enum AgentMode {
  plan,
  ask,
  auto,
  bypass,
}

extension AgentModeLabel on AgentMode {
  String get label => switch (this) {
        AgentMode.plan => 'Plan',
        AgentMode.ask => 'Ask',
        AgentMode.auto => 'Auto',
        AgentMode.bypass => 'Bypass',
      };

  String get shortHint => switch (this) {
        AgentMode.plan => '只读',
        AgentMode.ask => '需批准',
        AgentMode.auto => '半自动',
        AgentMode.bypass => '自动',
      };

  String get descriptionZh => switch (this) {
        AgentMode.plan => '只读规划，不执行写/危险命令',
        AgentMode.ask => '每条命令都需你批准（默认）',
        AgentMode.auto => '安全命令自动执行，其余询问',
        AgentMode.bypass => '自动执行（仍拦截 rm -rf 等高危）',
      };

  bool get allowsShellTools => this != AgentMode.plan;
}
