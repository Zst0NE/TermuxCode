/// Agent operating modes (OpenCode-style Plan/Build split).
enum AgentMode {
  /// No tools (or minimal). Pure Q&A.
  chat,

  /// Read-only tools only.
  plan,

  /// Full tools subject to [PermissionGate].
  build,
}

extension AgentModeLabel on AgentMode {
  String get label => switch (this) {
        AgentMode.chat => 'Chat',
        AgentMode.plan => 'Plan',
        AgentMode.build => 'Build',
      };

  String get descriptionZh => switch (this) {
        AgentMode.chat => '纯对话，不调用工具',
        AgentMode.plan => '只读探索，不改系统',
        AgentMode.build => '可执行命令（经权限批准）',
      };
}
