import 'dart:async';

import 'package:aveo_scanner/core/transport/bt_classic_channel.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum BluetoothPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// Requests Android's Bluetooth connect permission before listing paired devices.
Future<BluetoothPermissionResult> requestBluetoothConnectPermission() async {
  // Ask for both "Nearby devices" permissions in one dialog: CONNECT opens
  // the socket, SCAN is needed by some adapter calls on Android 12+.
  final Map<Permission, PermissionStatus> statuses = await [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ].request();
  final PermissionStatus status =
      statuses[Permission.bluetoothConnect] ?? PermissionStatus.denied;
  return switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => BluetoothPermissionResult.granted,
    PermissionStatus.permanentlyDenied =>
      BluetoothPermissionResult.permanentlyDenied,
    PermissionStatus.restricted => BluetoothPermissionResult.restricted,
    _ => BluetoothPermissionResult.denied,
  };
}

final class BtClassicTransport implements Transport {
  BtClassicTransport(this.address, {BtClassicChannel? channel})
    : _channel = channel ?? PlatformBtClassicChannel() {
    _incomingController = StreamController<List<int>>.broadcast();
    _stateController = StreamController<TransportState>.broadcast();
    _channelSubscription = _channel.incoming.listen(
      _incomingController.add,
      onError: _handleIncomingError,
      onDone: _handleIncomingDone,
    );
  }

  final String address;
  final BtClassicChannel _channel;
  late final StreamController<List<int>> _incomingController;
  late final StreamController<TransportState> _stateController;
  StreamSubscription<List<int>>? _channelSubscription;
  bool _isConnected = false;
  bool _disposed = false;

  @override
  String get label => 'bt:$address';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<TransportState> get state => _stateController.stream;

  @override
  Stream<List<int>> get incoming => _incomingController.stream;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw const TransportException('El transporte ya fue cerrado.');
    }
    _emitState(TransportState.connecting);
    try {
      await _channel.connect(address);
      _isConnected = true;
      _emitState(TransportState.connected);
    } on PlatformException catch (error) {
      _isConnected = false;
      _emitState(TransportState.error);
      throw TransportException(
        error.message ?? 'No se pudo conectar por Bluetooth.',
        code: error.code,
      );
    } on Exception catch (error) {
      _isConnected = false;
      _emitState(TransportState.error);
      throw TransportException(error.toString(), code: 'CONNECT_FAILED');
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_disposed) {
      try {
        await _channel.disconnect();
      } on PlatformException catch (error) {
        throw TransportException(
          error.message ?? 'No se pudo desconectar.',
          code: error.code,
        );
      } finally {
        _isConnected = false;
        _emitState(TransportState.disconnected);
      }
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_isConnected) {
      throw const TransportException(
        'No hay conexión Bluetooth.',
        code: 'NOT_CONNECTED',
      );
    }
    try {
      await _channel.write(bytes);
    } on PlatformException catch (error) {
      throw TransportException(
        error.message ?? 'Falló el envío Bluetooth.',
        code: error.code,
      );
    } on Exception catch (error) {
      throw TransportException(error.toString(), code: 'WRITE_FAILED');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await disconnect();
    } finally {
      _disposed = true;
      await _channelSubscription?.cancel();
      await _incomingController.close();
      await _stateController.close();
    }
  }

  void _handleIncomingError(Object error, StackTrace stackTrace) {
    _isConnected = false;
    _emitState(TransportState.error);
    if (error is PlatformException) {
      _incomingController.addError(
        TransportException(
          error.message ?? 'Se perdió la conexión Bluetooth.',
          code: error.code,
        ),
        stackTrace,
      );
    } else {
      _incomingController.addError(error, stackTrace);
    }
  }

  void _handleIncomingDone() {
    if (_isConnected) {
      _isConnected = false;
      _emitState(TransportState.disconnected);
    }
  }

  void _emitState(TransportState value) {
    if (!_stateController.isClosed) _stateController.add(value);
  }
}
