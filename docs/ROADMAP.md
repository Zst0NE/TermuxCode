# Roadmap

Aligned with product decisions: **Remote-first**, **wrap host CLIs**, success = open-source traction.

## R1 — Story & demo (docs)

- [x] Public repo + v0.1.0 / v0.1.1 APK  
- [x] Rebrand TermuxCode  
- [x] README remote-first narrative  
- [x] Competitors + roadmap docs  
- [x] Short demo script (docs/DEMO.md); GIF still welcome from community

## R2 — Remote CLI adapters

- [x] Detect `opencode` / `claude` / `codex` on SSH host  
- [x] Non-interactive prompt runner with safe quoting  
- [x] Surface CLI output in Agent UI (`/cli`)  
- [x] Deep-support **one** CLI first (prefer OpenCode) — improved detect + single-quote + run/exec/-p ladder

## R3 — Control-plane UX

- [x] Chat/agent history persistence  
- [x] Streaming LLM tokens (HTTP, OpenAI SSE; Anthropic falls back)  
- [x] Remote CLI detect/run skeleton (`/cli`, settings probe)  
- [x] Auto-fetch model list + searchable filter chips  
- [x] Tool result timeline (status chips, collapsible output)  
- [x] Session reconnect (`lastProfile` + top strip / terminal CTA)  
- [ ] Disconnect auto-detect while idle (keep-alive)  
- [ ] Tool timeline polish (timestamps / duration)

## R4 — Local Termux as host

- [ ] Workspace type: Remote SSH | Local Termux  
- [ ] Stable local exec bridge (Run Command / documented integration)  
- [ ] Same adapter interface as remote  

## Later

- Real release signing + applicationId migration  
- Multi-ABI APK / Play hygiene  
- Subagents, MCP, `/undo`  

## Non-goals (near term)

- Full OpenCode reimplementation  
- Team multiplayer  
- DB IDE / knowledge-base product surface  
