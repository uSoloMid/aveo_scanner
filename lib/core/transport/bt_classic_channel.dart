import 'package:flutter/services.dart';

/// Injectable access to the Android Bluetooth classic platform channels.
abstract interface class BtClassicChannel {
  Future<bool> isEnabled();

  Future<List<BondedBluetoothDevice>> bondedDevices();

  Future<void> connect(String address);

  Future<void> write(List<int> bytes);

  Future<void> disconnect();

  Stream<List<int>> get incoming;
}

final class BondedBluetoothDevice {
  const BondedBluetoothDevice({required this.name, required this.address});

  final String? name;
  final String address;
}

final class PlatformBtClassicChannel implements BtClassicChannel {
  PlatformBtClassicChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(_methodName),
       _eventChannel = eventChannel ?? const EventChannel(_eventName);

  static const String _methodName = 'mx.solomid.aveo_scanner/bt_classic';
  static const String _eventName = 'mx.solomid.aveo_scanner/bt_classic/data';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<List<int>>? _incoming;

  // Kotlin sends ByteArray, which arrives as Uint8List.
  @override
  Stream<List<int>> get incoming => _incoming ??= _eventChannel
      .receiveBroadcastStream()
      .map((event) => event as Uint8List);

  @override
  Future<bool> isEnabled() async =>
      await _methodChannel.invokeMethod<bool>('isEnabled') ?? false;

  @override
  Future<List<BondedBluetoothDevice>> bondedDevices() async {
    final devices = await _methodChannel
        .invokeListMethod<Map<Object?, Object?>>('bondedDevices');
    return (devices ?? <Map<Object?, Object?>>[])
        .map((device) {
          return BondedBluetoothDevice(
            name: device['name'] as String?,
            address: device['address'] as String? ?? '',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> connect(String address) => _methodChannel.invokeMethod<void>(
    'connect',
    <String, Object>{'address': address},
  );

  // Must be a Uint8List: a plain List<int> reaches Kotlin as ArrayList<Int>,
  // not ByteArray, and every write would fail.
  @override
  Future<void> write(List<int> bytes) => _methodChannel.invokeMethod<void>(
    'write',
    <String, Object>{'bytes': Uint8List.fromList(bytes)},
  );

  @override
  Future<void> disconnect() => _methodChannel.invokeMethod<void>('disconnect');
}
