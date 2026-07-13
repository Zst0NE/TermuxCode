# Competitors & positioning

TermuxCode aims to be a **mobile control plane** for terminals and coding agents — not a full desktop agent runtime.

## Landscape

| Project | Type | Mobile | SSH/PTY | Coding agent | Notes |
|---------|------|--------|---------|--------------|-------|
| [OpenCode](https://opencode.ai) | Desktop/TUI agent | Via wrappers | Host-side | Strong | Brain to wrap, not reimplement |
| [Aider](https://github.com/Aider-AI/aider) | Git pair CLI | No | Host-side | Strong | Good remote target |
| Claude Code / Codex CLI | Platform CLIs | Via bridges | Host-side | Strong | Wrap over SSH |
| [Chaterm](https://github.com/chaterm/Chaterm) | AI ops terminal | Yes (related apps) | Yes | Ops-oriented | Infra/SRE, not app coding |
| [CC Pocket](https://github.com/K9i-0/ccpocket) | Flutter + bridge | Yes | Via bridge | Controls Claude/Codex | Closest product shape |
| [Faryo](https://github.com/Snailflyer/faryo) | Phone/PWA + tmux | Yes | Session share | Session-centric | Same live session philosophy |
| [opencode-manager](https://github.com/chriswritescode-dev/opencode-manager) | Mobile web for OpenCode | PWA | Remote | Multi-agent UI | Web control plane |
| Termux + CLI tutorials | DIY | Yes | Local | Depends | High setup cost |

## TermuxCode vs them

| | TermuxCode | CC Pocket | Chaterm | OpenCode |
|--|------------|-----------|---------|----------|
| Primary UI | Flutter Android | Flutter | Electron/app | TUI/desktop |
| Default path | SSH remote-first | Bridge to desktop agents | AI ops terminal | Local coding agent |
| Approval UX | First-class | Strong | Varies | CLI-centric |
| BYOK in app | Yes | Depends on host CLI | Varies | Provider config |
| Self-contained agent | Light harness | Delegates | Agent features | Full |
| Local Termux | Roadmap host | N/A | N/A | Optional ports |

## Differentiation we keep

1. **Phone-native terminal + agent in one app** (PTY + approvals + BYOK).  
2. **Remote-first**, wrap OpenCode/Claude/Codex on the host.  
3. **Honest security defaults** (host keys, ask-before-shell, deny patterns).  
4. **Chinese + global BYOK** ergonomics.  
5. Optional **local Termux** as another host — not “full PC replacement” marketing.

## What we will not do early

- Rebuild full LSP multi-agent desktop runtime  
- Promise “replace your laptop”  
- Silent auto-run of destructive commands  
