# TermuxCode

**Chat-first AI app for your own servers** — Flutter / Android.

Talk like **Doubao / Claude / ChatGPT**. When needed, the AI runs commands on **your** remote host (SSH).  
If the host already has **Claude Code / Codex / OpenCode**, TermuxCode drives those **native agents** over a PTY.  
Otherwise it uses a **built-in Claude-style harness** (BYOK + tools) over SSH.

[![Release](https://img.shields.io/github/v/release/Zst0NE/TermuxCode)](https://github.com/Zst0NE/TermuxCode/releases)

## Install

Latest: **[v0.1.2](https://github.com/Zst0NE/TermuxCode/releases/tag/v0.1.2)**  
APK: arm64-v8a, debug-signed (sideload).

```bash
adb install -r TermuxCode-0.1.2-arm64-v8a-release.apk
```

## Product model

| Layer | Role |
|-------|------|
| Phone UI | Conversation, modes, approvals, multi-terminal |
| Remote host | Your VPS / container — preferred brain if Claude/Codex/OpenCode installed |
| Builtin agent | Fallback: your API key + remote shell/read/write/glob/grep/todo |

## Features (complete MVP)

- **Chat-first UI** — 对话 / 服务器 / 终端 / 设置  
- **Backends** — 远程 Agent (PTY) \| 内置 Agent (BYOK)  
- **Modes** — Plan · Ask · Auto (default) · Bypass (hard-deny still applies)  
- **Builtin tools** — shell, read, list, glob, grep, write, todo  
- **Project memory** — loads host `CLAUDE.md` / `AISH.md` when present  
- **SSH** — profiles, host-key trust, keepalive, reconnect  
- **Multi-terminal** — multiple PTYs on one SSH connection  
- **Remote Ask confirm** + interrupt  
- **Model list** auto-fetch (OpenAI-compatible / Anthropic)  
- **Streaming** replies (OpenAI SSE)  

## Quick start

1. **设置** → Base URL + API Key → 拉取模型 → 保存  
2. **服务器** → 添加并连接你的主机（信任指纹）  
3. **对话** → 默认 **Auto**；有远程 CLI 时优先 **远程 Agent**  
4. **终端** → `+` 多开 shell（同机）  

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/ROADMAP.md](docs/ROADMAP.md), [docs/DEMO.md](docs/DEMO.md), [docs/COMPETITORS.md](docs/COMPETITORS.md).

```text
Phone chat UI  ──SSH──►  Host: claude | codex | opencode  (preferred)
                    └─►  Builtin tools via exec            (fallback)
```

## Build

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## Security notes

- Secrets in OS keystore only  
- Host-key trust on first connect  
- Hard-deny for catastrophic commands even in Bypass  
- Debug signing — replace before store listing  

## License

Personal / learning project.
