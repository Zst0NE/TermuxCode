# TermuxCode Architecture Design

> Product: **Chat-first AI app** (Doubao / Claude App UX) that runs work on **the user’s own remote host**.  
> Best path: when the host already has **Claude Code / Codex / OpenCode**, control those **native agents** instead of reinventing them on Android.

---

## 1. Product thesis

```text
┌─────────────────────────────────────────────┐
│  TermuxCode (Android)                         │
│  = Conversation UI + Approvalvals + Session      │
│  NOT a full desktop coding-agent runtime      │
└──────────────────────┬──────────────────────┘
                       │ SSH (and later local Termux)
┌──────────────────────▼──────────────────────┐
│  User host / container                           │
│  Prefer: claude | codex | opencode (native) │
│  Fallback: thin shell tools (read/list/exec)│
└─────────────────────────────────────────────┘
```

| Layer | Owns | Does not own |
|-------|------|----------------|
| **Phone app** | Chat UX, modes, approvals, multi-PTY, BYOK for *fallback* LLM | Full codebase indexing, heavy multi-agent fleet |
| **Remote native agent** | Real Claude Code / Codex workflows | UI |
| **Fallback harness** | Simple ops when native agent missing | Replace Claude Code |

**Success metric:** From the phone, feel like chatting with Claude/Codex *on your server*, with Plan / Ask / Auto / Bypass and multi-terminal.

---

## 2. Dual execution backends (core design)

### Path A — Remote Native Agent (preferred)

When detect finds `claude` / `codex` / `opencode` on the host:

```text
User message (phone)
    → TermuxCode Session
    → RemoteAgentSession (adapter)
    → SSH PTY or non-interactive channel
    → native CLI (claude / codex / opencode)
    → stream stdout/stderr/events back
    → phone renders as chat + optional approval
```

**Why this is better**

- Native agent already has tools, repo context, skills, subagents  
- Android stays a **control plane**, not a second brain  
- Matches your note: *“远程已装 claude/codex 就直接控制原生 agent”*

### Path B — Built-in Harness (fallback)

When no native CLI:

```text
User message
    → AgentRuntime (phone)
    → LLM (BYOK)
    → tools: shell / read / list / (future write/glob/grep)
    → PermissionGate (Plan/Ask/Auto/Bypass)
    → SSH exec on host
```

Use for simple ops, demos, or hosts without Claude/Codex.

### Path selection (runtime)

```text
on SSH connect:
  detect CLIs
  if claude|codex|opencode present:
    default backend = remote_native (user can switch)
  else:
    default backend = builtin_harness
```

UI: clear switch — **远程 Claude/Codex** | **内置 Agent** (same chat surface).

---

## 3. Claude Code / Codex concepts → TermuxCode mapping

| Claude Code / Codex idea | TermuxCode design |
|--------------------------|-------------------|
| Agent loop | **Remote:** CLI owns the loop. **Builtin:** `AgentRuntime` loop |
| Plan mode | `AgentMode.plan` — no mutating tools; or remote `claude` plan-style prompts |
| Default / ask | `AgentMode.ask` — approve each shell / high-risk step |
| Auto / acceptEdits | `AgentMode.auto` — allowlist auto; else ask |
| Bypass permissions | `AgentMode.bypass` — auto except **hard-deny** list |
| Tools (Bash/Read/Edit…) | Remote: native. Builtin: shell/read/list + later write/glob/grep |
| CLAUDE.md | Load remote `CLAUDE.md` / `AISH.md` / `.termuxcode/AISH.md` into context (builtin) or rely on native agent’s own project files |
| Subagents | Prefer remote native; phone only shows status/summaries |
| Multi-session | Chat history + **multi-PTY tabs** on one SSH connection |
| Streaming | Remote PTY/stdout stream; builtin OpenAI SSE |

---

## 4. Module architecture (target)

```text
lib/
  ui/  (screens)          Chat-first Doubao/Claude UI
  providers/              Chat, Session (multi-tab), Settings
  agent/
    agent_runtime.dart    Builtin loop only
    permission_gate.dart  Plan/Ask/Auto/Bypass + hard-deny
    tools/                Fallback tools over SSH
    remote/
      remote_cli_detector.dart
      remote_cli_adapter.dart     # non-interactive / batch
      remote_agent_session.dart   # NEW: long-lived native agent session
      remote_agent_protocol.dart  # NEW: event types (text, tool, ask, done)
  services/
    ssh_service.dart      Connection + exec + multi shell()
    llm_service.dart      BYOK for builtin path only
```

### New: `RemoteAgentSession` (design)

Responsible for **controlling a native agent on the host**:

| Method | Purpose |
|--------|---------|
| `attach(kind)` | Bind to claude/codex/opencode after detect |
| `send(userText)` | Forward turn into remote agent |
| `events` | Stream: `text_delta`, `tool_hint`, `need_input`, `done`, `error` |
| `respondApproval(bool)` | If remote or our gate needs confirmation |
| `cancel()` | Kill remote process group / close PTY |

**Transport options (phased):**

| Phase | Transport | Pros | Cons |
|-------|-----------|------|------|
| **P1** | SSH `exec` non-interactive (`claude -p`, `codex exec`, `opencode run`) | Simple | Weak multi-turn, limited streaming |
| **P2** | Dedicated SSH PTY running interactive CLI; phone multiplexes input/output | Real agent session | Harder: prompts, TUI noise, resize |
| **P3** | Host-side small bridge (`termuxcode-bridge`) exposing JSON-RPC over SSH | Clean events | Extra install on host |

**Recommendation:** Ship **P1** well (already started), design adapters so **P2/P3** plug in without UI rewrite.

---

## 5. Conversation UI (phone)

Aligned with Doubao / Claude App:

```text
[ 远程主机状态条 · 轻量 ]
[ 对话标题 · 模式 Plan|Ask|Auto|Bypass · 后端 远程Claude|内置 ]
[ 消息流：气泡 + 命令批准卡 + 工具结果折叠 ]
[ 大输入框 + 发送 ]
Tab: 对话 | 服务器 | 终端(多标签) | 设置
```

- **对话** = primary  
- **服务器** = user’s machines/containers  
- **终端** = multi-PTY on **same** SSH (power users / when agent needs raw shell)  
- **设置** = BYOK for builtin + defaults for remote backend preference  

---

## 6. Permission model (shared philosophy)

Even when driving remote Claude/Codex:

1. **Phone-side gate (optional overlay)**  
   - Ask / Auto / Bypass for *what we send* and *what we auto-confirm*  
2. **Hard-deny list (always)**  
   - `rm -rf /`, `dd`, `mkfs`, `curl|sh`, etc.  
3. **Remote agent’s own permissions**  
   - Claude Code / Codex may still prompt in TUI; P2 must surface those prompts in chat  

```text
deny > (mode) ask|auto|bypass > execute
```

---

## 7. Multi-terminal (same server)

Already the right direction:

- One `SSHClient` / connection  
- Many `shell()` PTYs → tabs `shell-1`, `shell-2`, …  
- Chat agent uses **exec** (non-interactive) by default so it doesn’t steal a PTY  
- Optional: “open agent in terminal tab” for full interactive Claude TUI (P2)

---

## 8. Implementation roadmap (concrete)

### Phase N1 — Prefer remote native agent (high value)

1. **Backend switch** in chat: `远程 Agent` | `内置 Agent`  
2. **Detect + health**: version string, recommended invoke flags per CLI  
3. **Deep one CLI first**: prefer **Claude Code** *or* **OpenCode** (pick one to polish)  
4. Map modes → remote behavior:  
   - Plan → prompt prefix “plan only, don’t execute”  
   - Ask → show every proposed command card before sending next step (if batch)  
   - Auto/Bypass → fewer stops (document risk)  
5. Stream remote stdout into chat bubbles  

### Phase N2 — Session-grade remote control

1. Long-lived SSH channel / PTY for multi-turn native agent  
2. Parse or strip TUI junk; surface “waiting for input”  
3. Multi-chat threads bound to one host  

### Phase N3 — Host bridge (optional but best long-term)

1. Small `termuxcode-bridge` on server (Node/Go)  
2. JSON events: tool start/end, diffs, asks  
3. Phone becomes a first-class remote UI for Claude/Codex-like agents  

### Phase N4 — Builtin harness parity (only where needed)

1. write / glob / grep over SSH  
2. Load remote `CLAUDE.md` / `AISH.md` into builtin system prompt  
3. Session todos (TodoWrite-like)  

---

## 9. What we will *not* clone on Android

| Avoid on phone | Why |
|----------------|-----|
| Full local Claude Code runtime | Size, CPU, disk, maintenance |
| Desktop-class multi-agent swarm | Battery + UX |
| Silent destructive auto-run | Mobile trust |
| Replacing host project memory files | Native agent already uses them |

---

## 10. Recommended default product behavior

1. Open app → **对话**  
2. User configures server + API (BYOK for fallback)  
3. On connect → detect CLIs  
4. If `claude` or `codex` found → default **远程原生 Agent**  
5. Else → **内置 Agent** with Plan/Ask/Auto/Bypass  
6. Terminal tabs = same machine, parallel shells  

---

## 11. Locked decisions (2026-07)

| # | Decision | Choice |
|---|----------|--------|
| D1 | Native CLIs | **All three** — unified adapter framework first |
| D2 | Control depth | **P2 long-lived PTY** (interactive remote agent session) |
| D3 | Default mode | **Auto** (allowlist auto; else ask; hard-deny always) |
| D4 | Builtin vs remote | Prefer remote when detected; one backend per chat turn/session |

---

## 12. Summary

**Correct architecture:**

> **TermuxCode = mobile Claude/Doubao-style chat client + approval/session shell**,  
> whose **preferred brain is the native Claude/Codex/OpenCode already on the user’s server**,  
> with a **small builtin harness only as fallback**.

P2 means: open an SSH PTY, run `claude` / `codex` / `opencode` interactively, multiplex I/O into the chat UI (and keep multi-terminal tabs for raw shells on the same connection).
