import 'tool.dart';

/// Outcome of a permission check.
enum PermissionDecision {
  allow,
  ask,
  deny,
}

/// Session-level policy knob (mobile-friendly).
enum PermissionMode {
  /// Almost everything asks (safest default).
  ask,

  /// Reads auto; shell/write ask.
  autoRead,

  /// Workspace shell may auto for low-risk allowlist; high-risk still ask/deny.
  agent,
}

/// Evaluates whether a tool call may run.
class PermissionGate {
  PermissionGate({
    this.mode = PermissionMode.ask,
    List<RegExp>? denyCommandPatterns,
    List<RegExp>? allowCommandPatterns,
  })  : denyCommandPatterns = denyCommandPatterns ?? _defaultDeny,
        allowCommandPatterns = allowCommandPatterns ?? _defaultAllow;

  final PermissionMode mode;
  final List<RegExp> denyCommandPatterns;
  final List<RegExp> allowCommandPatterns;

  static final _defaultDeny = <RegExp>[
    RegExp(r'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/', caseSensitive: false),
    RegExp(r'rm\s+-rf\s+', caseSensitive: false),
    RegExp(r'\bdd\b.*\bof=', caseSensitive: false),
    RegExp(r'\bmkfs\b', caseSensitive: false),
    RegExp(r':\(\)\s*\{\s*:\|:\s*&\s*\}\s*;', caseSensitive: false),
    RegExp(r'>\s*/dev/sd', caseSensitive: false),
    RegExp(r'chmod\s+-R\s+777\s+/', caseSensitive: false),
  ];

  static final _defaultAllow = <RegExp>[
    RegExp(r'^(ls|pwd|whoami|uname|date|df|du|ps|cat|head|tail|wc|file|id)\b'),
    RegExp(r'^git\s+(status|diff|log|branch|show)\b'),
    RegExp(r'^(echo|printf)\b'),
  ];

  PermissionDecision evaluate(ToolCallRequest request, ToolRisk risk) {
    final name = request.name;
    final cmd = (request.arguments['command'] as String?) ?? '';

    if (name == 'shell' || name == 'run_command') {
      for (final re in denyCommandPatterns) {
        if (re.hasMatch(cmd)) return PermissionDecision.deny;
      }
    }

    if (mode == PermissionMode.ask) {
      if (risk == ToolRisk.low && (name == 'read' || name == 'list')) {
        return PermissionDecision.allow;
      }
      return PermissionDecision.ask;
    }

    if (mode == PermissionMode.autoRead) {
      if (risk == ToolRisk.low) return PermissionDecision.allow;
      return PermissionDecision.ask;
    }

    // agent mode
    if (name == 'shell' || name == 'run_command') {
      for (final re in allowCommandPatterns) {
        if (re.hasMatch(cmd.trim())) return PermissionDecision.allow;
      }
      if (risk == ToolRisk.high) return PermissionDecision.ask;
      return PermissionDecision.ask;
    }
    if (risk == ToolRisk.low) return PermissionDecision.allow;
    return PermissionDecision.ask;
  }
}
