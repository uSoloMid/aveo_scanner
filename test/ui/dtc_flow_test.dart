import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/data/backup_repository.dart';
import 'package:aveo_scanner/data/database.dart';
import 'package:aveo_scanner/app.dart';
import 'package:aveo_scanner/obd/obd_service.dart';
import 'package:aveo_scanner/ui/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('el borrado se rechaza si RPM es mayor que cero', () async {
    final transport = MockTransport(
      engineRunning: true,
      latency: () => Duration.zero,
    );
    await transport.connect();
    final elm = Elm327(transport, delay: (_) async {});
    final service = ObdService(elm, savePreClearBackup: (_) async {});
    await service.connectAndInit();

    await expectLater(
      service.clearDtcs(Confirmation.userApproved('04')),
      throwsStateError,
    );
    expect(transport.writtenCommands, isNot(contains('04')));
    await elm.close();
  });

  testWidgets('muestra P0133 y no envía 04 sin escribir BORRAR', (
    tester,
  ) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final backups = _InMemoryBackups(database);
    MockTransport? transport;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          backupRepositoryProvider.overrideWithValue(backups),
          bondedDevicesProvider.overrideWith(
            (ref) async => const DeviceListing(),
          ),
          mockTransportProvider.overrideWithValue(() {
            final instance = MockTransport(latency: () => Duration.zero);
            transport = instance;
            return instance;
          }),
        ],
        child: const AveoApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Simulador (sin carro)'));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Fallas').last);
    await tester.pump();
    await tester.tap(find.text('Confirmadas · modo 03'));
    await tester.pump();
    await tester.tap(find.text('Leer').first);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('P0133'), findsOneWidget);

    await tester.ensureVisible(find.text('Borrar códigos'));
    await tester.pump();
    await tester.tap(find.text('Borrar códigos'));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Antes de borrar'), findsOneWidget);
    expect(backups.saved.single['confirmed'], isNotEmpty);
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Confirmación final'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Borrar'))
          .onPressed,
      isNull,
    );
    expect(transport?.writtenCommands, isNot(contains('04')));
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
}

// sqflite FFI work does not complete under the widget-test fake clock.
class _InMemoryBackups extends BackupRepository {
  _InMemoryBackups(super.database);

  final List<Map<String, Object?>> saved = [];

  @override
  Future<int> save(String kind, Map<String, Object?> payload) async {
    saved.add(payload);
    return saved.length;
  }
}
