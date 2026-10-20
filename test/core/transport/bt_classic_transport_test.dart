import 'dart:async';

import 'package:aveo_scanner/core/transport/bt_classic_channel.dart';
import 'package:aveo_scanner/core/transport/bt_classic_transport.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'platform channel sends write bytes as Uint8List (Kotlin ByteArray)',
    () async {
      const methodChannel = MethodChannel('test/bt_classic');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null),
      );
      final channel = PlatformBtClassicChannel(methodChannel: methodChannel);

      await channel.write(<int>[0x41, 0x54, 0x5A, 0x0D]);

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'write');
      expect(args['bytes'], isA<Uint8List>());
      expect(args['bytes'], <int>[0x41, 0x54, 0x5A, 0x0D]);
    },
  );

  test('connects, broadcasts state/data, writes, and disconnects', () async {
    final channel = _FakeBtChannel();
    final transport = BtClassicTransport('AA:BB:CC:DD:EE:FF', channel: channel);
    final states = <TransportState>[];
    final bytes = <List<int>>[];
    final stateSubscription = transport.state.listen(states.add);
    final dataSubscription = transport.incoming.listen(bytes.add);

    expect(transport.label, 'bt:AA:BB:CC:DD:EE:FF');
    await transport.connect();
    expect(transport.isConnected, isTrue);
    channel.data.add(<int>[0x41, 0x42]);
    await Future<void>.delayed(Duration.zero);
    expect(bytes, <List<int>>[
      <int>[0x41, 0x42],
    ]);
    await transport.write(<int>[0x30, 0x31]);
    expect(channel.writes, <List<int>>[
      <int>[0x30, 0x31],
    ]);
    await transport.disconnect();
    expect(transport.isConnected, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(states, <TransportState>[
      TransportState.connecting,
      TransportState.connected,
      TransportState.disconnected,
    ]);
    await stateSubscription.cancel();
    await dataSubscription.cancel();
    await transport.dispose();
  });

  test('maps platform errors to TransportException with code', () async {
    final channel = _FakeBtChannel()
      ..connectError = PlatformException(
        code: 'NO_PERMISSION',
        message: 'Denied',
      );
    final transport = BtClassicTransport('AA', channel: channel);
    await expectLater(
      transport.connect(),
      throwsA(
        isA<TransportException>().having(
          (error) => error.code,
          'code',
          'NO_PERMISSION',
        ),
      ),
    );
    expect(transport.isConnected, isFalse);
    await transport.dispose();
  });

  test('rejects writes while disconnected', () async {
    final transport = BtClassicTransport('AA', channel: _FakeBtChannel());
    await expectLater(
      transport.write(<int>[1]),
      throwsA(
        isA<TransportException>().having(
          (error) => error.code,
          'code',
          'NOT_CONNECTED',
        ),
      ),
    );
    await transport.dispose();
  });
}

final class _FakeBtChannel implements BtClassicChannel {
  final StreamController<List<int>> data =
      StreamController<List<int>>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  Object? connectError;
  bool connected = false;

  @override
  Stream<List<int>> get incoming => data.stream;

  @override
  Future<List<BondedBluetoothDevice>> bondedDevices() async =>
      const <BondedBluetoothDevice>[];

  @override
  Future<void> connect(String address) async {
    if (connectError != null) throw connectError!;
    connected = true;
  }

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> write(List<int> bytes) async => writes.add(bytes);
}
