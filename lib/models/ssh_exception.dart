/// Base exception for SSH operations.
class SshException implements Exception {
  final String message;
  final Object? cause;

  const SshException(this.message, {this.cause});

  @override
  String toString() {
    if (cause == null) return 'SshException: $message';
    return 'SshException: $message (cause: $cause)';
  }
}

/// Thrown when authentication fails (wrong password / key rejected).
class SshAuthException extends SshException {
  const SshAuthException(super.message, {super.cause});

  @override
  String toString() {
    if (cause == null) return 'SshAuthException: $message';
    return 'SshAuthException: $message (cause: $cause)';
  }
}

/// Thrown when an operation is attempted on a session that is not connected.
class SshNotConnectedException extends SshException {
  const SshNotConnectedException(super.message, {super.cause});

  @override
  String toString() => 'SshNotConnectedException: $message';
}

/// Thrown when a command or connection attempt exceeds the allowed duration.
class SshTimeoutException extends SshException {
  const SshTimeoutException(super.message, {super.cause});

  @override
  String toString() => 'SshTimeoutException: $message';
}

/// Thrown when the user declines to trust an unknown host key.
class SshHostKeyRejectedException extends SshException {
  const SshHostKeyRejectedException(super.message, {super.cause});

  @override
  String toString() => 'SshHostKeyRejectedException: $message';
}

/// Thrown when the stored host key fingerprint doesn't match the server's.
class SshHostKeyMismatchException extends SshException {
  const SshHostKeyMismatchException(super.message, {super.cause});

  @override
  String toString() => 'SshHostKeyMismatchException: $message';
}
