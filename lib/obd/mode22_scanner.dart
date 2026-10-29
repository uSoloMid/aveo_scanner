import 'package:aveo_scanner/obd/obd_service.dart';

/// A mode 22 identifier the ECU answered.
final class Mode22Hit {
  const Mode22Hit(this.id, this.data);
  final int id;
  final List<int> data;

  String get idHex => id.toRadixString(16).padLeft(4, '0').toUpperCase();
  String get dataHex => data
      .map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

final class ScanProgress {
  const ScanProgress(this.current, this.done, this.total, this.hits);
  final int current, done, total;
  final List<Mode22Hit> hits;
}

/// Walks a range of mode 22 identifiers (read-only service, allowed by
/// CommandGuard) and reports which ones the ECU answers.
final class Mode22Scanner {
  Mode22Scanner(this.obd);
  final ObdService obd;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<ScanProgress> scan(int from, int to) async* {
    _cancelled = false;
    final List<Mode22Hit> hits = [];
    final int total = to - from + 1;
    for (int id = from; id <= to && !_cancelled; id++) {
      try {
        final List<int>? data = await obd.probeMode22(id);
        if (data != null) hits.add(Mode22Hit(id, data));
      } on Object {
        // Timeouts are expected for unsupported identifiers on K-Line.
      }
      yield ScanProgress(id, id - from + 1, total, List.unmodifiable(hits));
    }
  }
}

/// CSV with every hit: identifier, raw bytes and the first byte / word as
/// decimal, so changes can be compared between a cold and a warm scan.
String mode22HitsCsv(List<Mode22Hit> hits) {
  final StringBuffer b = StringBuffer('id,comando,bytes_hex,a_dec,ab_dec\n');
  for (final Mode22Hit h in hits) {
    final String a = h.data.isEmpty ? '' : '${h.data[0]}';
    final String ab = h.data.length < 2
        ? ''
        : '${h.data[0] * 256 + h.data[1]}';
    b.writeln('${h.idHex},22${h.idHex},${h.dataHex},$a,$ab');
  }
  return b.toString();
}
