import 'package:sqflite/sqflite.dart';
import 'package:aveo_scanner/data/database.dart';
import 'package:aveo_scanner/obd/pid.dart';

final class SessionRepository {
  SessionRepository(this.database);
  final AppDatabase database;
  Future<int> start({
    required String transport,
    String? protocol,
    String? vin,
  }) async {
    final Database db = await database.database;
    return db.insert('sessions', <String, Object?>{
      'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'transport': transport,
      'protocol': protocol,
      'vin': vin,
    });
  }

  Future<void> end(int id) async => (await database.database).update(
    'sessions',
    <String, Object?>{
      'ended_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );
  Future<void> addReadings(int id, List<PidValue> values) async {
    if (values.isEmpty) return;
    final DatabaseExecutor db = await database.database;
    final Batch batch = db.batch();
    for (final PidValue value in values) {
      batch.insert('readings', <String, Object?>{
        'session_id': id,
        'at': value.at.toUtc().millisecondsSinceEpoch,
        'pid': value.pid,
        'value': value.value,
      });
    }
    await batch.commit(noResult: true);
  }
}
