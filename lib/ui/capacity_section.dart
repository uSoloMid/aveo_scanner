import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:aveo_scanner/data/csv_log_writer.dart';
import 'package:aveo_scanner/obd/capacity_probe.dart';
import 'package:aveo_scanner/ui/providers.dart';
import 'package:aveo_scanner/ui/log_files_section.dart';

class CapacitySection extends ConsumerStatefulWidget {
  const CapacitySection({super.key, required this.onSaved});
  final VoidCallback onSaved;
  @override
  ConsumerState<CapacitySection> createState() => _CapacitySectionState();
}

class _CapacitySectionState extends ConsumerState<CapacitySection> {
  CapacityProbe? _probe;
  String? _message;
  File? _report;
  bool _running = false;
  Future<void> _run() async {
    final connection = ref.read(connectionProvider);
    if (connection == null || ref.read(acquisitionProvider) != null) return;
    final owner = ref.read(acquisitionProvider.notifier);
    owner.set('Prueba de capacidad en curso');
    setState(() {
      _running = true;
      _report = null;
      _message = null;
    });
    IOSink? sink;
    File? file;
    try {
      final initial = await connection.obd.readPids([12, 13]);
      final speed = initial[13]?.value;
      if (speed == null || speed >= 2 || (initial[12]?.value ?? 0) <= 0) {
        throw StateError(
          'La prueba requiere motor encendido, carro detenido y lecturas de RPM y velocidad.',
        );
      }
      final dir = await logsDirectory();
      file = File(
        path.join(dir.path, 'capacidad_${fileStamp(DateTime.now())}.csv'),
      );
      CsvLogWriter.activePaths.add(file.path);
      sink = file.openWrite();
      final output = sink;
      output.writeln(
        'tipo,fase,comando,fecha_hora,valida,error,cola_ms,total_ms,primer_byte_ms,respuesta_ms,interpretacion_ms,respuesta_original,intentos,validas,segundos,validas_por_segundo,p95_ms,estable',
      );
      output.writeln(
        [
          'metadatos',
          '',
          '',
          DateTime.now().toIso8601String(),
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          jsonEncode({
            'adaptador': connection.info.version,
            'transporte': connection.transport.label,
            'protocolo': connection.info.protocolCode,
            'app': '1.1.1+3',
            'simulador': connection.transport.label == 'mock',
            'minimo_pausa_ms': 50,
            'criterio_estable':
                '>=10 intentos y >=98% respuestas válidas sin corte',
            'limite': 'Máximo observado entre ajustes probados; no mide ocupación física del bus.',
          }),
        ].map((v) => csvCell(v.toString())).join(','),
      );
      // Isolate the phone's file/flush path from adapter and ECU response time.
      final localFile = File(
        path.join(
          dir.path,
          '.capacidad_celular_${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      final localSink = localFile.openWrite();
      final diskWatch = Stopwatch()..start();
      try {
        for (var i = 0; i < 200; i++) {
          localSink.writeln('$i,${List.filled(80, '123.456').join(',')}');
          await localSink.flush();
        }
      } finally {
        await localSink.close();
        await localFile.delete();
      }
      output.writeln(
        [
          'celular',
          'Guardado local con vaciado por fila',
          '',
          DateTime.now().toIso8601String(),
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          jsonEncode({
            'filas': 200,
            'milisegundos': diskWatch.elapsedMilliseconds,
            'filas_por_segundo':
                200 * 1000000 / diskWatch.elapsedMicroseconds.clamp(1, 1 << 60),
            'nota': 'Prueba sintética de escritura; no es capacidad de lecturas OBD.',
          }),
        ].map((v) => csvCell(v.toString())).join(','),
      );
      final perCommand = <String, List<double>>{};
      final errorsByCommand = <String, int>{};
      final attemptsByCommand = <String, int>{};
      final probe = CapacityProbe(connection.elm);
      _probe = probe;
      await probe.run(
        onProgress: () {
          if (mounted) setState(() {});
        },
        onQuery: (phase, command, valid, error, metric) async {
          attemptsByCommand.update(command, (n) => n + 1, ifAbsent: () => 1);
          if (!valid) {
            errorsByCommand.update(command, (n) => n + 1, ifAbsent: () => 1);
          }
          if (metric != null) {
            perCommand.putIfAbsent(command, () => []).add(metric.elapsedMs);
          }
          output.writeln(
            [
              'consulta',
              phase,
              command,
              metric?.at.toIso8601String() ?? DateTime.now().toIso8601String(),
              valid ? 1 : 0,
              error ?? '',
              metric?.queueMs ?? '',
              metric?.elapsedMs ?? '',
              metric?.firstByteMs ?? '',
              metric?.wireMs ?? '',
              metric?.parseMs ?? '',
              metric?.raw ?? '',
            ].map((v) => csvCell(v.toString())).join(','),
          );
          await output.flush();
        },
      );
      for (final command in attemptsByCommand.keys) {
        final durations = perCommand[command] ?? [];
        durations.sort();
        output.writeln(
          [
            'parametro',
            'Resumen de todas las etapas (ajustes distintos)',
            command,
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            jsonEncode({
              'intentos': attemptsByCommand[command],
              'errores': errorsByCommand[command] ?? 0,
              'p95_total_ms': durations.isEmpty
                  ? null
                  : durations[((durations.length - 1) * .95).ceil()],
            }),
          ].map((v) => csvCell(v.toString())).join(','),
        );
      }
      for (final result in probe.results) {
        output.writeln(
          [
            'resumen',
            result.phase.name,
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            result.attempts,
            result.valid,
            result.elapsed.inMilliseconds / 1000,
            result.rate.toStringAsFixed(3),
            result.p95.toStringAsFixed(2),
            result.stable ? 1 : 0,
          ].map((v) => csvCell(v.toString())).join(','),
        );
      }
      if (mounted) {
        setState(() {
          _message = probe.cancelled
              ? 'Prueba cancelada. Se conserva el resultado parcial.'
              : probe.recommendation == null
              ? 'Sin configuración validada. Revisa los errores del informe.'
              : 'Configuración validada durante 2 minutos. El resultado es un límite observado, no una garantía en todas las condiciones.';
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _message = 'La prueba se detuvo: $e');
    } finally {
      try {
        await sink?.close();
      } on Object catch (e) {
        if (mounted) {
          setState(() => _message = 'No se pudo guardar el informe: $e');
        }
      }
      if (file != null) CsvLogWriter.activePaths.remove(file.path);
      owner.set(null);
      if (mounted) {
        setState(() {
          _running = false;
          _report = file;
        });
        widget.onSaved();
      }
    }
  }

  Future<void> _apply() async {
    final best = _probe?.recommendation;
    final connection = ref.read(connectionProvider);
    if (best == null ||
        connection == null ||
        ref.read(acquisitionProvider) != null) {
      return;
    }
    final owner = ref.read(acquisitionProvider.notifier);
    owner.set('Aplicando ajuste de lectura');
    final oldTimeout = connection.elm.preferredTimeoutHex;
    final oldAdaptive = connection.elm.preferredAdaptive;
    try {
      final timeoutResponse = await connection.elm.send(
        'ATST${best.phase.timeoutHex}',
      );
      if (timeoutResponse.text?.trim() != 'OK') {
        throw StateError('No se aceptó el tiempo de espera');
      }
      final response = await connection.elm.send('ATAT${best.phase.adaptive}');
      if (response.error != null || response.text?.trim() != 'OK') {
        throw StateError('El adaptador no aceptó el ajuste');
      }
      connection.elm.preferredAdaptive = best.phase.adaptive;
      connection.elm.preferredTimeoutHex = best.phase.timeoutHex;
      connection.elm.minimumGap = Duration(milliseconds: best.phase.gapMs + 50);
      if (mounted) {
        setState(
          () => _message = 'Ajuste aplicado con 50 ms adicionales de margen. Válido durante esta conexión; vuelve a comprobarlo si cambias de adaptador.',
        );
      }
    } on Object catch (e) {
      try {
        await connection.elm.send('ATST$oldTimeout');
        await connection.elm.send('ATAT$oldAdaptive');
      } on Object {
        /* The adapter may be disconnected. */
      }
      if (mounted) setState(() => _message = 'No se pudo aplicar: $e');
    } finally {
      owner.set(null);
    }
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(acquisitionProvider) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capacidad de lectura',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Prueba de unos 5–8 minutos, con el carro detenido y el motor encendido. '
          'Compara esperas fijas y adaptativas, RPM sola y grupos de señales. Aumenta el ritmo hasta el límite probado y valida 2 minutos. '
          'Se detiene si se acumulan errores. Puedes cancelarla.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _run,
              icon: const Icon(Icons.speed),
              label: const Text('Medir capacidad'),
            ),
            if (_running)
              OutlinedButton(
                onPressed: () => _probe?.cancel(),
                child: const Text('Cancelar prueba'),
              ),
            if (!_running && _probe?.recommendation != null)
              OutlinedButton(
                onPressed: busy ? null : _apply,
                child: const Text('Usar ajuste con margen'),
              ),
            if (!_running && _report != null)
              OutlinedButton.icon(
                onPressed: () => shareLog(_report!),
                icon: const Icon(Icons.share),
                label: const Text('Compartir informe'),
              ),
          ],
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          Text(_probe?.stage ?? 'Preparando…'),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!),
          ),
        if (_probe != null)
          for (final result in _probe!.results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${result.phase.name}: ${result.rate.toStringAsFixed(2)} respuestas válidas/s · '
                '${result.phase.commands.length} señales · ${result.valid}/${result.attempts} · p95 ${result.p95.round()} ms · '
                '${result.stable ? 'estable en esta prueba' : 'no validada'}',
              ),
            ),
      ],
    );
  }
}
