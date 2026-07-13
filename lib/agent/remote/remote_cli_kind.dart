/// Host-side coding CLI detected over SSH.
enum RemoteCliKind {
  opencode,
  claude,
  codex,
  unknown,
}

extension RemoteCliKindX on RemoteCliKind {
  String get cliName => switch (this) {
        RemoteCliKind.opencode => 'opencode',
        RemoteCliKind.claude => 'claude',
        RemoteCliKind.codex => 'codex',
        RemoteCliKind.unknown => 'unknown',
      };

  String get label => switch (this) {
        RemoteCliKind.opencode => 'OpenCode',
        RemoteCliKind.claude => 'Claude Code',
        RemoteCliKind.codex => 'Codex CLI',
        RemoteCliKind.unknown => 'Unknown',
      };
}
