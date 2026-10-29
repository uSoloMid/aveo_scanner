import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveo_scanner/obd/pid.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';
import 'package:aveo_scanner/ui/providers.dart';

import 'widgets/gauge_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const List<int> _mainPids = [12, 13, 5, 66];
  final Map<int, PidValue> _values = {};
  final List<PidValue> _pendingReadings = [];
  Timer? _pollTimer;
  Timer? _saveTimer;
  Set<int> _supported = {};
  int _otherIndex = 0;
  int? _sessionId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_loadSupported()),
    );
  }

  Future<void> _loadSupported() async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    try {
      final supported = await connection.obd.readSupportedPids();
      if (!mounted) return;
      setState(() => _supported = supported.pids);
    } on Object {
      // Poll the four essential values even if the adapter omits support masks.
    }
    if (mounted) _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_poll()),
    );
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_flushReadings()),
    );
    _poll();
  }

  Future<void> _poll() async {
    final connection = ref.read(connectionProvider);
    if (connection == null || _busy) return;
    _busy = true;
    try {
      final extras =
          _supported
              .where(
                (pid) =>
                    standardPids.containsKey(pid) && !_mainPids.contains(pid),
              )
              .toList()
            ..sort();
      final int? other = extras.isEmpty
          ? null
          : extras[_otherIndex++ % extras.length];
      final result = await connection.obd.readPids([
        12,
        13,
        5,
        if (_supported.contains(66)) 66,
        ?other,
      ]);
      if (!mounted) return;
      setState(() => _values.addAll(result));
      _pendingReadings.addAll(result.values);
    } on Object {
      // A transient NO DATA should not stop the next polling cycle.
    } finally {
      _busy = false;
    }
  }

  Future<void> _flushReadings() async {
    final id = _sessionId;
    if (id == null || _pendingReadings.isEmpty) return;
    final values = List<PidValue>.of(_pendingReadings);
    _pendingReadings.clear();
    try {
      await ref.read(sessionRepositoryProvider).addReadings(id, values);
    } on Object {
      _pendingReadings.insertAll(0, values);
    }
  }

  Future<void> _toggleRecording() async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    final repository = ref.read(sessionRepositoryProvider);
    final id = _sessionId;
    if (id == null) {
      try {
        final newId = await repository.start(
          transport: connection.transport.label,
          protocol: connection.info.protocolName,
        );
        if (!mounted) return;
        setState(() => _sessionId = newId);
      } on Object catch (error) {
        if (mounted) _showMessage('No se pudo iniciar la sesión: $error');
      }
      return;
    }
    await _flushReadings();
    try {
      await repository.end(id);
      if (mounted) setState(() => _sessionId = null);
    } on Object catch (error) {
      if (mounted) _showMessage('No se pudo cerrar la sesión: $error');
    }
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _tile(int pid, double? value, {bool alert = false}) {
    final definition = standardPids[pid];
    if (definition == null) return const SizedBox.shrink();
    return GaugeTile(definition: definition, value: value, alert: alert);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _saveTimer?.cancel();
    final id = _sessionId;
    if (id != null) {
      final values = List<PidValue>.of(_pendingReadings);
      unawaited(() async {
        final repository = ref.read(sessionRepositoryProvider);
        if (values.isNotEmpty) await repository.addReadings(id, values);
        await repository.end(id);
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);
    if (connection == null) {
      return const Center(child: Text('Conecta un adaptador para ver datos.'));
    }
    final double rpm = _values[12]?.value ?? 0;
    final double? coolant = _values[5]?.value;
    final double voltage = _values[66]?.value ?? connection.info.voltage;
    final bool voltageAlert = rpm > 0 && voltage < 12;
    final double? maf = _values[16]?.value;
    final double lph = maf == null ? 0 : fuelLph(maf);
    final extras =
        _supported
            .where(
              (pid) =>
                  standardPids.containsKey(pid) && !_mainPids.contains(pid),
            )
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Tablero')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final pid in _mainPids)
                _tile(
                  pid,
                  pid == 66 ? voltage : _values[pid]?.value,
                  alert:
                      (pid == 5 && (coolant ?? 0) > 105) ||
                      (pid == 66 && voltageAlert),
                ),
            ],
          ),
          if (maf != null)
            Card(
              child: ListTile(
                title: Text('${lph.toStringAsFixed(2)} L/h'),
                subtitle: Text(
                  'Consumo estimado · ${kmPerL(_values[13]?.value ?? 0, lph)?.toStringAsFixed(1) ?? '—'} km/L',
                ),
              ),
            ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Otros datos', style: Theme.of(context).textTheme.titleLarge),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
              childAspectRatio: 1.3,
              children: [
                for (final pid in extras) _tile(pid, _values[pid]?.value),
              ],
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _toggleRecording,
            icon: Icon(
              _sessionId == null ? Icons.fiber_manual_record : Icons.stop,
            ),
            label: Text(
              _sessionId == null ? 'Grabar sesión' : 'Terminar sesión',
            ),
          ),
        ],
      ),
    );
  }
}
