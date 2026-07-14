# Demo script (30–60s)

Goal: show TermuxCode as a **mobile control plane** for remote SSH + AI.

## Prep

1. Android arm64 device/emulator with TermuxCode installed  
2. SSH host with shell access  
3. Optional: `opencode` or `claude` on the host for `/cli`  
4. BYOK API key (OpenAI-compatible works best for streaming)

## Script

| Time | Action | On screen |
|------|--------|-----------|
| 0–5s | Open app | Global strip: 未连接 · TermuxCode |
| 5–15s | 连接 → 添加主机 → 信任指纹 → 连接 | Top strip: 已连接 · label |
| 15–25s | 设置 → 填 Key → **拉取模型** → 选模型 → 保存 | Model dropdown/search |
| 25–40s | Agent → Build → “查看磁盘占用” → 批准 | Streaming reply + tool card + timeline |
| 40–50s | 终端 → 功能键 / ✨ 魔法棒 | PTY + key bar |
| 50–60s | `/cli` 或雷达探测；`/cli 用一句话说明当前目录` | Remote CLI chips + markdown output |

## Talking points

- Not “full OpenCode on phone” — **control plane + approvals**  
- Built-in harness for simple ops; host CLIs for heavy coding  
- Host-key trust + ask-before-run  

## Capture

```bash
adb shell screencap -p /sdcard/demo.png
adb pull /sdcard/demo.png
# or record: adb shell screenrecord /sdcard/demo.mp4
```
