import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:aveo_scanner/data/csv_log_writer.dart';
import 'package:aveo_scanner/obd/gm_pids.dart';
import 'package:aveo_scanner/obd/idle_recorder.dart';
import 'package:aveo_scanner/obd/mode22_scanner.dart';
import 'package:aveo_scanner/ui/log_files_section.dart';
import 'package:aveo_scanner/ui/providers.dart';

/// Idle diagnosis: continuous CSV recorder with event markers, plus a
/// mode 22 scanner to discover what else the MR-140 exposes.
class DiagnosticScreen extends ConsumerStatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  ConsumerState<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends ConsumerState<DiagnosticScreen> {
  IdleRecorder? _recorder;
  CsvLogWriter? _writer;
  StreamSubscription<RecorderSample>? _sub;
  RecorderSample? _last;
  final List<String> _events = [];
  String? _message;
  bool _starting = false;
  File? _lastFile;
  final GlobalKey<LogFilesSectionState> _filesKey = GlobalKey();

  Mode22Scanner? _scanner;
  ScanProgress? _scan;
  int _rangeStart = 0x1100;

  static const List<int> _ranges = [0x1100, 0x1200, 0x1300, 0x1500, 0x0000];

  bool get _recording => _recorder?.isRunning ?? false;
  bool get _scanning => _scanner != null;

  Future<void> _startRecording() async {
    final connection = ref.read(connectionProvider);
    if (connection == null || _starting || _scanning) return;
    setState(() {
      _starting = true;
      _message = 'Revisando qué datos responde tu computadora…';
    });
    try {
      final IdleRecorder recorder = IdleRecorder(connection.obd);
      final List<String> dropped = await recorder.probe();
      final CsvLogWriter writer = await CsvLogWriter.create(recorder.channels);
      _sub = recorder.samples.listen(_onSample);
      recorder.start();
      if (!mounted) return;
      setState(() {
        _recorder = recorder;
        _writer = writer;
        _events.clear();
        _message = dropped.isEmpty
            ? 'Grabando en ${path.basename(writer.file.path)}'
            : 'Grabando. No disponibles en tu carro: ${dropped.join(', ')}';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'No se pudo iniciar: $error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onSample(RecorderSample s) {
    final CsvLogWriter? writer = _writer;
    if (writer != null) unawaited(writer.add(s));
    if (!mounted) return;
    setState(() {
      _last = s;
      for (final String e in s.events) {
        _events.insert(0, '${clockStamp(s.at).substring(0, 8)}  $e');
      }
    });
  }

  Future<void> _stopRecording() async {
    final IdleRecorder? recorder = _recorder;
    final CsvLogWriter? writer = _writer;
    if (recorder == null) return;
    await recorder.dispose();
    await _sub?.cancel();
    await writer?.close();
    if (!mounted) return;
    setState(() {
      _recorder = null;
      _writer = null;
      _lastFile = writer?.file;
      _message = writer == null
          ? 'Grabación detenida.'
          : 'Guardado: ${writer.file.path} (${writer.rows} filas)';
    });
    await _filesKey.currentState?.refresh();
  }

  void _mark(String label) {
    _recorder?.mark(label);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Marca: $label'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _startScan() async {
    final connection = ref.read(connectionProvider);
    if (connection == null || _recording || _scanning) return;
    final Mode22Scanner scanner = Mode22Scanner(connection.obd);
    setState(() {
      _scanner = scanner;
      _scan = null;
    });
    final int from = _rangeStart, to = _rangeStart + 0xFF;
    try {
      await for (final ScanProgress p in scanner.scan(from, to)) {
        if (mounted) setState(() => _scan = p);
      }
      final List<Mode22Hit> hits = _scan?.hits ?? const [];
      final Directory dir = await logsDirectory();
      final File file = File(path.join(
        dir.path,
        'modo22_${_hex(from)}-${_hex(to)}_${fileStamp(DateTime.now())}.csv',
      ));
      await file.writeAsString(mode22HitsCsv(hits));
      if (mounted) {
        setState(() {
          _message = '${hits.length} respuestas. Guardado: ${file.path}';
          _lastFile = file;
        });
        await _filesKey.currentState?.refresh();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Error en el escaneo: $error');
    } finally {
      if (mounted) setState(() => _scanner = null);
    }
  }

  String _hex(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();

  @override
  void dispose() {
    final IdleRecorder? recorder = _recorder;
    final CsvLogWriter? writer = _writer;
    _scanner?.cancel();
    unawaited(() async {
      await recorder?.dispose();
      await _sub?.cancel();
      await writer?.close();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(connectionProvider) == null) {
      return const Center(child: Text('Conecta un adaptador para diagnosticar.'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico de ralentí')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(sample: _last, recording: _recording),
          const SizedBox(height: 12),
          _recordControls(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText(_message ?? ''),
            ),
          if (!_recording && _lastFile != null)
            FilledButton.icon(
              onPressed: () => shareLog(_lastFile!),
              icon: const Icon(Icons.share),
              label: const Text('Compartir este registro'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          if (_last != null) _ValuesGrid(sample: _last!, channels: _recorder?.channels ?? const []),
          if (_events.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Eventos', style: Theme.of(context).textTheme.titleLarge),
            for (final String e in _events.take(30)) Text(e),
          ],
          const Divider(height: 40),
          LogFilesSection(key: _filesKey),
          const Divider(height: 40),
          _scanSection(context),
        ],
      ),
    );
  }

  Widget _recordControls() {
    if (!_recording) {
      return FilledButton.icon(
        onPressed: _starting || _scanning ? null : _startRecording,
        icon: const Icon(Icons.fiber_manual_record),
        label: Text(_starting ? 'Preparando…' : 'Empezar a grabar'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => _mark('SE ACELERÓ'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  minimumSize: const Size.fromHeight(72),
                ),
                child: const Text('SE ACELERÓ', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _mark('SE COMPUSO'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size.fromHeight(72),
                ),
                child: const Text('SE COMPUSO', style: TextStyle(fontSize: 20)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final String label in const ['Volante', 'Pedal', 'Aire A/C', 'Apagué y prendí'])
              OutlinedButton(onPressed: () => _mark(label), child: Text(label)),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _stopRecording,
          icon: const Icon(Icons.stop),
          label: Text('Detener (${_writer?.rows ?? 0} filas)'),
        ),
      ],
    );
  }

  Widget _scanSection(BuildContext context) {
    final ScanProgress? p = _scan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Buscar parámetros ocultos (modo 22)',
            style: Theme.of(context).textTheme.titleLarge),
        const Text('Solo lectura. Prueba 256 identificadores; tarda unos minutos. '
            'Hazlo con el motor encendido y sin grabar.'),
        const SizedBox(height: 8),
        Row(
          children: [
            DropdownButton<int>(
              value: _rangeStart,
              onChanged: _scanning ? null : (v) => setState(() => _rangeStart = v ?? 0x1100),
              items: [
                for (final int r in _ranges)
                  DropdownMenuItem(value: r, child: Text('22${_hex(r)}–22${_hex(r + 0xFF)}')),
              ],
            ),
            const SizedBox(width: 12),
            _scanning
                ? OutlinedButton(onPressed: () => _scanner?.cancel(), child: const Text('Cancelar'))
                : FilledButton(
                    onPressed: _recording ? null : _startScan,
                    child: const Text('Escanear'),
                  ),
          ],
        ),
        if (p != null) ...[
          LinearProgressIndicator(value: p.done / p.total),
          Text('22${_hex(p.current)} · ${p.done}/${p.total} · ${p.hits.length} respuestas'),
          for (final Mode22Hit h in p.hits)
            Text('22${h.idHex} → ${h.dataHex}', style: const TextStyle(fontFamily: 'monospace')),
        ],
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sample, required this.recording});
  final RecorderSample? sample;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final RecorderSample? s = sample;
    final double? rpm = s?['rpm'], desired = s?[gmDesiredIdle.key];
    final double? iac = s?[gmIacPosition.key];
    final double? relThrottle = s?['mariposa_relativa_pct'];
    final bool high = s?.highIdle ?? false;
    final String headline = s == null
        ? (recording ? 'Leyendo…' : 'Sin datos todavía')
        : high
        ? 'RALENTÍ ALTO'
        : 'Normal';
    return Card(
      color: high ? Colors.red.shade900 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('RPM real: ${rpm?.round() ?? '—'}   ·   Pide la computadora: ${desired?.round() ?? '—'}',
                style: const TextStyle(fontSize: 20)),
            Text('Diferencia: ${rpm != null && desired != null ? (rpm - desired).round() : '—'} rpm   ·   IAC: ${iac?.round() ?? '—'} pasos',
                style: const TextStyle(fontSize: 20)),
            Text(
              'Mariposa relativa: ${relThrottle?.toStringAsFixed(1) ?? '—'} %'
              '${relThrottle != null && relThrottle > 1 ? '  ⚠ la computadora cree que estás acelerando' : ''}',
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValuesGrid extends StatelessWidget {
  const _ValuesGrid({required this.sample, required this.channels});
  final RecorderSample sample;
  final List<RecorderChannel> channels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 4,
    children: [
      for (final RecorderChannel c in channels)
        SizedBox(
          width: 170,
          child: Text(
            '${c.nameEs}: ${sample[c.key]?.toStringAsFixed(c.key == 'rpm' ? 0 : 1) ?? '—'} ${c.unit}',
          ),
        ),
    ],
  );
}
