import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';

final class SpyTransport implements Transport {
  final StreamController<List<int>> input =
      StreamController<List<int>>.broadcast(sync: true);
  final List<String> writes = [];
  bool autoReply = true;
  void Function(String command)? afterWrite;
  @override
  String get label => 'spy';
  @override
  bool get isConnected => true;
  @override
  Stream<List<int>> get incoming => input.stream;
  @override
  Stream<TransportState> get state => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> write(List<int> bytes) async {
    final String command = ascii.decode(bytes).trim();
    writes.add(command);
    afterWrite?.call(command);
    if (autoReply) {
      input.add(ascii.encode('OK\r>'));
    }
  }
}

void main() {
  test('blocked and unconfirmed commands never write to transport', () async {
    final SpyTransport transport = SpyTransport();
    final Elm327 elm = Elm327(transport, delay: (_) async {});
    await expectLater(
      elm.send('1101'),
      throwsA(isA<CommandBlockedException>()),
    );
    await expectLater(
      elm.send('04'),
      throwsA(isA<ConfirmationRequiredException>()),
    );
    expect(transport.writes, isEmpty);
    await elm.close();
  });
  test('queues commands FIFO', () async {
    final SpyTransport transport = SpyTransport();
    final Elm327 elm = Elm327(transport, delay: (_) async {});
    final Future<ElmResponse> first = elm.send('ATZ');
    final Future<ElmResponse> second = elm.send('ATI');
    await Future.wait([first, second]);
    expect(transport.writes, ['ATZ', 'ATI']);
    await elm.close();
  });
  test('requires matching confirmation', () async {
    final SpyTransport transport = SpyTransport();
    final Elm327 elm = Elm327(transport, delay: (_) async {});
    await expectLater(
      elm.send('04', confirmation: Confirmation.userApproved('14')),
      throwsA(isA<ConfirmationRequiredException>()),
    );
    expect(transport.writes, isEmpty);
    await elm.close();
  });
  test(
    'waits for a late prompt before writing the next queued command',
    () async {
      final SpyTransport transport = SpyTransport()..autoReply = false;
      final Elm327 elm = Elm327(transport, delay: (_) async {});
      final Completer<void> secondWrite = Completer<void>();
      transport.afterWrite = (String command) {
        if (command == 'ATI' && !secondWrite.isCompleted) {
          secondWrite.complete();
        }
      };
      await expectLater(
        elm.send('ATZ', timeout: const Duration(milliseconds: 10)),
        throwsA(isA<ElmTimeoutException>()),
      );
      final Future<ElmResponse> next = elm.send('ATI');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.writes, ['ATZ']);
      transport.input.add(ascii.encode('late bytes>'));
      await secondWrite.future;
      expect(transport.writes, ['ATZ', 'ATI']);
      transport.input.add(ascii.encode('OK>'));
      await next;
      await elm.close();
    },
  );
  test('extends response wait for pending and enforces minimum gap', () async {
    final SpyTransport transport = SpyTransport()..autoReply = false;
    transport.afterWrite = (_) {
      transport.input.add(ascii.encode('7E8037F0178\r\r>'));
      Timer(const Duration(milliseconds: 30), () {
        transport.input.add(ascii.encode('7E804410C1AF8\r\r>'));
      });
    };
    DateTime now = DateTime.utc(2026);
    final List<Duration> delays = [];
    final Elm327 elm = Elm327(
      transport,
      clock: () => now,
      delay: (Duration duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );
    final ElmResponse response = await elm.send(
      '010C',
      timeout: const Duration(milliseconds: 5),
    );
    expect(response.isNegative, isTrue);
    expect(response.messages, hasLength(2));
    transport.afterWrite = null;
    transport.autoReply = true;
    await elm.send('010D');
    expect(delays, contains(const Duration(milliseconds: 50)));
    await elm.close();
  });
  test(
    'continues the queue when a timed-out command never returns a prompt',
    () async {
      final SpyTransport transport = SpyTransport()..autoReply = false;
      final Elm327 elm = Elm327(
        transport,
        delay: (_) async {},
        latePromptTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        elm.send('ATZ', timeout: const Duration(milliseconds: 5)),
        throwsA(isA<ElmTimeoutException>()),
      );
      transport.autoReply = true;
      final ElmResponse next = await elm
          .send('ATI')
          .timeout(const Duration(seconds: 1));
      expect(next.text, 'OK');
      expect(transport.writes, ['ATZ', 'ATI']);
      await elm.close();
    },
  );
  test('initializes KWP and re-parses supported PIDs after ATDPN', () async {
    final MockTransport transport = MockTransport(
      kwp: true,
      latency: () => Duration.zero,
    );
    await transport.connect();
    final Elm327 elm = Elm327(transport, delay: (_) async {});
    final ElmInfo info = await elm.initialize();
    expect(info.protocolCode, '5');
    expect(info.supportedPids, isNotEmpty);
    expect(elm.protocolFamily, ProtocolFamily.kwp);
    await elm.close();
  });
}
