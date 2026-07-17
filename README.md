# TermuxCode

**TermuxCode** is a **chat-first AI app** (Doubao / Claude App style).  
Talk naturally; when needed the AI runs commands on **your** remote server/container over SSH (with approval).  
Not a classic SSH client first — a conversation product with remote execution superpowers.

[![Release](https://img.shields.io/github/v/release/Zst0NE/TermuxCode)](https://github.com/Zst0NE/TermuxCode/releases)
[![License](https://img.shields.io/badge/license-personal-lightgrey)](#license)

**中文：** TermuxCode 是手机上的 AI 终端 / Coding Agent 控制面。默认 **远程 SSH 优先**；用自然语言 + 批准流程操作主机；内置轻量 Agent Runtime；目标是包装远端 OpenCode/Claude Code，并把本机 Termux 作为可选执行环境。

## Why TermuxCode?

| You want… | TermuxCode |
|-----------|------------|
| Phone-native SSH + PTY | Yes (`dartssh2` + `xterm`) |
| AI that **asks before running** commands | Yes (approval cards + permission gate) |
| BYOK (OpenAI-compatible / Anthropic) | Yes |
| Full desktop agent brain (LSP, multi-agent fleet) | **No** — we wrap CLIs instead of reimplementing OpenCode |
| Local Termux as the main OS | Roadmap (local backend), not the only path |

See [docs/COMPETITORS.md](docs/COMPETITORS.md) and [docs/ROADMAP.md](docs/ROADMAP.md).

## Architecture (target)

```text
┌─────────────────────────────────────┐
│  TermuxCode App (Flutter)           │
│  Terminal · Agent UI · Approvals    │
└──────────────────┬──────────────────┘
                   │ SSH / (later) Bridge
┌──────────────────▼──────────────────┐
│  Host: PC · VPS · optional Termux   │
│  shell · opencode · claude · codex  │
└─────────────────────────────────────┘
```

Today the built-in harness still executes tools via **SSH `exec`**. Remote CLI adapters detect and invoke host binaries when available.

## Features (v0.1.x)

- SSH profiles (password / key) + **host-key trust** dialog  
- Interactive PTY, mobile key bar, font size, NL→command wand  
- Agent page: **Chat / Plan / Build**  
- Tools: `shell`, `read`, `list` + permission deny/allow/ask  
- BYOK + Markdown replies  
- Android release: [v0.1.0 APK (arm64)](https://github.com/Zst0NE/TermuxCode/releases/tag/v0.1.0)

## Quick start

### Install APK

1. Download [TermuxCode-0.1.0-arm64-v8a-release.apk](https://github.com/Zst0NE/TermuxCode/releases/download/v0.1.0/TermuxCode-0.1.0-arm64-v8a-release.apk)  
2. Allow unknown sources → install  
3. **Settings**: Base URL + model + API key  
4. **连接**: add SSH host → trust fingerprint → connect  
5. **终端** / **Agent**: work

> Signing: v0.1.0 uses the **debug keystore** (sideload-friendly, not store-ready).  
> ABI: **arm64-v8a** only.

### Build from source

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## Project layout

```text
lib/
  agent/           # AgentRuntime · tools · permission · remote CLI adapters
  models/ services/ providers/ screens/ widgets/
docs/              # competitors · roadmap
```

## Security

- Secrets in OS keystore only  
- Host key change blocks connect  
- Shell tools go through approval / deny patterns  
- Do not use debug-signed builds on production servers without review  

## Contributing / feedback

Issues and ideas welcome: https://github.com/Zst0NE/TermuxCode/issues  

## License

Personal / learning project for now.
