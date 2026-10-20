import 'dart:async';

enum Direction { tx, rx, guard }

final class TrafficEntry {
  const TrafficEntry({required this.at, required this.dir, required this.text});
  final DateTime at;
  final Direction dir;
  final String text;
}

final class TrafficLog {
  TrafficLog({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final List<TrafficEntry> _entries = [];
  final StreamController<List<TrafficEntry>> _changes =
      StreamController.broadcast();
  List<TrafficEntry> get entries => List.unmodifiable(_entries);
  Stream<List<TrafficEntry>> get changes => _changes.stream;
  void add(Direction dir, String text) {
    _entries.add(TrafficEntry(at: _now(), dir: dir, text: text));
    if (_entries.length > 500) {
      _entries.removeAt(0);
    }
    _changes.add(entries);
  }

  Future<void> close() => _changes.close();
}
