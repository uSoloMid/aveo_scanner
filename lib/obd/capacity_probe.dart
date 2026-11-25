import 'dart:async';

import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/query_metric.dart';
import 'package:aveo_scanner/obd/gm_pids.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';

class CapacityPhase {
  const CapacityPhase(
    this.name,
    this.commands,
    this.gapMs,
    this.adaptive,
    this.duration, {
    this.timeoutHex = '32',
  });
  final String name;
  final List<String> commands;
  final int gapMs, adaptive;
  final String timeoutHex;
  final Duration duration;
}

class CapacityResult {
  CapacityResult(
    this.phase,
    this.attempts,
    this.valid,
    this.elapsed,
    this.durations,
    this.aborted,
  );
  final CapacityPhase phase;
  final int attempts, valid;
  final Duration elapsed;
  final List<double> durations;
  final bool aborted;
  double get rate =>
      elapsed.inMicroseconds == 0 ? 0 : valid * 1e6 / elapsed.inMicroseconds;
  double get success => attempts == 0 ? 0 : valid / attempts;
  bool get stable => !aborted && attempts >= 10 && success >= .98;
  double get p95 {
    if (durations.isEmpty) return 0;
    final sorted = [...durations]..sort();
    return sorted[((sorted.length - 1) * .95).ceil()];
  }
}

/// Bounded load test: never pipelines ECU requests or changes ECU state.
/// Limits and stability thresholds are engineering policy, not vehicle specifications.
class CapacityProbe {
  CapacityProbe(
    this.elm, {
    this.phaseDuration = const Duration(seconds: 15),
    this.enduranceDuration = const Duration(seconds: 120),
  });
  final Elm327 elm;
  final Duration phaseDuration, enduranceDuration;
  bool cancelled = false;
  final List<CapacityResult> results = [];
  final List<String> available = [];
  CapacityResult? recommendation;
  String stage = '';
  void cancel() => cancelled = true;

  static bool validResponse(String command, ElmResponse response) {
    if (response.error != null || response.isNegative) return false;
    if (const ['ATI', 'ATDP', 'ATDPN'].contains(command)) {
      return (response.text ?? '').isNotEmpty && response.text?.trim() != '?';
    }
    if (command.startsWith('01') && command.length == 4) {
      final pid = int.parse(command.substring(2), radix: 16);
      final def = standardPids[pid];
      if (def == null) return false;
      return response.messages.any((m) {
        for (var i = 0; i + 2 + def.bytes <= m.data.length; i++) {
          if (m.data[i] == 0x41 && m.data[i + 1] == pid) return true;
        }
        return false;
      });
    }
    if (command.startsWith('22')) {
      final id = int.parse(command.substring(2), radix: 16);
      final payload = mode22Payload([
        for (final m in response.messages) m.data,
      ], id);
      return payload != null && payload.isNotEmpty;
    }
    return false;
  }

  Future<void> run({
    required void Function() onProgress,
    required Future<void> Function(
      String phase,
      String command,
      bool valid,
      String? error,
      QueryMetric? metric,
    )
    onQuery,
  }) async {
    final previousGap = elm.minimumGap;
    final previousAdaptive = elm.preferredAdaptive;
    final previousTimeout = elm.preferredTimeoutHex;
    QueryMetric? last;
    final subscription = elm.metrics.listen((m) => last = m);
    // Metrics are dispatched synchronously with the command completion only after
    // the stream microtask; let that delivery complete before taking a snapshot.
    Future<bool> query(String phase, String command) async {
      last = null;
      var valid = false;
      String? error;
      try {
        final response = await elm.send(command);
        valid = validResponse(command, response);
        error =
            response.error?.name ??
            (response.isNegative
                ? 'negative_${response.negativeCode}'
                : valid
                ? null
                : 'unexpected_payload');
      } on Object catch (e) {
        error = e.runtimeType.toString();
      }
      await Future<void>.delayed(Duration.zero);
      await onQuery(phase, command, valid, error, last);
      return valid;
    }

    try {
      stage = 'Comprobando parámetros disponibles';
      onProgress();
      elm.minimumGap = const Duration(milliseconds: 250);
      await elm.send('ATAT1');
      for (final command in ['ATI', 'ATDP', 'ATDPN']) {
        if (cancelled) break;
        await query('identificacion_declarada', command);
      }
      for (final command in [
        '010C',
        '221192',
        '221172',
        '0111',
        '0145',
        '010D',
        '010B',
        '0106',
        '0107',
        '0105',
        '010F',
        '0142',
      ]) {
        if (cancelled) break;
        // Retry once: an isolated missed reply is not proof of unsupported data.
        if (await query('disponibilidad', command) ||
            (!cancelled && await query('disponibilidad_reintento', command))) {
          available.add(command);
        }
      }
      if (cancelled) return;
      if (!available.contains('010C')) {
        throw StateError(
          'El motor no responde RPM; revisa contacto y conexión.',
        );
      }
      final mixed = available
          .where(
            (c) => [
              '010C',
              '221192',
              '221172',
              '0111',
              '0145',
              '010D',
            ].contains(c),
          )
          .toList();
      final phases = [
        CapacityPhase(
          'Adaptador sin consultar ECU',
          ['ATI'],
          50,
          1,
          phaseDuration,
        ),
        CapacityPhase('RPM sola', ['010C'], 50, 1, phaseDuration),
        CapacityPhase(
          'Grupo espera fija 400 ms pausa 250 ms',
          mixed,
          250,
          0,
          phaseDuration,
          timeoutHex: '64',
        ),
        for (final gap in [250, 100, 50])
          CapacityPhase(
            'Grupo AT1 pausa $gap ms',
            mixed,
            gap,
            1,
            phaseDuration,
          ),
        CapacityPhase('Grupo AT2 pausa 50 ms', mixed, 50, 2, phaseDuration),
        CapacityPhase(
          'Grupo ampliado AT1 pausa 50 ms',
          available,
          50,
          1,
          phaseDuration,
        ),
        CapacityPhase(
          'Grupo ampliado AT2 pausa 50 ms',
          available,
          50,
          2,
          phaseDuration,
        ),
      ];
      Future<CapacityResult> measure(CapacityPhase phase) async {
        stage = phase.name;
        onProgress();
        elm.minimumGap = Duration(milliseconds: phase.gapMs);
        final timeoutConfig = await elm.send('ATST${phase.timeoutHex}');
        if (timeoutConfig.text?.trim() != 'OK') {
          return CapacityResult(phase, 0, 0, Duration.zero, [], true);
        }
        final config = await elm.send('ATAT${phase.adaptive}');
        if (config.error != null || config.text?.trim() != 'OK') {
          return CapacityResult(phase, 0, 0, Duration.zero, [], true);
        }
        // Returning from adapter-only commands may require KWP link recovery.
        // Log and exclude preparation; never count warm-up as saturation.
        if (!phase.commands.every((c) => c.startsWith('AT'))) {
          var consecutive = 0;
          for (
            var attempt = 0;
            attempt < 6 && consecutive < 3 && !cancelled;
            attempt++
          ) {
            if (await query('Preparación: ${phase.name}', '010C')) {
              consecutive++;
            } else {
              consecutive = 0;
            }
          }
          if (consecutive < 3) {
            return CapacityResult(phase, 0, 0, Duration.zero, [], true);
          }
        }
        final watch = Stopwatch()..start();
        var attempts = 0, valid = 0, streak = 0;
        final durations = <double>[];
        var abort = false;
        while (!cancelled && watch.elapsed < phase.duration) {
          final command = phase.commands[attempts % phase.commands.length];
          final start = Stopwatch()..start();
          final ok = await query(phase.name, command);
          durations.add(start.elapsedMicroseconds / 1000);
          attempts++;
          if (ok) {
            valid++;
            streak = 0;
          } else {
            streak++;
          }
          if (streak >= 3 ||
              (attempts >= 10 && (attempts - valid) / attempts > .1)) {
            abort = true;
            break;
          }
          onProgress();
        }
        return CapacityResult(
          phase,
          attempts,
          valid,
          watch.elapsed,
          durations,
          abort || cancelled,
        );
      }

      for (final phase in phases) {
        if (cancelled) break;
        var result = await measure(phase);
        results.add(result);
        if (!cancelled &&
            phase.name.startsWith('Grupo') &&
            !result.stable &&
            !result.aborted) {
          final repeat = CapacityPhase(
            '${phase.name} · repetición',
            phase.commands,
            phase.gapMs,
            phase.adaptive,
            phase.duration,
            timeoutHex: phase.timeoutHex,
          );
          result = await measure(repeat);
          results.add(result);
        }
        // Adapter-only/RPM results do not establish capacity of the mixed set.
        // Do not ramp up after the conservative mixed baseline fails.
        if (phase.name.startsWith('Grupo') &&
            result.aborted &&
            phase.adaptive == 1) {
          break;
        }
      }
      final stable =
          results
              .where(
                (r) =>
                    r.phase.name.startsWith('Grupo') &&
                    !r.phase.name.contains('ampliado') &&
                    r.stable,
              )
              .toList()
            ..sort((a, b) => b.rate.compareTo(a.rate));
      if (!cancelled && stable.isNotEmpty) {
        final best = stable.first;
        final validation = await measure(
          CapacityPhase(
            'Validación sostenida',
            mixed,
            best.phase.gapMs,
            best.phase.adaptive,
            enduranceDuration,
            timeoutHex: best.phase.timeoutHex,
          ),
        );
        results.add(validation);
        if (validation.stable) recommendation = validation;
      }
    } finally {
      elm.minimumGap = previousGap;
      try {
        await elm.send('ATST$previousTimeout');
        await elm.send('ATAT$previousAdaptive');
      } finally {
        await subscription.cancel();
      }
      stage = cancelled ? 'Prueba cancelada' : 'Prueba terminada';
      onProgress();
    }
  }
}
