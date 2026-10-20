import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:aveo_scanner/data/database.dart';

// Not final: widget tests substitute an in-memory fake (sqflite FFI does not
// progress under the fake test clock).
class BackupRepository {
  BackupRepository(
    this.database, {
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getExternalStorageDirectory;
  final AppDatabase database;
  final Future<Directory?> Function() _directoryProvider;
  Future<int> save(String kind, Map<String, Object?> payload) async =>
      (await database.database).insert('backups', <String, Object?>{
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'kind': kind,
        'payload': jsonEncode(payload),
      });
  Future<List<Map<String, Object?>>> list() async =>
      (await database.database).query('backups', orderBy: 'created_at DESC');
  Future<Map<String, Object?>?> get(int id) async {
    final List<Map<String, Object?>> rows = await (await database.database)
        .query('backups', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> exportJson(int id) async {
    final Map<String, Object?>? backup = await get(id);
    if (backup == null) throw StateError('No existe el respaldo solicitado.');
    final Directory? root = await _directoryProvider();
    if (root == null) {
      throw StateError('No hay almacenamiento externo disponible.');
    }
    final Directory folder = Directory(path.join(root.path, 'backups'));
    await folder.create(recursive: true);
    final Object? createdAt = backup['created_at'];
    final Object? payload = backup['payload'];
    if (createdAt is! int || payload is! String) {
      throw StateError('El respaldo guardado tiene datos inválidos.');
    }
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(
      createdAt,
      isUtc: true,
    );
    final String stamp = at
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final File file = File(path.join(folder.path, 'aveo_backup_$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonDecode(payload)),
    );
    return file.path;
  }
}
