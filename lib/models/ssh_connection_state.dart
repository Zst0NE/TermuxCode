/// Lifecycle states for an SSH connection.
enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}
