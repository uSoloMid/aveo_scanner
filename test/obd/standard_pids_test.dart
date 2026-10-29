import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';
import 'package:aveo_scanner/obd/supported_pids.dart';

void main() {
  test('decodes each standard PID formula', () {
    final Map<int, List<int>> samples = {
      1: [0x82, 0, 0, 0],
      3: [0x02, 0x00],
      69: [0x0B],
      20: [0x90, 0xFF],
      21: [0x1C, 0xFF],
      4: [255],
      5: [90],
      6: [0],
      7: [255],
      11: [42],
      12: [0x1A, 0xF8],
      13: [80],
      14: [128],
      15: [60],
      16: [0x00, 0x64],
      17: [128],
      31: [0x00, 0x10],
      47: [128],
      51: [101],
      66: [0x37, 0x14],
    };
    expect(samples.keys.toSet(), standardPids.keys.toSet());
    for (final MapEntry<int, List<int>> entry in samples.entries) {
      expect(
        standardPids[entry.key]!.decode(entry.value),
        isA<double>(),
        reason: 'PID ${entry.key.toRadixString(16)}',
      );
    }
    expect(standardPids[12]!.decode(samples[12]!), 1726);
    expect(standardPids[5]!.decode(samples[5]!), 50);
    expect(standardPids[16]!.decode(samples[16]!), 1);
    expect(standardPids[66]!.decode(samples[66]!), 14.1);
    expect(standardPids[20]!.decode(samples[20]!), 0.72);
    expect(standardPids[3]!.decode(samples[3]!), 2);
    expect(standardPids[69]!.decode(samples[69]!), closeTo(4.31, 0.01));
  });
  test('decodes README RPM and elapsed-time examples', () {
    expect(standardPids[12]!.decode([0x1a, 0xf8]), 1726);
    expect(standardPids[31]!.decode([1, 0xff]), 511);
  });
  test('decodes a real supported-PID mask', () {
    final SupportedPids pids = SupportedPids.fromMask(0, [
      0xbe,
      0x3e,
      0xb8,
      0x11,
    ]);
    expect(pids.pids, {
      1,
      3,
      4,
      5,
      6,
      7,
      11,
      12,
      13,
      14,
      15,
      17,
      19,
      20,
      21,
      28,
      32,
    });
  });
  test('computes fuel consumption and avoids division near idle', () {
    expect(fuelLph(10), closeTo(3.303, 0.01));
    expect(kmPerL(20, 0), isNull);
  });
}
