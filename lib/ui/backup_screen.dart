import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveo_scanner/obd/dtc.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';
import 'package:aveo_scanner/ui/providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  List<Map<String, Object?>> _backups = [];
  bool _busy = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  void _setProgress(String value) {
    if (mounted) setState(() => _progress = value);
  }

  Future<void> _load() async {
    try {
      final backups = await ref.read(backupRepositoryProvider).list();
      if (mounted) setState(() => _backups = backups);
    } on Object catch (error) {
      if (mounted) _showMessage('No se pudieron cargar los respaldos: $error');
    }
  }

  Future<void> _createBackup() async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    setState(() {
      _busy = true;
      _progress = 'Leyendo identificación del adaptador…';
    });
    final data = <String, Object?>{
      'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'transport': connection.transport.label,
      'protocol': connection.info.protocolName,
      'version': connection.info.version,
      'voltage': connection.info.voltage,
      'initializationRaw': connection.info.supportedPids
          .map((message) => message.data)
          .toList(),
    };
    try {
      final identification = <String, String>{};
      for (final command in ['ATI', 'ATDPN', 'ATRV']) {
        final response = await connection.elm.send(command);
        identification[command] = response.raw;
      }
      if (!mounted) return;
      data['identificationRaw'] = identification;
      _setProgress('Leyendo VIN, calibración y CVN…');
      final vehicle = await connection.obd.readVehicleInfo();
      data['vehicle'] = {
        'vin': vehicle.vin,
        'calid': vehicle.calid,
        'cvn': vehicle.cvn,
      };
      final vehicleRaw = <String, String>{};
      for (final command in ['0902', '0904', '0906']) {
        vehicleRaw[command] = (await connection.elm.send(command)).raw;
      }
      data['vehicleRaw'] = vehicleRaw;
      _setProgress('Consultando PIDs soportados…');
      final supported = await connection.obd.readSupportedPids();
      data['supportedPids'] = supported.pids.toList()..sort();
      final supportedRaw = <String, String>{};
      for (final base in [0, 32, 64, 96, 128, 160, 192, 224]) {
        final command = '01${base.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
        supportedRaw[command] = (await connection.elm.send(command)).raw;
      }
      data['supportedPidsRaw'] = supportedRaw;
      final dtcs = <String, Object?>{};
      final dtcRaw = <String, String>{};
      for (final kind in DtcKind.values) {
        _setProgress('Leyendo fallas ${_kindName(kind)}…');
        final codes = await connection.obd.readDtcs(kind);
        dtcs[kind.name] = [
          for (final code in codes)
            {
              'code': code.code,
              'description': code.descriptionEs,
              'ecu': code.ecu,
            },
        ];
        final mode = switch (kind) {
          DtcKind.confirmed => '03',
          DtcKind.pending => '07',
          DtcKind.permanent => '0A',
        };
        dtcRaw[mode] = (await connection.elm.send(mode)).raw;
      }
      data['dtcs'] = dtcs;
      data['dtcRaw'] = dtcRaw;
      _setProgress('Leyendo freeze frame…');
      final frame = await connection.obd.readFreezeFrame();
      final freezeRaw = <String, String>{};
      final freezeCommands = <String>[
        '0202',
        '0200',
        for (final pid in frame.values.keys)
          '02${pid.toRadixString(16).padLeft(2, '0')}00'.toUpperCase(),
      ];
      for (final command in freezeCommands) {
        freezeRaw[command] = (await connection.elm.send(command)).raw;
      }
      data['freezeFrame'] = {
        'dtcs': [for (final dtc in frame.dtcs) dtc.code],
        'values': frame.values.map(
          (pid, value) => MapEntry(pid.toString(), value),
        ),
        'raw': freezeRaw,
      };
      _setProgress('Leyendo valores base…');
      final pidList = supported.pids.where(standardPids.containsKey).toList()
        ..sort();
      final pids = await connection.obd.readPids(pidList);
      final raw = <String, String>{};
      for (final pid in pidList) {
        final command = '01${pid.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
        raw[pid.toString()] = (await connection.elm.send(command)).raw;
      }
      data['readings'] = {
        for (final entry in pids.entries)
          entry.key.toString(): {
            'value': entry.value.value,
            'at': entry.value.at.toUtc().millisecondsSinceEpoch,
            'raw': raw[entry.key.toString()],
          },
      };
      await ref.read(backupRepositoryProvider).save('initial', data);
      if (!mounted) return;
      await _load();
    } on Object catch (error) {
      if (mounted) _showMessage('El respaldo no se completó: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  String _kindName(DtcKind kind) => switch (kind) {
    DtcKind.confirmed => 'confirmadas',
    DtcKind.pending => 'pendientes',
    DtcKind.permanent => 'permanentes',
  };

  Future<void> _showDetail(int id) async {
    final item = await ref.read(backupRepositoryProvider).get(id);
    if (!mounted || item == null) return;
    final Object? rawPayload = item['payload'];
    if (rawPayload is! String) {
      _showMessage('El contenido del respaldo no es válido.');
      return;
    }
    final Object? payload = jsonDecode(rawPayload);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle del respaldo'),
        content: SingleChildScrollView(
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(payload),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(int id) async {
    try {
      final location = await ref.read(backupRepositoryProvider).exportJson(id);
      if (!mounted) return;
      _showMessage('Respaldo exportado: $location');
    } on Object catch (error) {
      if (mounted) _showMessage('No se pudo exportar: $error');
    }
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Respaldo')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _createBackup,
          icon: const Icon(Icons.save),
          label: const Text('Hacer respaldo inicial'),
        ),
        if (_busy) ...[
          const LinearProgressIndicator(),
          Padding(padding: const EdgeInsets.all(12), child: Text(_progress)),
        ],
        const SizedBox(height: 16),
        for (final item in _backups) _backupTile(item),
      ],
    ),
  );

  Widget _backupTile(Map<String, Object?> item) {
    final Object? idValue = item['id'];
    final Object? createdValue = item['created_at'];
    if (idValue is! int || createdValue is! int) return const SizedBox.shrink();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      createdValue,
      isUtc: true,
    ).toLocal();
    return Card(
      child: ListTile(
        title: Text('${item['kind']} · $createdAt'),
        onTap: () => _showDetail(idValue),
        trailing: IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Exportar',
          onPressed: () => _export(idValue),
        ),
      ),
    );
  }
}
