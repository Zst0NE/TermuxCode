import 'package:uuid/uuid.dart';

/// How the SSH connection authenticates.
enum SshAuthMethod { password, privateKey }

/// A saved SSH connection target. Secrets (password / private key) are NOT
/// stored in this object; they live in secure storage keyed by [id].
class SshProfile {
  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  const SshProfile({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
  });

  factory SshProfile.create({
    required String label,
    required String host,
    int port = 22,
    required String username,
    required SshAuthMethod authMethod,
  }) {
    return SshProfile(
      id: const Uuid().v4(),
      label: label.trim().isEmpty ? '$username@$host' : label.trim(),
      host: host.trim(),
      port: port,
      username: username.trim(),
      authMethod: authMethod,
    );
  }

  SshProfile copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
  }) {
    return SshProfile(
      id: id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
      };

  factory SshProfile.fromJson(Map<String, dynamic> json) => SshProfile(
        id: json['id'] as String,
        label: json['label'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        authMethod: SshAuthMethod.values.firstWhere(
          (m) => m.name == json['authMethod'],
          orElse: () => SshAuthMethod.password,
        ),
      );
}
