import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:aveo_scanner/data/backup_repository.dart';
import 'package:aveo_scanner/data/database.dart';
import 'package:aveo_scanner/data/session_repository.dart';
import 'package:aveo_scanner/obd/pid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('guarda sesiones, lecturas con UTC ms y respaldos', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final sessions = SessionRepository(database);
    final backups = BackupRepository(database);
    final id = await sessions.start(
      transport: 'mock',
      protocol: 'CAN 11b 500k',
    );
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await sessions.addReadings(id, [PidValue(pid: 12, value: 850, at: at)]);
    await sessions.end(id);

    final db = await database.database;
    final reading = (await db.query('readings')).single;
    expect(reading['at'], at.millisecondsSinceEpoch);
    expect(reading['session_id'], id);
    final session = (await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(session['ended_at'], isA<int>());

    final backupId = await backups.save('initial', {
      'vehicle': {'vin': 'KL1TD5DE5CB000000'},
    });
    expect((await backups.list()).single['kind'], 'initial');
    expect(
      (await backups.get(backupId))?['payload'],
      contains('KL1TD5DE5CB000000'),
    );
    await database.close();
  });

  test('elimina lecturas al borrar la sesión por clave foránea', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final sessions = SessionRepository(database);
    final id = await sessions.start(transport: 'mock');
    await sessions.addReadings(id, [
      PidValue(pid: 12, value: 900, at: DateTime.now().toUtc()),
    ]);
    final db = await database.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    expect(await db.query('readings'), isEmpty);
    await database.close();
  });
}
