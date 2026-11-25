final class QueryMetric {
  const QueryMetric({
    required this.command,
    required this.at,
    required this.queueMs,
    required this.elapsedMs,
    required this.raw,
    this.error,
    this.firstByteMs,
    this.wireMs = 0,
    this.parseMs = 0,
  });
  final String command, raw;
  final String? error;
  final DateTime at;
  final double queueMs, elapsedMs, wireMs, parseMs;
  final double? firstByteMs;
}
