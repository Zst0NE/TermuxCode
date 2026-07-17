import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_connection_state.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/llm_service.dart';
import '../widgets/terminal_key_bar.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Terminal? _terminal;
  bool _attached = false;
  double _fontSize = 13;

  static const _theme = TerminalTheme(
    cursor: Color(0xFF00FF88),
    selection: Color(0xFF264F78),
    foreground: Color(0xFFD4D4D4),
    background: Color(0xFF0C0C0C),
    black: Color(0xFF0C0C0C),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFFAA),
    searchHitBackgroundCurrent: Color(0xFFFF8800),
    searchHitForeground: Color(0xFF000000),
  );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final cs = Theme.of(context).colorScheme;

    if (session.state != SshConnectionState.connected) {
      final last = session.lastProfile;
      final canReconnect = last != null && !session.isConnecting;
      return Scaffold(
        appBar: AppBar(title: const Text('终端')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 72, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  session.isConnecting
                      ? '正在连接…'
                      : session.state == SshConnectionState.error
                          ? '连接异常'
                          : '未连接',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  last != null
                      ? '上次主机：${last.label}（${last.username}@${last.host}）'
                      : '请先在「连接」页面连接到 SSH 主机',
                  style: TextStyle(color: cs.outline, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                if (canReconnect) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await session.reconnect();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('重连失败：$e'),
                            backgroundColor: Colors.red[800],
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text('重新连接 ${last.label}'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Multi-terminal on the same SSH server.
    final tabs = session.tabs;
    final active = session.activeTab;

    if (tabs.isEmpty || active == null) {
      return Scaffold(
        appBar: AppBar(title: Text(session.activeProfileLabel ?? '终端')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () async {
              try {
                await session.openNewTerminal();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('打开终端失败：$e'),
                    backgroundColor: Colors.red[800],
                  ),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('新建终端'),
          ),
        ),
      );
    }

    final term = active.terminal;
    term.onResize = (w, h, pw, ph) => session.resize(w, h);

    return Scaffold(
      appBar: AppBar(
        title: Text(session.activeProfileLabel ?? '终端'),
        actions: [
          IconButton(
            tooltip: '新建终端（同机）',
            onPressed: () async {
              try {
                await session.openNewTerminal();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('新建失败：$e'), backgroundColor: Colors.red[800]),
                );
              }
            },
            icon: const Icon(Icons.add, size: 22),
          ),
          IconButton(
            tooltip: 'AI 生成命令',
            onPressed: () => _showNlCommandDialog(context, term),
            icon: const Icon(Icons.auto_awesome, size: 20),
          ),
          IconButton(
            tooltip: '缩小字体',
            onPressed: () {
              setState(() => _fontSize = (_fontSize - 1).clamp(10, 22));
            },
            icon: const Icon(Icons.text_decrease, size: 20),
          ),
          IconButton(
            tooltip: '放大字体',
            onPressed: () {
              setState(() => _fontSize = (_fontSize + 1).clamp(10, 22));
            },
            icon: const Icon(Icons.text_increase, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab strip — multiple PTYs on one server
          Material(
            color: const Color(0xFF121816),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: tabs.length,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemBuilder: (ctx, i) {
                        final t = tabs[i];
                        final selected = i == session.activeTabIndex;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          child: InputChip(
                            label: Text(
                              t.title,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? const Color(0xFF00E5A0)
                                    : null,
                              ),
                            ),
                            selected: selected,
                            onPressed: () => session.selectTab(i),
                            onDeleted: tabs.length <= 1
                                ? null
                                : () => session.closeTab(i),
                            deleteIconColor: cs.outline,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TerminalView(
              term,
              key: ValueKey(active.id),
              theme: _theme,
              textStyle: TerminalStyle(
                fontSize: _fontSize,
                fontFamily: 'monospace',
              ),
              autofocus: true,
              backgroundOpacity: 1,
            ),
          ),
          TerminalKeyBar(terminal: term),
        ],
      ),
    );
  }

  Future<void> _showNlCommandDialog(BuildContext context, Terminal term) async {
    final settings = context.read<SettingsProvider>();
    if (!settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「设置」配置 LLM 与 API Key')),
      );
      return;
    }

    final inputCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    var loading = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> generate() async {
              final nl = inputCtrl.text.trim();
              if (nl.isEmpty || loading) return;
              setModal(() {
                loading = true;
                error = null;
              });
              try {
                final llm = LlmService();
                final cmd = await llm.suggestShellCommand(
                  config: settings.config,
                  apiKey: settings.apiKey,
                  naturalLanguage: nl,
                );
                llm.dispose();
                setModal(() {
                  cmdCtrl.text = cmd;
                  loading = false;
                });
              } catch (e) {
                setModal(() {
                  loading = false;
                  error = '$e';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AI 生成命令',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '生成后只会填入终端，不会自动执行。请确认后再按回车。',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: inputCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '你想做什么？',
                      hintText: '例如：查找占用磁盘最多的前 10 个目录',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => generate(),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: loading ? null : generate,
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(loading ? '生成中…' : '生成命令'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: cmdCtrl,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: '命令（可编辑）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final cmd = cmdCtrl.text.trim();
                            if (cmd.isEmpty) return;
                            // Insert into terminal input only — user presses Enter to run.
                            term.textInput(cmd);
                            Navigator.pop(ctx);
                          },
                          child: const Text('填入终端'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    inputCtrl.dispose();
    cmdCtrl.dispose();
  }
}
