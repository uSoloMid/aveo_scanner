import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/obd/dtc.dart';
import 'package:aveo_scanner/obd/dtc_descriptions_es.dart';

void main() {
  test('includes at least 150 generic Spanish P0 descriptions', () {
    expect(dtcDescriptionsEs.length, greaterThanOrEqualTo(150));
    expect(
      dtcDescriptionsEs.keys.every((String code) => code.startsWith('P0')),
      isTrue,
    );
  });
  test('decodes CAN DTC count and skips padding', () {
    final List<Dtc> result = decodeDtcs(
      [0x43, 2, 0x01, 0x33, 0, 0],
      DtcKind.confirmed,
      ecu: '7E8',
    );
    expect(result.map((Dtc d) => d.code), ['P0133']);
    expect(result.single.ecu, '7E8');
  });
  test('decodes three KWP pairs without count byte', () {
    final List<Dtc> result = decodeDtcs([
      0x01,
      0x33,
      0x03,
      0x00,
      0xC1,
      0x23,
    ], DtcKind.pending);
    expect(result.map((Dtc d) => d.code), ['P0133', 'P0300', 'U0123']);
  });
}
