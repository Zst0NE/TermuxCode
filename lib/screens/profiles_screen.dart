import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ssh_profiles_provider.dart';
import '../providers/session_provider.dart';
import '../models/ssh_profile.dart';
import '../models/ssh_connection_state.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profilesProv = context.watch<SshProfilesProvider>();
    final sessionProv = context.watch<SessionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 主机'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加主机',
            onPressed: () => _showProfileSheet(context, null),
          ),
        ],
      ),
      body: profilesProv.profiles.isEmpty
          ? _EmptyProfiles(onAdd: () => _showProfileSheet(context, null))
          : ListView.builder(
              itemCount: profilesProv.profiles.length,
              itemBuilder: (context, i) {
                final p = profilesProv.profiles[i];
                final isActive = sessionProv.activeProfileId == p.id;
                final connState = isActive ? sessionProv.state : null;
                return _ProfileTile(
                  profile: p,
                  isActive: isActive,
                  connState: connState,
                  onConnect: () => _connect(context, p),
                  onDisconnect: () => sessionProv.disconnect(),
                  onEdit: () => _showProfileSheet(context, p),
                  onDelete: () => _confirmDelete(context, profilesProv, p),
                );
              },
            ),
    );
  }

  Future<void> _connect(BuildContext context, SshProfile profile) async {
    final sessionProv = context.read<SessionProvider>();
    try {
      await sessionProv.connect(profile);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败：$e'), backgroundColor: Colors.red[800]),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SshProfilesProvider prov,
    SshProfile profile,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主机'),
        content: Text('确定要删除 ${profile.label} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await prov.deleteProfile(profile.id);
  }

  void _showProfileSheet(BuildContext context, SshProfile? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ProfileFormSheet(existing: existing),
    );
  }
}

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 72, color: cs.outline),
            const SizedBox(height: 16),
            Text('还没有 SSH 主机', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('点击右上角 + 添加第一台远程主机', style: TextStyle(color: cs.outline, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加主机'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.connState,
    required this.onConnect,
    required this.onDisconnect,
    required this.onEdit,
    required this.onDelete,
  });

  final SshProfile profile;
  final bool isActive;
  final SshConnectionState? connState;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected = connState == SshConnectionState.connected;
    final isConnecting = connState == SshConnectionState.connecting;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConnected ? Colors.teal.shade700 : cs.surfaceContainerHighest,
          child: Icon(
            isConnected ? Icons.link : Icons.dns_outlined,
            color: isConnected ? Colors.white : cs.onSurfaceVariant,
            size: 20,
          ),
        ),
        title: Text(profile.label, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${profile.username}@${profile.host}:${profile.port}  ·  '
          '${profile.authMethod == SshAuthMethod.password ? '密码' : '密钥'}',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isConnecting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isConnected)
              OutlinedButton(
                onPressed: onDisconnect,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withOpacity(0.5)),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('断开'),
              )
            else
              FilledButton(
                onPressed: onConnect,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('连接'),
              ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet form for adding/editing an SSH profile.
class _ProfileFormSheet extends StatefulWidget {
  const _ProfileFormSheet({this.existing});
  final SshProfile? existing;

  @override
  State<_ProfileFormSheet> createState() => _ProfileFormSheetState();
}

class _ProfileFormSheetState extends State<_ProfileFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _privateKey;
  SshAuthMethod _authMethod = SshAuthMethod.password;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _label = TextEditingController(text: p?.label ?? '');
    _host = TextEditingController(text: p?.host ?? '');
    _port = TextEditingController(text: p?.port.toString() ?? '22');
    _username = TextEditingController(text: p?.username ?? '');
    _password = TextEditingController();
    _privateKey = TextEditingController();
    _authMethod = p?.authMethod ?? SshAuthMethod.password;
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? '添加 SSH 主机' : '编辑 SSH 主机',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: '名称（可选）'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _host,
                      decoration: const InputDecoration(labelText: '主机 / IP *'),
                      keyboardType: TextInputType.url,
                      validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      decoration: const InputDecoration(labelText: '端口'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 65535) return '无效';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: '用户名 *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<SshAuthMethod>(
                segments: const [
                  ButtonSegment(value: SshAuthMethod.password, label: Text('密码')),
                  ButtonSegment(value: SshAuthMethod.privateKey, label: Text('私钥')),
                ],
                selected: {_authMethod},
                onSelectionChanged: (v) => setState(() => _authMethod = v.first),
              ),
              const SizedBox(height: 12),
              if (_authMethod == SshAuthMethod.password)
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: '密码 *'),
                  obscureText: true,
                  validator: (v) {
                    if (widget.existing != null) return null;
                    return (v == null || v.isEmpty) ? '必填' : null;
                  },
                )
              else
                TextFormField(
                  controller: _privateKey,
                  decoration: const InputDecoration(
                    labelText: '私钥（PEM 格式）*',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  validator: (v) {
                    if (widget.existing != null) return null;
                    return (v == null || v.trim().isEmpty) ? '必填' : null;
                  },
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? '添加' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final prov = context.read<SshProfilesProvider>();
      final port = int.parse(_port.text.trim());
      if (widget.existing == null) {
        await prov.addProfile(
          label: _label.text,
          host: _host.text,
          port: port,
          username: _username.text,
          authMethod: _authMethod,
          password: _authMethod == SshAuthMethod.password ? _password.text : null,
          privateKey: _authMethod == SshAuthMethod.privateKey ? _privateKey.text : null,
        );
      } else {
        await prov.updateProfile(
          widget.existing!.copyWith(
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            host: _host.text.trim(),
            port: port,
            username: _username.text.trim(),
            authMethod: _authMethod,
          ),
          password: _authMethod == SshAuthMethod.password && _password.text.isNotEmpty ? _password.text : null,
          privateKey: _authMethod == SshAuthMethod.privateKey && _privateKey.text.isNotEmpty ? _privateKey.text : null,
        );
      }
      if (mounted) Navigator.of(context).pop();
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
