import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aveo_scanner/data/database.dart';
import 'package:aveo_scanner/app.dart';
import 'package:aveo_scanner/ui/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('permite conectar al simulador y muestra RPM en el tablero', (
    tester,
  ) async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          bondedDevicesProvider.overrideWith(
            (ref) async => const DeviceListing(),
          ),
        ],
        child: const AveoApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Simulador (sin carro)'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Tablero').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('RPM'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
}
