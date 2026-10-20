import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';

void main() {
  test('applies adapter echo, spacing, and header settings', () async {
    final MockTransport mock = MockTransport(latency: () => Duration.zero);
    await mock.connect();
    final List<String> frames = [];
    final StreamSubscription<List<int>> sub = mock.incoming.listen(
      (List<int> b) => frames.add(ascii.decode(b)),
    );
    await mock.write(ascii.encode('010C\r'));
    expect(frames.join(), contains('010C\r'));
    expect(frames.join(), contains('41 0C'));
    await mock.write(ascii.encode('ATE0\r'));
    await mock.write(ascii.encode('ATS0\r'));
    await mock.write(ascii.encode('ATH1\r'));
    frames.clear();
    await mock.write(ascii.encode('010C\r'));
    expect(frames.join(), contains('7E804410C'));
    await sub.cancel();
    await mock.disconnect();
  });
  test('serves DTCs and clears only confirmed and pending codes', () async {
    final MockTransport mock = MockTransport(latency: () => Duration.zero);
    await mock.connect();
    final List<String> frames = [];
    final StreamSubscription<List<int>> sub = mock.incoming.listen(
      (List<int> b) => frames.add(ascii.decode(b)),
    );
    await mock.write(ascii.encode('03\r'));
    expect(frames.join(), contains('43 02 01 33'));
    frames.clear();
    await mock.write(ascii.encode('04\r'));
    await mock.write(ascii.encode('03\r'));
    expect(frames.join(), contains('43 00'));
    frames.clear();
    await mock.write(ascii.encode('0A\r'));
    expect(frames.join(), contains('4A 01 01 33'));
    await sub.cancel();
    await mock.disconnect();
  });
  test('responds with VIN ISO-TP frames and KWP checksum frame', () async {
    final MockTransport mock = MockTransport(latency: () => Duration.zero);
    await mock.connect();
    final List<String> frames = [];
    final StreamSubscription<List<int>> sub = mock.incoming.listen(
      (List<int> b) => frames.add(ascii.decode(b)),
    );
    await mock.write(ascii.encode('ATH1\r'));
    await mock.write(ascii.encode('0902\r'));
    expect(frames.join(), contains('7E810'));
    expect(frames.join(), contains('7E821'));
    final MockTransport kwp = MockTransport(
      kwp: true,
      latency: () => Duration.zero,
    );
    await kwp.connect();
    frames.clear();
    final StreamSubscription<List<int>> sub2 = kwp.incoming.listen(
      (List<int> b) => frames.add(ascii.decode(b)),
    );
    await kwp.write(ascii.encode('010C\r'));
    expect(frames.join(), contains('86F110'));
    await sub.cancel();
    await sub2.cancel();
    await mock.disconnect();
    await kwp.disconnect();
  });
}
