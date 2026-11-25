import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/data/csv_log_writer.dart';
import 'package:aveo_scanner/ui/log_files_section.dart';

void main() {
  testWidgets('select all and delete exclude the active recording', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('aveo_logs_test_');
    final protected = File(path.join(dir.path, 'active.csv'))
      ..writeAsStringSync('active');
    final closed = File(path.join(dir.path, 'closed.csv'))
      ..writeAsStringSync('closed');
    CsvLogWriter.activePaths.add(protected.path);
    final key = GlobalKey<LogFilesSectionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LogFilesSection(key: key, directory: dir),
          ),
        ),
      ),
    );
    await tester.runAsync(() => key.currentState!.refresh());
    await tester.pump();
    expect(find.text('Grabando · archivo protegido'), findsOneWidget);
    await tester.tap(find.text('Seleccionar todos / ninguno'));
    await tester.pump();
    expect(find.text('Compartir (1)'), findsOneWidget);
    await tester.tap(find.text('Eliminar seleccionados'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar 1 registros?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(closed.existsSync(), false);
    expect(protected.existsSync(), true);
    await tester.pumpWidget(const SizedBox.shrink());
    CsvLogWriter.activePaths.remove(protected.path);
    protected.deleteSync();
    dir.deleteSync();
  });
  test('raw ELM carriage returns are quoted as CSV cells', () {
    expect(csvCell('410C1234\r>'), '"410C1234\r>"');
  });
}
