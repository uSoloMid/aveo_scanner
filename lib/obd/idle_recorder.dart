import 'dart:async';

import 'package:aveo_scanner/obd/gm_pids.dart';
import 'package:aveo_scanner/obd/obd_service.dart';

/// One value the recorder reads from the car.
final class RecorderChannel {
  const RecorderChannel({
    required this.key,
    required this.nameEs,
    required this.unit,
    required this.read,
    this.fast = false,
    this.optional = false,
  });

  /// Standard mode 01 PID.
  factory RecorderChannel.pid(
    int pid,
    String key,
    String nameEs,
    String unit, {
    bool fast = false,
  }) => RecorderChannel(
    key: key,
    nameEs: nameEs,
    unit: unit,
    fast: fast,
    read: (ObdService obd) async => (await obd.readPids([pid]))[pid]?.value,
  );

  /// GM mode 22 identifier. Unverified ones are optional: probed once and
  /// dropped when the ECU does not answer.
  factory RecorderChannel.gm(GmPidDef def, {bool fast = false}) =>
      RecorderChannel(
        key: def.key,
        nameEs: def.nameEs,
        unit: def.unit,
        fast: fast,
        optional: !def.verified,
        read: (ObdService obd) => obd.readGm(def),
      );

  final String key, nameEs, unit;

  /// Fast channels are read every cycle; the rest round-robin.
  final bool fast;
  final bool optional;
  final Future<double?> Function(ObdService) read;
}

/// The idle diagnosis set. Fast ones answer "does the ECU want this idle and
/// where is the IAC" about once per second on KWP at 10.4 kbaud.
List<RecorderChannel> defaultRecorderChannels() => [
  RecorderChannel.pid(12, 'rpm', 'RPM', 'rpm', fast: true),
  RecorderChannel.gm(gmIacPosition, fast: true),
  RecorderChannel.pid(
    69,
    'mariposa_relativa_pct',
    'Mariposa relativa',
    '%',
    fast: true,
  ),
  RecorderChannel.pid(13, 'velocidad_kmh', 'Velocidad', 'km/h', fast: true),
  RecorderChannel.gm(gmDesiredIdle),
  RecorderChannel.pid(17, 'mariposa_pct', 'Mariposa', '%'),
  RecorderChannel.pid(5, 'refrigerante_c', 'Refrigerante', '°C'),
  RecorderChannel.pid(11, 'map_kpa', 'MAP', 'kPa'),
  RecorderChannel.pid(14, 'avance_grados', 'Avance', '°'),
  RecorderChannel.pid(6, 'trim_corto_pct', 'Trim corto', '%'),
  RecorderChannel.pid(7, 'trim_largo_pct', 'Trim largo', '%'),
  RecorderChannel.pid(15, 'aire_admision_c', 'Aire admisión', '°C'),
  RecorderChannel.pid(4, 'carga_pct', 'Carga', '%'),
  RecorderChannel.pid(20, 'o2_1_v', 'Sensor O2 1', 'V'),
  RecorderChannel.pid(21, 'o2_2_v', 'Sensor O2 2', 'V'),
  RecorderChannel.pid(3, 'estado_combustible', 'Estado combustible', ''),
  RecorderChannel(
    key: 'voltaje_bateria_v',
    nameEs: 'Batería',
    unit: 'V',
    read: (ObdService obd) => obd.readAdapterVoltage(),
  ),
  for (final GmPidDef def in gmPids)
    if (!def.verified && def.recordByDefault) RecorderChannel.gm(def),
];

final class RecorderSample {
  const RecorderSample({
    required this.at,
    required this.values,
    required this.events,
    required this.highIdle,
  });
  final DateTime at;

  /// Latest known value per channel key (null = never read yet).
  final Map<String, double?> values;
  final List<String> events;
  final bool highIdle;

  double? operator [](String key) => values[key];
}

/// Rules for flagging a high idle: engine running, car stopped, and RPM well
/// above what the ECU asks for. Hysteresis avoids flapping on a throttle blip.
final class HighIdleDetector {
  HighIdleDetector({this.enterDelta = 300, this.exitDelta = 150});
  final double enterDelta, exitDelta;
  bool _high = false;
  int _streak = 0;

  bool get isHigh => _high;

  /// Returns an event description when the state changes, otherwise null.
  String? update(Map<String, double?> v) {
    final double? rpm = v['rpm'], desired = v[gmDesiredIdle.key];
    final double speed = v['velocidad_kmh'] ?? 0;
    final double throttle = v['mariposa_pct'] ?? 0;
    if (rpm == null || desired == null || rpm <= 0 || desired <= 0) {
      return null;
    }
    final bool idleConditions = speed < 2 && throttle < 14;
    final double delta = rpm - desired;
    if (!_high) {
      _streak = idleConditions && delta > enterDelta ? _streak + 1 : 0;
      if (_streak >= 2) {
        _high = true;
        return 'AUTO: ralentí alto (${rpm.round()} rpm, pide ${desired.round()})';
      }
    } else if (!idleConditions || delta < exitDelta) {
      _high = false;
      _streak = 0;
      return idleConditions
          ? 'AUTO: ralentí normal (${rpm.round()} rpm)'
          : 'AUTO: fin ralentí alto (se movió o aceleró)';
    }
    return null;
  }
}

/// Polls the ECU in a loop and emits one [RecorderSample] per cycle.
final class IdleRecorder {
  IdleRecorder(
    this.obd, {
    List<RecorderChannel>? channels,
    DateTime Function()? now,
    this.slowPerCycle = 3,
  }) : _channels = channels ?? defaultRecorderChannels(),
       _now = now ?? DateTime.now;

  final ObdService obd;
  final int slowPerCycle;
  final DateTime Function() _now;
  List<RecorderChannel> _channels;
  final Map<String, double?> _latest = {};
  final List<String> _pendingEvents = [];
  final HighIdleDetector detector = HighIdleDetector();
  final StreamController<RecorderSample> _samples =
      StreamController<RecorderSample>.broadcast();
  bool _running = false;
  int _slowIndex = 0;
  int _okReads = 0;
  Future<void>? _loop;

  List<RecorderChannel> get channels => List.unmodifiable(_channels);
  Stream<RecorderSample> get samples => _samples.stream;
  bool get isRunning => _running;

  /// Tries every optional channel once and keeps only those the ECU answers.
  /// Returns the names that were dropped.
  Future<List<String>> probe() async {
    final List<RecorderChannel> kept = [];
    final List<String> dropped = [];
    for (final RecorderChannel c in _channels) {
      if (!c.optional) {
        kept.add(c);
        continue;
      }
      final double? value = await _safeRead(c);
      if (value == null) {
        dropped.add(c.nameEs);
      } else {
        _latest[c.key] = value;
        kept.add(c);
      }
    }
    _channels = kept;
    return dropped;
  }

  /// Adds a manual marker to the next sample (e.g. "se aceleró").
  void mark(String label) => _pendingEvents.add(label);

  void start() {
    if (_running) return;
    _running = true;
    _loop = _run();
  }

  Future<void> stop() async {
    _running = false;
    await _loop;
    _loop = null;
  }

  Future<void> dispose() async {
    await stop();
    await _samples.close();
  }

  /// Runs a single read cycle. Public so tests can step deterministically.
  Future<RecorderSample> cycle() async {
    final List<RecorderChannel> fast = [
      for (final RecorderChannel c in _channels)
        if (c.fast) c,
    ];
    final List<RecorderChannel> slow = [
      for (final RecorderChannel c in _channels)
        if (!c.fast) c,
    ];
    _okReads = 0;
    for (final RecorderChannel c in fast) {
      _latest[c.key] = await _safeRead(c) ?? _latest[c.key];
    }
    for (int i = 0; i < slowPerCycle && slow.isNotEmpty; i++) {
      final RecorderChannel c = slow[_slowIndex++ % slow.length];
      _latest[c.key] = await _safeRead(c) ?? _latest[c.key];
    }
    final String? auto = detector.update(_latest);
    final List<String> events = [?auto, ..._pendingEvents];
    _pendingEvents.clear();
    return RecorderSample(
      at: _now(),
      values: Map.unmodifiable({
        for (final RecorderChannel c in _channels) c.key: _latest[c.key],
      }),
      events: List.unmodifiable(events),
      highIdle: detector.isHigh,
    );
  }

  Future<void> _run() async {
    while (_running) {
      final RecorderSample sample = await cycle();
      if (!_samples.isClosed) _samples.add(sample);
      if (_okReads == 0) {
        // Nothing answered (ignition off, adapter lost): don't spin.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<double?> _safeRead(RecorderChannel c) async {
    try {
      final double? value = await c.read(obd);
      if (value != null) _okReads++;
      return value;
    } on Object {
      // Timeouts and NO DATA are normal on K-Line; keep the last value.
      return null;
    }
  }
}
