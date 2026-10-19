/// Byte pipe to an ELM327 adapter. Knows nothing about OBD or AT commands.
///
/// Only `Elm327` may call [write]; every command goes through `CommandGuard`
/// first. See docs/SPEC.md section 3.
library;

enum TransportState { disconnected, connecting, connected, error }

abstract interface class Transport {
  /// Human-readable label for logs and the sessions table (e.g. "mock", "bt:AA:BB:...").
  String get label;

  bool get isConnected;

  /// Broadcast stream of state changes.
  Stream<TransportState> get state;

  /// Broadcast stream of raw bytes received from the adapter.
  Stream<List<int>> get incoming;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> write(List<int> bytes);
}

final class TransportException implements Exception {
  const TransportException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'TransportException(${code ?? '-'}): $message';
}
