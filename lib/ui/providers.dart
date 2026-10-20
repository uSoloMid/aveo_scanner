import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/core/transport/bt_classic_transport.dart';
import 'package:aveo_scanner/core/transport/bt_classic_channel.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/traffic_log.dart';
import 'package:aveo_scanner/obd/obd_service.dart';
import 'package:aveo_scanner/data/database.dart';
import 'package:aveo_scanner/data/session_repository.dart';
import 'package:aveo_scanner/data/backup_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final AppDatabase value = AppDatabase();
  ref.onDispose(() => unawaited(value.close()));
  return value;
});
// Real 30–80 ms adapter latency in the app; tests override with zero.
final mockTransportProvider = Provider<MockTransport Function()>(
  (ref) => MockTransport.new,
);
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(appDatabaseProvider)),
);
final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(ref.watch(appDatabaseProvider)),
);

final class ActiveConnection {
  const ActiveConnection({
    required this.transport,
    required this.elm,
    required this.obd,
    required this.info,
  });
  final Transport transport;
  final Elm327 elm;
  final ObdService obd;
  final ElmInfo info;
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ActiveConnection?>(
      ConnectionNotifier.new,
    );

class ConnectionNotifier extends Notifier<ActiveConnection?> {
  // Mirrors `state`: Riverpod forbids reading `state` inside onDispose.
  ActiveConnection? _active;
  Elm327? _connecting;

  @override
  ActiveConnection? build() {
    ref.onDispose(() {
      final ActiveConnection? current = _active;
      if (current != null) {
        unawaited(current.elm.close());
      }
      final Elm327? pending = _connecting;
      if (pending != null) {
        unawaited(pending.close());
      }
    });
    return null;
  }

  void _setActive(ActiveConnection? value) {
    _active = value;
    state = value;
  }

  Future<ActiveConnection> connect(Transport transport) async {
    final ActiveConnection? existing = _active;
    if (existing != null) {
      _setActive(null);
      await existing.elm.close();
    }
    await transport.connect();
    final Elm327 elm = Elm327(transport);
    _connecting = elm;
    final ObdService obd = ObdService(
      elm,
      savePreClearBackup: (payload) async {
        await ref.read(backupRepositoryProvider).save('pre_clear', payload);
      },
    );
    try {
      final ElmInfo info = await obd.connectAndInit();
      final ActiveConnection connection = ActiveConnection(
        transport: transport,
        elm: elm,
        obd: obd,
        info: info,
      );
      _connecting = null;
      _setActive(connection);
      return connection;
    } on Object {
      await elm.close();
      _connecting = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final ActiveConnection? current = _active;
    _setActive(null);
    if (current != null) {
      await current.elm.close();
    }
  }
}

final class DeviceListing {
  const DeviceListing({
    this.devices = const [],
    this.error,
    this.needsSettings = false,
  });
  final List<BondedBluetoothDevice> devices;
  final String? error;
  final bool needsSettings;
}

final bondedDevicesProvider = FutureProvider<DeviceListing>((ref) async {
  try {
    final BluetoothPermissionResult permission =
        await requestBluetoothConnectPermission();
    if (permission != BluetoothPermissionResult.granted) {
      return DeviceListing(
        error: 'Se necesita el permiso BLUETOOTH_CONNECT para ver adaptadores emparejados. Permite Bluetooth en Ajustes de la aplicación.',
        needsSettings: true,
      );
    }
    final PlatformBtClassicChannel channel = PlatformBtClassicChannel();
    if (!await channel.isEnabled()) {
      return const DeviceListing(
        error: 'Bluetooth está apagado. Actívalo en Ajustes.',
      );
    }
    return DeviceListing(devices: await channel.bondedDevices());
  } on Object catch (error) {
    return DeviceListing(error: 'No se pudieron leer los dispositivos: $error');
  }
});
final trafficLogProvider = Provider<TrafficLog>(
  (ref) => ref.watch(connectionProvider)?.elm.log ?? TrafficLog(),
);
final terminalSenderProvider = Provider<Future<ElmResponse> Function(String)>(
  (ref) => (String command) async {
    final ActiveConnection? connection = ref.read(connectionProvider);
    if (connection == null) throw StateError('Conecta primero un adaptador.');
    return connection.elm.send(command);
  },
);
