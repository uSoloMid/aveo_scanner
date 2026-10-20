final class PidDef {
  const PidDef({
    required this.pid,
    required this.nameEs,
    required this.unit,
    required this.bytes,
    required this.decode,
    required this.min,
    required this.max,
  });
  final int pid;
  final String nameEs, unit;
  final int bytes;
  final double Function(List<int>) decode;
  final double min, max;
}

final class PidValue {
  const PidValue({required this.pid, required this.value, required this.at});
  final int pid;
  final double value;
  final DateTime at;
}
