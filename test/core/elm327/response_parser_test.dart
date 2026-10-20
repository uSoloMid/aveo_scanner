import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';

void main() {
  const ResponseParser parser = ResponseParser();
  test('parses single CAN frames and two ECUs', () {
    final r = parser.parse(
      '7E804410C1AF8\r7E904410C1000',
      protocol: ProtocolFamily.can11,
    );
    expect(r.messages, hasLength(2));
    expect(r.messages.first.data, [0x41, 0x0c, 0x1a, 0xf8]);
    expect(standardPids[12]!.decode(r.messages.first.data.sublist(2)), 1726);
  });
  test('reassembles VIN ISO-TP frames', () {
    final r = parser.parse(
      '7E810144902014B4C31\r7E82154443544453543\r7E82242303030303030',
      protocol: ProtocolFamily.can11,
    );
    expect(r.messages.single.data, hasLength(20));
    expect(
      String.fromCharCodes(r.messages.single.data.skip(3)),
      'KL1TD5DE5CB000000',
    );
  });
  test('decodes the README mode 22 elapsed-time response', () {
    final r = parser.parse('7E8056211A101FF', protocol: ProtocolFamily.can11);
    expect(standardPids[31]!.decode(r.messages.single.data.sublist(3)), 511);
  });
  test('parses pending negative response', () {
    final r = parser.parse('7E8037F2231', protocol: ProtocolFamily.can11);
    expect(r.isNegative, isTrue);
    expect(r.negativeCode, 0x31);
  });
  test(
    'parses CAN 29 bit, no-header payloads, and discards bad KWP checksum',
    () {
      final r29 = parser.parse(
        '18DAF11003410C00',
        protocol: ProtocolFamily.can29,
      );
      expect(r29.messages.single.ecu, 'F110');
      final plain = parser.parse(
        'SEARCHING...\r41 0C 1A F8\r>',
        protocol: ProtocolFamily.unknown,
        command: '010C',
      );
      expect(plain.messages.single.data, [0x41, 0x0C, 0x1A, 0xF8]);
      final bad = parser.parse(
        '86F1104301013300',
        protocol: ProtocolFamily.kwp,
      );
      expect(bad.messages, isEmpty);
    },
  );
  test('recognizes all adapter error replies', () {
    const Set<String> cases = {
      'NO DATA',
      '?',
      'UNABLE TO CONNECT',
      'CAN ERROR',
      'BUS ERROR',
      'BUS BUSY',
      'FB ERROR',
      'DATA ERROR',
      'STOPPED',
      'BUFFER FULL',
      'ERR12',
      'LV RESET',
    };
    for (final String message in cases) {
      expect(
        parser.parse('$message\r>', protocol: ProtocolFamily.can11).error,
        isNotNull,
        reason: message,
      );
    }
  });
  test('validates and parses a KWP header and checksum', () {
    final List<int> frame = [0x86, 0xF1, 0x10, 0x43, 0x01, 0x01, 0x33];
    frame.add(frame.fold<int>(0, (int sum, int byte) => (sum + byte) & 0xFF));
    final String raw = frame
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final result = parser.parse(raw, protocol: ProtocolFamily.kwp);
    expect(result.messages.single.ecu, '10');
    expect(result.messages.single.data, [0x43, 0x01, 0x01, 0x33]);
  });
}
