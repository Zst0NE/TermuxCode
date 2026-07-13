import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent.dart';
import '../models/llm_provider_config.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  LlmProviderKind _kind = LlmProviderKind.openai;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _baseUrl = TextEditingController(text: s.config.baseUrl);
    _model = TextEditingController(text: s.config.model);
    _apiKey = TextEditingController(text: s.maskedApiKey);
    _kind = s.config.kind;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(label: 'AI 提供商'),
              const SizedBox(height: 8),
              SegmentedButton<LlmProviderKind>(
                segments: LlmProviderKind.values
                    .map((k) => ButtonSegment(value: k, label: Text(k.label)))
                    .toList(),
                selected: {_kind},
                onSelectionChanged: (v) {
                  setState(() {
                    _kind = v.first;
                    _baseUrl.text = _kind == LlmProviderKind.openai
                        ? 'https://api.openai.com/v1'
                        : 'https://api.anthropic.com';
                    _model.text = _kind == LlmProviderKind.openai ? 'gpt-4o' : 'claude-sonnet-4-6';
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.openai.com/v1',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(
                  labelText: '模型 ID',
                  hintText: 'gpt-4o',
                  prefixIcon: Icon(Icons.memory_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKey,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存设置'),
              ),
              const SizedBox(height: 32),
              _SectionHeader(label: '远端 Coding CLI'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '在已连接的 SSH 主机上探测 OpenCode / Claude Code / Codex（Remote-first）。',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _detectRemoteCli(context),
                        icon: const Icon(Icons.search),
                        label: const Text('探测远端 CLI'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _SectionHeader(label: '关于'),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal, color: cs.primary),
                          const SizedBox(width: 8),
                          Text('TermuxCode', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '手机上的 AI Agent 控制面（Remote-first）。包装远端 CLI，内置轻量 Harness。',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _detectRemoteCli(BuildContext context) async {
    final session = context.read<SessionProvider>();
    final chat = context.read<ChatProvider>();
    if (!session.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「连接」页连上 SSH')),
      );
      return;
    }
    await chat.remoteCli.detect();
    if (!context.mounted) return;
    final avail = chat.remoteCli.available;
    final msg = avail.isEmpty
        ? '未检测到 opencode / claude / codex'
        : avail.entries.map((e) => '• ${e.key.label}: ${e.value}').join('\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('远端 CLI'),
        content: SingleChildScrollView(child: Text(msg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final prov = context.read<SettingsProvider>();
      await prov.saveConfig(
        config: prov.config.copyWith(
          kind: _kind,
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
        ),
        apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e'), backgroundColor: Colors.red[800]),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}
