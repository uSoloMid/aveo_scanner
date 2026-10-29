import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:aveo_scanner/obd/idle_recorder.dart';

/// Public folder first: `Descargas/AveoScanner` is reachable from any app's
/// file picker (Claude, WhatsApp, Drive). Android 11+ lets an app write its
/// own files there without storage permissions.
const String publicLogsPath = '/storage/emulated/0/Download/AveoScanner';

/// Folder for CSV logs: public Downloads when writable, otherwise
/// `Android/data/<app id>/files/registros`.
Future<Directory> logsDirectory() async {
  if (Platform.isAndroid) {
    final Directory public = Directory(publicLogsPath);
    try {
      await public.create(recursive: true);
      final File probe = File(path.join(public.path, '.prueba'));
      await probe.writeAsString('ok');
      await probe.delete();
      return public;
    } on Object {
      // Older Android or blocked storage: fall back to the app folder.
    }
  }
  Directory? base;
  try {
    base = await getExternalStorageDirectory();
  } on Object {
    base = null;
  }
  base ??= await getApplicationDocumentsDirectory();
  final Directory dir = Directory(path.join(base.path, 'registros'));
  await dir.create(recursive: true);
  return dir;
}

/// Saved logs, newest first.
Future<List<File>> listLogs() async {
  final Directory dir = await logsDirectory();
  final List<File> files = [];
  await for (final FileSystemEntity e in dir.list()) {
    if (e is File && e.path.endsWith('.csv')) files.add(e);
  }
  files.sort(
    (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
  );
  return files;
}

String fileStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}_'
      '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
}

String clockStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

String csvCell(String value) =>
    value.contains(RegExp(r'[",\n]')) ? '"${value.replaceAll('"', '""')}"' : value;

/// Pure formatting, kept separate from file IO so it is unit-testable.
final class RecorderCsvFormat {
  const RecorderCsvFormat(this.channels);
  final List<RecorderChannel> channels;

  String header() => [
    'hora',
    'evento',
    'ralenti_alto',
    for (final RecorderChannel c in channels) c.key,
  ].join(',');

  String row(RecorderSample s) => [
    clockStamp(s.at),
    csvCell(s.events.join(' | ')),
    s.highIdle ? '1' : '0',
    for (final RecorderChannel c in channels) _number(s[c.key]),
  ].join(',');

  String _number(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }
}

/// Appends recorder samples to a CSV file, flushing every row so a crash or
/// a dead battery loses at most one second of data.
final class CsvLogWriter {
  CsvLogWriter._(this.file, this._sink, this._format);

  static Future<CsvLogWriter> create(
    List<RecorderChannel> channels, {
    Directory? directory,
    DateTime? now,
  }) async {
    final Directory dir = directory ?? await logsDirectory();
    final File file = File(
      path.join(dir.path, 'aveo_${fileStamp(now ?? DateTime.now())}.csv'),
    );
    final IOSink sink = file.openWrite();
    final RecorderCsvFormat format = RecorderCsvFormat(channels);
    sink.writeln(format.header());
    await sink.flush();
    return CsvLogWriter._(file, sink, format);
  }

  final File file;
  final IOSink _sink;
  final RecorderCsvFormat _format;
  int rows = 0;
  Future<void> _tail = Future<void>.value();

  /// Writes are chained: IOSink rejects a write while a flush is pending.
  Future<void> add(RecorderSample sample) {
    final String line = _format.row(sample);
    rows++;
    return _tail = _tail.then((_) async {
      _sink.writeln(line);
      await _sink.flush();
    });
  }

  Future<void> close() async {
    await _tail;
    await _sink.close();
  }
}
