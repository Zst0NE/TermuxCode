# Roadmap

Aligned with product decisions: **Remote-first**, **wrap host CLIs**, success = open-source traction.

## R1 — Story & demo (docs) ✅ in progress

- [x] Public repo + v0.1.0 APK  
- [x] Rebrand TermuxCode  
- [ ] README remote-first narrative  
- [ ] Competitors + roadmap docs  
- [ ] Short demo script / GIF (community)

## R2 — Remote CLI adapters

- [ ] Detect `opencode` / `claude` / `codex` on SSH host  
- [ ] Non-interactive prompt runner with safe quoting  
- [ ] Stream stdout into Agent UI  
- [ ] Deep-support **one** CLI first (prefer OpenCode)

## R3 — Control-plane UX

- [ ] Chat/agent history persistence  
- [ ] Streaming LLM tokens (HTTP)  
- [ ] Disconnect banner + session resume  
- [ ] Tool timeline polish  

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
