import 'package:aveo_scanner/obd/dtc_descriptions_es.dart';

enum DtcKind { confirmed, pending, permanent }

final class Dtc {
  const Dtc({
    required this.code,
    required this.kind,
    required this.ecu,
    this.descriptionEs,
  });
  final String code;
  final DtcKind kind;
  final String? descriptionEs;
  final String ecu;
}

List<Dtc> decodeDtcs(
  List<int> data,
  DtcKind kind, {
  String ecu = '?',
  bool hasCount = true,
}) {
  final bool hasService =
      data.isNotEmpty && const [0x43, 0x47, 0x4a].contains(data.first);
  final int start = hasService ? 1 : 0;
  final bool counted = hasCount && hasService;
  final int count = counted && data.length > 1
      ? data[1]
      : (data.length - start) ~/ 2;
  final List<Dtc> result = [];
  for (
    int i = 0;
    i < count && start + (counted ? 1 : 0) + i * 2 + 1 < data.length;
    i++
  ) {
    final int offset = start + (counted ? 1 : 0) + i * 2;
    final int a = data[offset], b = data[offset + 1];
    if (a == 0 && b == 0) {
      continue;
    }
    const List<String> prefix = ['P', 'C', 'B', 'U'];
    final String code =
        '${prefix[a >> 6]}${((a >> 4) & 3).toString()}${(a & 15).toRadixString(16).toUpperCase()}${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    result.add(
      Dtc(
        code: code,
        kind: kind,
        ecu: ecu,
        descriptionEs: dtcDescriptionsEs[code],
      ),
    );
  }
  return result;
}

final class FreezeFrame {
  const FreezeFrame({required this.dtcs, required this.values});
  final List<Dtc> dtcs;
  final Map<int, double> values;
}
