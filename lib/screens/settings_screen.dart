import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent.dart';
import '../models/llm_provider_config.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/llm_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _ModelFilter { all, chat, other }

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _modelSearch;
  LlmProviderKind _kind = LlmProviderKind.openai;
  bool _obscureKey = true;
  bool _saving = false;
  bool _fetchingModels = false;
  List<String> _modelIds = [];
  String? _modelsError;
  _ModelFilter _modelFilter = _ModelFilter.all;

  static bool _isChatModel(String id) {
    final l = id.toLowerCase();
    return !l.contains('embed') &&
        !l.contains('whisper') &&
        !l.contains('tts') &&
        !l.contains('dall-e') &&
        !l.contains('moderation') &&
        !l.contains('embedding');
  }

  List<String> get _filteredModelIds {
    var list = _modelIds.where((id) {
      switch (_modelFilter) {
        case _ModelFilter.all:
          return true;
        case _ModelFilter.chat:
          return _isChatModel(id);
        case _ModelFilter.other:
          return !_isChatModel(id);
      }
    }).toList();
    final q = _modelSearch.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((id) => id.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _baseUrl = TextEditingController(text: s.config.baseUrl);
    _model = TextEditingController(text: s.config.model);
    _apiKey = TextEditingController(text: s.maskedApiKey);
    _modelSearch = TextEditingController();
    _kind = s.config.kind;
    _modelSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _modelSearch.dispose();
    super.dispose();
  }

  /// Prefer the real key from provider when the field still shows a mask.
  String _resolveApiKey(SettingsProvider prov) {
    final typed = _apiKey.text.trim();
    if (typed.isEmpty) return prov.apiKey.trim();
    if (typed.contains('••••')) return prov.apiKey.trim();
    return typed;
  }

  Future<void> _fetchModels() async {
    final prov = context.read<SettingsProvider>();
    final key = _resolveApiKey(prov);
    final base = _baseUrl.text.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Base URL')),
      );
      return;
    }
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写有效的 API Key（不要只保留掩码）')),
      );
      return;
    }

    setState(() {
      _fetchingModels = true;
      _modelsError = null;
    });

    final llm = LlmService();
    try {
      final cfg = LlmProviderConfig(
        kind: _kind,
        baseUrl: base,
        model: _model.text.trim().isEmpty ? 'placeholder' : _model.text.trim(),
      );
      final ids = await llm.listModels(config: cfg, apiKey: key);
      if (!mounted) return;
      setState(() {
        _modelIds = ids;
        // Keep current model if still present; otherwise pick a sensible default.
        final current = _model.text.trim();
        if (current.isNotEmpty && ids.contains(current)) {
          // ok
        } else {
          _model.text = _pickPreferredModel(ids, _kind);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已拉取 ${ids.length} 个模型')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsError = '$e';
        _modelIds = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拉取失败：$e'),
          backgroundColor: Colors.red[800],
        ),
      );
    } finally {
      llm.dispose();
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  String _pickPreferredModel(List<String> ids, LlmProviderKind kind) {
    final preferred = kind == LlmProviderKind.openai
        ? [
            'gpt-4o',
            'gpt-4o-mini',
            'gpt-4.1',
            'gpt-4.1-mini',
            'deepseek-chat',
            'deepseek-reasoner',
          ]
        : [
            'claude-sonnet-4-6',
            'claude-sonnet-4-5',
            'claude-sonnet-4-0',
            'claude-3-5-sonnet-latest',
            'claude-3-5-sonnet-20241022',
            'claude-3-opus-latest',
          ];
    for (final p in preferred) {
      if (ids.contains(p)) return p;
    }
    // Prefer chatty names over embeddings/whisper when sorting fell alphabetically.
    final chatty = ids.where((id) {
      final l = id.toLowerCase();
      return !l.contains('embed') &&
          !l.contains('whisper') &&
          !l.contains('tts') &&
          !l.contains('dall-e') &&
          !l.contains('moderation');
    }).toList();
    if (chatty.isNotEmpty) return chatty.first;
    return ids.first;
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
                    _model.text = _kind == LlmProviderKind.openai
                        ? 'gpt-4o'
                        : 'claude-sonnet-4-6';
                    _modelIds = [];
                    _modelsError = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.openai.com/v1',
                  helperText: '须含 https:// ，例如 https://api.deepseek.com/v1',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return '必填';
                  final withScheme =
                      s.contains('://') ? s : 'https://$s';
                  final uri = Uri.tryParse(withScheme);
                  if (uri == null || uri.host.isEmpty) {
                    return '地址无效，请带 https://';
                  }
                  return null;
                },
                onChanged: (_) {
                  // URL change invalidates cached list.
                  if (_modelIds.isNotEmpty) {
                    setState(() {
                      _modelIds = [];
                      _modelsError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKey,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: InputDecoration(
                        labelText: '模型 ID',
                        hintText: _kind == LlmProviderKind.openai
                            ? 'gpt-4o / deepseek-chat'
                            : 'claude-sonnet-4-6',
                        prefixIcon: const Icon(Icons.memory_outlined),
                        helperText: _modelIds.isEmpty
                            ? '可手动填写，或点右侧拉取列表'
                            : '已加载 ${_modelIds.length} 个，可下拉选择或手改',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '必填' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.tonalIcon(
                      onPressed: _fetchingModels ? null : _fetchModels,
                      icon: _fetchingModels
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined),
                      label: Text(_fetchingModels ? '拉取中' : '拉取模型'),
                    ),
                  ),
                ],
              ),
              if (_modelsError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _modelsError!,
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              ],
              if (_modelIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                // ── Search field ──────────────────────────────────────────
                TextField(
                  controller: _modelSearch,
                  decoration: InputDecoration(
                    labelText: '搜索模型',
                    hintText: '关键词过滤…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _modelSearch.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _modelSearch.clear();
                            },
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                // ── Filter chips ──────────────────────────────────────────
                Row(
                  children: [
                    for (final f in _ModelFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(switch (f) {
                            _ModelFilter.all => '全部',
                            _ModelFilter.chat => '对话',
                            _ModelFilter.other => '其他',
                          }),
                          selected: _modelFilter == f,
                          onSelected: (_) =>
                              setState(() => _modelFilter = f),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    const Spacer(),
                    // ── Count label ───────────────────────────────────────
                    Text(
                      '显示 ${_filteredModelIds.length} / ${_modelIds.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // ── Scrollable model list ─────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: _filteredModelIds.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: Text('无匹配模型')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredModelIds.length,
                          itemBuilder: (ctx, i) {
                            final id = _filteredModelIds[i];
                            final selected = _model.text.trim() == id;
                            return InkWell(
                              onTap: () => setState(() => _model.text = id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        id,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
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
                          Text(
                            'TermuxCode',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '手机上的 AI Agent 控制面（Remote-first）。包装远端 CLI，内置轻量 Harness。',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
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
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Colors.red[800],
          ),
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
