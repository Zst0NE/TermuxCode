# AIsh

**AIsh**（AI Shell）—— 面向手机的 AI 驱动 SSH 终端客户端。

用自然语言控制远程 Linux / Termux 主机：内置交互式 PTY 终端，并通过 BYOK（自带 API Key）接入云端大模型执行 `run_command` 工具调用。

![LDPlayer screenshot](preview/ldplayer_screenshot.png)

## 功能

- **SSH 主机管理**：密码 / 私钥登录，凭据写入系统安全存储
- **交互式终端**：`dartssh2` + `xterm` PTY 双向桥接与窗口缩放
- **AI 助手**：OpenAI 兼容 / Anthropic 双协议，命令执行前需用户批准
- **BYOK**：Base URL + 模型 + API Key 可自定义（DeepSeek、Kimi、本地 Ollama 等）

## 技术栈

| 层 | 方案 |
|----|------|
| UI | Flutter · Material 3 · Provider |
| SSH | `dartssh2` |
| 终端 | `xterm` |
| 安全存储 | `flutter_secure_storage` |
| LLM | `http` 直连 OpenAI / Anthropic API |

## 目录结构

```
lib/
  main.dart / app_shell.dart
  models/          # SSH / LLM / 聊天消息
  services/        # SecureStore · SshService · LlmService · AgentService
  providers/       # 状态层
  screens/         # 连接 · 终端 · AI · 设置
  widgets/
preview/           # 交互预览 HTML + 模拟器截图
```

## 快速开始

### 依赖

- Flutter stable（推荐 3.32+）
- Android SDK（真机 / 模拟器）

### 运行

```bash
flutter pub get
flutter run
```

### 构建 Debug APK

```bash
flutter build apk --debug
# 产物: build/app/outputs/flutter-apk/app-debug.apk
```

### 雷电模拟器示例

```bash
# 启动雷电后
adb connect 127.0.0.1:5555
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.example.termux_ai -c android.intent.category.LAUNCHER 1
```

## 使用流程

1. **设置**：填写 LLM Base URL、模型与 API Key  
2. **连接**：添加 SSH 主机并连接  
3. **终端**：交互式 shell  
4. **AI**：自然语言提需求 → 审查 `run_command` → 批准后远程执行  

## 安全说明

- API Key / SSH 密码 / 私钥只写入 OS Keystore / Keychain  
- 异常与日志中不输出完整密钥  
- AI 命令默认需用户点「批准」后才执行  

## 许可证

个人 / 学习项目。若要正式开源协议，可后续补充 MIT 等声明。
