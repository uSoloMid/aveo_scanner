import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final class AppDatabase {
  AppDatabase({DatabaseFactory? factory, this._databasePath})
    : _factory = factory ?? databaseFactory;
  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  Future<Database> get database async {
    final Database? current = _database;
    if (current != null) return current;
    final String file =
        _databasePath ??
        path.join(
          (await getApplicationDocumentsDirectory()).path,
          'aveo_scanner.db',
        );
    final Database opened = await _factory.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, transport TEXT NOT NULL, protocol TEXT, vin TEXT)',
          );
          await db.execute(
            'CREATE TABLE readings (session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, at INTEGER NOT NULL, pid INTEGER NOT NULL, value REAL NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX idx_readings_session ON readings(session_id, at)',
          );
          await db.execute(
            "CREATE TABLE backups (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL)",
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 1) {
            await db.execute(
              'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER NOT NULL, ended_at INTEGER, transport TEXT NOT NULL, protocol TEXT, vin TEXT)',
            );
            await db.execute(
              'CREATE TABLE readings (session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, at INTEGER NOT NULL, pid INTEGER NOT NULL, value REAL NOT NULL)',
            );
            await db.execute(
              'CREATE INDEX idx_readings_session ON readings(session_id, at)',
            );
            await db.execute(
              "CREATE TABLE backups (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL)",
            );
          }
        },
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
