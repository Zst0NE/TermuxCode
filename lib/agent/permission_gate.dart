import 'tool.dart';

/// Outcome of a permission check.
enum PermissionDecision {
  allow,
  ask,
  deny,
}

/// Session-level policy — mirrors Claude Code / Codex approval styles.
enum PermissionMode {
  /// Every medium/high risk tool asks (default).
  ask,

  /// Reads auto; shell only if on allowlist, else ask.
  auto,

  /// Auto-approve tools except hard-deny patterns.
  bypass,
}

/// Evaluates whether a tool call may run.
class PermissionGate {
  PermissionGate({
    this.mode = PermissionMode.ask,
    List<RegExp>? denyCommandPatterns,
    List<RegExp>? allowCommandPatterns,
  })  : denyCommandPatterns = denyCommandPatterns ?? _defaultDeny,
        allowCommandPatterns = allowCommandPatterns ?? _defaultAllow;

  PermissionMode mode;
  final List<RegExp> denyCommandPatterns;
  final List<RegExp> allowCommandPatterns;

  static final _defaultDeny = <RegExp>[
    RegExp(r'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/', caseSensitive: false),
    RegExp(r'rm\s+-rf\b', caseSensitive: false),
    RegExp(r'\bdd\b.*\bof=', caseSensitive: false),
    RegExp(r'\bmkfs\b', caseSensitive: false),
    RegExp(r':\(\)\s*\{\s*:\|:\s*&\s*\}\s*;', caseSensitive: false),
    RegExp(r'>\s*/dev/sd', caseSensitive: false),
    RegExp(r'chmod\s+-R\s+777\s+/', caseSensitive: false),
    RegExp(r'\bshutdown\b|\breboot\b|\bpoweroff\b', caseSensitive: false),
    RegExp(r'\bmkfs\.', caseSensitive: false),
    RegExp(r'curl\s+[^\n]*\|\s*(ba)?sh', caseSensitive: false),
    RegExp(r'wget\s+[^\n]*\|\s*(ba)?sh', caseSensitive: false),
  ];

  static final _defaultAllow = <RegExp>[
    RegExp(r'^(ls|pwd|whoami|uname|date|df|du|ps|cat|head|tail|wc|file|id|env|printenv)\b'),
    RegExp(r'^git\s+(status|diff|log|branch|show|remote|rev-parse)\b'),
    RegExp(r'^(echo|printf|which|type|command)\b'),
    RegExp(r'^(free|uptime|hostname|nproc|arch)\b'),
    RegExp(r'^python3?\s+--version\b'),
    RegExp(r'^node\s+-v\b'),
  ];

  PermissionDecision evaluate(ToolCallRequest request, ToolRisk risk) {
    final name = request.name;
    final cmd = (request.arguments['command'] as String?) ??
        (request.arguments['path'] as String?) ??
        '';

    // Hard deny always wins (even in bypass).
    if (name == 'shell' || name == 'run_command') {
      for (final re in denyCommandPatterns) {
        if (re.hasMatch(cmd)) return PermissionDecision.deny;
      }
    }

    // Low-risk reads always auto in all modes.
    if (risk == ToolRisk.low &&
        (name == 'read' || name == 'list' || name == 'glob' || name == 'grep')) {
      return PermissionDecision.allow;
    }

    switch (mode) {
      case PermissionMode.ask:
        return PermissionDecision.ask;

      case PermissionMode.auto:
        if (name == 'shell' || name == 'run_command') {
          final c = cmd.trim();
          for (final re in allowCommandPatterns) {
            if (re.hasMatch(c)) return PermissionDecision.allow;
          }
          return PermissionDecision.ask;
        }
        // write/edit etc.
        if (risk == ToolRisk.medium) return PermissionDecision.ask;
        return PermissionDecision.ask;

      case PermissionMode.bypass:
        // Auto everything not hard-denied.
        return PermissionDecision.allow;
    }
  }

  PermissionGate copyWithMode(PermissionMode m) => PermissionGate(
        mode: m,
        denyCommandPatterns: denyCommandPatterns,
        allowCommandPatterns: allowCommandPatterns,
      );
}
