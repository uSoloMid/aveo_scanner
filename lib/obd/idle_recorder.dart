import 'dart:async';

import 'package:aveo_scanner/obd/dtc.dart';
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
    bool optional = false,
  }) => RecorderChannel(
    key: key,
    nameEs: nameEs,
    unit: unit,
    fast: fast,
    optional: optional,
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

  RecorderChannel withPriority(bool fast) => RecorderChannel(
    key: key,
    nameEs: nameEs,
    unit: unit,
    read: read,
    optional: optional,
    fast: fast,
  );
}

const estimatedThrottleReferenceKey = 'referencia_tps_estimada_pct';

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
  RecorderChannel.gm(gmDesiredIdle, fast: true),
  RecorderChannel.pid(17, 'mariposa_pct', 'Mariposa', '%', fast: true),
  RecorderChannel.pid(
    66,
    'voltaje_modulo_v',
    'Voltaje ECU',
    'V',
    optional: true,
  ),
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
    nameEs: 'Voltaje puerto OBD',
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
    this.readAt = const {},
    this.canEvaluate = false,
  });
  final DateTime at;
  final Map<String, DateTime> readAt;
  final bool canEvaluate;

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
    final double? speed = v['velocidad_kmh'];
    final double? throttle = v['mariposa_pct'];
    if (rpm == null ||
        desired == null ||
        speed == null ||
        throttle == null ||
        rpm <= 0 ||
        desired <= 0) {
      _high = false;
      _streak = 0;
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
    this.dtcInterval,
    Future<void> Function()? recover,
    Future<void> Function(Duration)? delay,
  }) : _channels = channels ?? defaultRecorderChannels(),
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _recover =
           recover ??
           (() async {
             if (!obd.elm.transport.isConnected) {
               await obd.elm.transport.connect();
             }
             await obd.connectAndInit();
           });

  final ObdService obd;
  final int slowPerCycle;
  final Duration? dtcInterval;
  DateTime? _lastDtcPoll;
  final Map<DtcKind, Set<String>> _observedCodes = {};
  DateTime? _engineStarted;
  bool _hasSeenEngineStopped = false;
  bool _startReferenceRecorded = false;
  bool _relativeElevated = false;
  final Future<void> Function() _recover;
  final Future<void> Function(Duration) _delay;
  int _cycleEcuReads = 0, _cleanCycles = 0;
  bool _rpmMissing = false;
  bool _retryUsed = false;
  bool _criticalMiss = false;
  int? _baselineGapMs;
  int _missingEngineCycles = 0;
  bool _engineLost = false;
  DateTime? _lastRecovery;
  final DateTime Function() _now;
  List<RecorderChannel> _channels;
  final Map<String, double?> _latest = {};
  final Map<String, DateTime> _readAt = {};
  final Map<String, DateTime> _attemptAt = {};
  final Map<String, int> _failures = {};
  Duration _interval(RecorderChannel c) => Duration(
    seconds: switch (c.key) {
      'map_kpa' => 1,
      'trim_corto_pct' ||
      'trim_largo_pct' ||
      'voltaje_bateria_v' ||
      'voltaje_modulo_v' => 3,
      'refrigerante_c' => 10,
      'aire_admision_c' => 20,
      _ => 6,
    },
  );
  static const maxAge = Duration(seconds: 15);
  static const _optionalRetryInterval = Duration(seconds: 30);
  final List<String> _pendingEvents = [];
  final HighIdleDetector detector = HighIdleDetector();
  final StreamController<RecorderSample> _samples =
      StreamController<RecorderSample>.broadcast();
  bool _running = false;
  int _okReads = 0;
  Future<void>? _loop;

  List<RecorderChannel> get channels => List.unmodifiable(_channels);
  bool get _estimatesThrottle =>
      _channels.any((c) => c.key == 'mariposa_pct' && c.fast) &&
      _channels.any((c) => c.key == 'mariposa_relativa_pct' && c.fast);

  List<RecorderChannel> get logChannels => [
    ..._channels,
    if (_estimatesThrottle)
      RecorderChannel(
        key: estimatedThrottleReferenceKey,
        nameEs: 'Referencia TPS estimada',
        unit: '%',
        read: (_) async => null,
      ),
  ];
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
  void mark(String label) =>
      _pendingEvents.add('${_now().toIso8601String()} $label');

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
    _cycleEcuReads = 0;
    _retryUsed = false;
    _criticalMiss = false;
    _baselineGapMs ??= obd.elm.minimumGap.inMilliseconds < 100
        ? 100
        : obd.elm.minimumGap.inMilliseconds;
    if (obd.elm.minimumGap.inMilliseconds < _baselineGapMs!) {
      obd.elm.minimumGap = Duration(milliseconds: _baselineGapMs!);
      _pendingEvents.add(
        'RITMO: pausa inicial de ${_baselineGapMs!} ms para priorizar estabilidad',
      );
    }
    for (final RecorderChannel c in fast) {
      if (c.optional &&
          (_failures[c.key] ?? 0) >= 3 &&
          _now().difference(_attemptAt[c.key]!) < _optionalRetryInterval) {
        continue;
      }
      var value = await _safeRead(c);
      if (value == null && !c.optional) {
        _criticalMiss = true;
        // One spaced retry per cycle, not a retry storm when ignition is off.
        if (!_retryUsed) {
          _retryUsed = true;
          await _delay(const Duration(milliseconds: 200));
          value = await _safeRead(c);
          _pendingEvents.add(
            value == null
                ? 'LECTURA: ${c.nameEs} sin respuesta tras reintento'
                : 'LECTURA: ${c.nameEs} recuperada en reintento',
          );
        }
      }
      _latest[c.key] = value;
    }
    for (int i = 0; i < slowPerCycle && slow.isNotEmpty; i++) {
      final now = _now();
      final due = slow.where((c) {
        final previous = _attemptAt[c.key];
        final interval = (_failures[c.key] ?? 0) >= 3
            ? _optionalRetryInterval
            : _interval(c);
        return previous == null || now.difference(previous) >= interval;
      }).toList();
      if (due.isEmpty) break;
      due.sort((a, b) {
        DateTime deadline(RecorderChannel c) => _attemptAt[c.key] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : _attemptAt[c.key]!.add(_interval(c));
        return deadline(a).compareTo(deadline(b));
      });
      final c = due.first;
      _latest[c.key] = await _safeRead(c);
    }
    // A failed RPM query is not a lost ECU if other queries still succeed.
    final readsRpmEachCycle = fast.any((c) => c.key == 'rpm');
    if (readsRpmEachCycle || fast.any((c) => c.key == 'mariposa_pct')) {
      if (_cycleEcuReads == 0) {
        _missingEngineCycles++;
        if (!_engineLost) {
          _engineLost = true;
          _pendingEvents.add('COMUNICACIÓN: sin respuesta del motor');
        }
      } else {
        _missingEngineCycles = 0;
        if (_engineLost) {
          _engineLost = false;
          _pendingEvents.add('COMUNICACIÓN: lecturas del motor recuperadas');
        }
        if (readsRpmEachCycle && _latest['rpm'] == null && !_rpmMissing) {
          _pendingEvents.add(
            'LECTURA: falta RPM; otras señales del motor responden',
          );
        } else if (_latest['rpm'] != null && _rpmMissing) {
          _pendingEvents.add('LECTURA: RPM disponible otra vez');
        }
      }
      _rpmMissing = _latest['rpm'] == null;
    }
    if (_criticalMiss) {
      _cleanCycles = 0;
      final gap = obd.elm.minimumGap.inMilliseconds;
      if (gap < 500) {
        obd.elm.minimumGap = Duration(milliseconds: (gap + 50).clamp(100, 500));
        _pendingEvents.add(
          'RITMO: pausa aumentada a ${obd.elm.minimumGap.inMilliseconds} ms por fallos de lectura',
        );
      }
    } else if (++_cleanCycles >= 20) {
      _cleanCycles = 0;
      final gap = obd.elm.minimumGap.inMilliseconds;
      if (gap > _baselineGapMs!) {
        obd.elm.minimumGap = Duration(
          milliseconds: (gap - 25).clamp(_baselineGapMs!, gap),
        );
        _pendingEvents.add(
          'RITMO: pausa reducida a ${obd.elm.minimumGap.inMilliseconds} ms tras 20 ciclos sin fallos rápidos',
        );
      }
    }
    final DateTime at = _now();
    final current = <String, double?>{
      for (final c in _channels)
        c.key:
            _readAt[c.key] != null &&
                at.difference(_readAt[c.key]!) <=
                    (c.fast || _interval(c) < maxAge
                        ? maxAge
                        : _interval(c) * 2)
            ? _latest[c.key]
            : null,
    };
    final canEvaluate =
        [
          'rpm',
          gmDesiredIdle.key,
          'velocidad_kmh',
          'mariposa_pct',
        ].every((key) => current[key] != null) &&
        (current['rpm'] ?? 0) > 0 &&
        (current[gmDesiredIdle.key] ?? 0) > 0;
    final String? auto = detector.update(current);
    final estimate = _evaluateThrottle(current, at);
    final List<String> events = [?auto, ..._pendingEvents];
    _pendingEvents.clear();
    return RecorderSample(
      at: at,
      readAt: Map.unmodifiable({
        ..._readAt,
        if (estimate != null)
          estimatedThrottleReferenceKey: _readAt['mariposa_relativa_pct']!,
      }),
      canEvaluate: canEvaluate,
      values: Map.unmodifiable({
        for (final RecorderChannel c in _channels) c.key: current[c.key],
        estimatedThrottleReferenceKey: ?estimate,
      }),
      events: List.unmodifiable(events),
      highIdle: detector.isHigh,
    );
  }

  double? _evaluateThrottle(Map<String, double?> values, DateTime at) {
    if (!_estimatesThrottle) return null;
    final rpm = values['rpm'];
    if ((rpm != null && rpm < 400) || _cycleEcuReads == 0) {
      _hasSeenEngineStopped = true;
      _engineStarted = null;
      _startReferenceRecorded = false;
      _relativeElevated = false;
    } else if (_hasSeenEngineStopped && rpm != null) {
      _engineStarted ??= at;
    }
    final absolute = values['mariposa_pct'];
    final relative = values['mariposa_relativa_pct'];
    if (absolute == null ||
        relative == null ||
        _readAt['mariposa_pct']!
                .difference(_readAt['mariposa_relativa_pct']!)
                .abs() >
            const Duration(seconds: 1)) {
      return null;
    }
    final estimate = absolute - relative;
    final speed = values['velocidad_kmh'];
    final nearClosed = absolute >= 9 && absolute <= 13;
    final stationary = speed != null && speed < 1;
    if (nearClosed && stationary && rpm != null && rpm >= 400) {
      final elapsed = _engineStarted == null
          ? null
          : at.difference(_engineStarted!);
      if (!_startReferenceRecorded &&
          elapsed != null &&
          elapsed >= const Duration(seconds: 5) &&
          elapsed <= const Duration(seconds: 10)) {
        _startReferenceRecorded = true;
        mark(
          'ARRANQUE: referencia TPS estimada ${estimate.toStringAsFixed(2)} %',
        );
      }
      if (!_relativeElevated && relative >= 3) {
        _relativeElevated = true;
        mark(
          'TPS: mariposa relativa elevada en reposo (${relative.toStringAsFixed(2)} %)',
        );
      } else if (relative < 2) {
        _relativeElevated = false;
      }
    } else {
      _relativeElevated = false;
    }
    return estimate;
  }

  Future<void> _pollCodes() async {
    final interval = dtcInterval;
    if (interval == null ||
        _cycleEcuReads == 0 ||
        (_lastDtcPoll != null && _now().difference(_lastDtcPoll!) < interval)) {
      return;
    }
    for (final kind in [DtcKind.confirmed, DtcKind.pending]) {
      if (!_running) break;
      try {
        final codes = (await obd.readDtcs(
          kind,
          requireResponse: true,
        )).map((code) => code.code).toSet();
        final previous = _observedCodes[kind];
        final added = previous == null ? codes : codes.difference(previous);
        if (previous == null || added.isNotEmpty) {
          final label = kind == DtcKind.confirmed
              ? 'confirmados'
              : 'pendientes';
          mark('DTC $label: ${added.isEmpty ? 'ninguno' : added.join(', ')}');
        }
        _observedCodes[kind] = codes;
      } on Object {
        mark('DTC ${kind.name}: lectura no disponible');
      }
    }
    _lastDtcPoll = _now();
  }

  Future<void> _run() async {
    while (_running) {
      final RecorderSample sample = await cycle();
      if (!_samples.isClosed) _samples.add(sample);
      if (_running) await _pollCodes();
      if (_missingEngineCycles >= 2 &&
          _running &&
          (_lastRecovery == null ||
              _now().difference(_lastRecovery!) >=
                  const Duration(seconds: 10))) {
        _lastRecovery = _now();
        _pendingEvents.add('COMUNICACIÓN: reiniciando enlace con el motor');
        // Keep the file open, but never carry values across ECU sessions.
        _latest.clear();
        _readAt.clear();
        _attemptAt.clear();
        _failures.clear();
        try {
          await _recover();
          _pendingEvents.add(
            'COMUNICACIÓN: enlace reiniciado; verificando lecturas',
          );
        } on Object {
          _pendingEvents.add(
            'COMUNICACIÓN: motor aún sin respuesta; se reintentará',
          );
        }
        _lastRecovery = _now();
      }
      if (_okReads == 0) {
        // Nothing answered (ignition off, adapter lost): don't spin.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<double?> _safeRead(RecorderChannel c) async {
    _attemptAt[c.key] = _now();
    try {
      final double? value = await c.read(obd);
      if (value != null) {
        _okReads++;
        if (c.key != 'voltaje_bateria_v') _cycleEcuReads++;
        _readAt[c.key] = _now();
        _failures[c.key] = 0;
      } else {
        _failures[c.key] = (_failures[c.key] ?? 0) + 1;
      }
      return value;
    } on Object {
      _failures[c.key] = (_failures[c.key] ?? 0) + 1;
      // Failed readings must not appear as current measurements.
      return null;
    }
  }
}
