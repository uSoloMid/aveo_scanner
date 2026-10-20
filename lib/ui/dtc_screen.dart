import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveo_scanner/obd/dtc.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/ui/providers.dart';

class DtcScreen extends ConsumerStatefulWidget {
  const DtcScreen({super.key});
  @override
  ConsumerState<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends ConsumerState<DtcScreen> {
  final Map<DtcKind, List<Dtc>> codes = {};
  FreezeFrame? freeze;
  String status = '';
  bool busy = false;
  Future<void> read(DtcKind kind) async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    setState(() {
      busy = true;
      status = 'Leyendo ${_name(kind).toLowerCase()}…';
    });
    try {
      final result = await connection.obd.readDtcs(kind);
      if (!mounted) return;
      setState(() {
        codes[kind] = result;
        status = 'Lectura terminada';
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() => status = 'No se pudieron leer las fallas: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> readFreeze() async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    try {
      final value = await connection.obd.readFreezeFrame();
      if (!mounted) return;
      setState(() => freeze = value);
    } on Object catch (e) {
      if (mounted) {
        setState(() => status = 'No se pudo leer el freeze frame: $e');
      }
    }
  }

  Future<void> clear() async {
    final connection = ref.read(connectionProvider);
    if (connection == null) return;
    setState(() => busy = true);
    try {
      final rpm = await connection.obd.readPids([12]);
      if (!mounted) return;
      final value = rpm[12];
      if (value == null) {
        throw StateError(
          'No se pudo confirmar que el motor esté apagado; no se borraron los códigos.',
        );
      }
      if (value.value > 0) {
        throw StateError(
          'Apaga el motor (deja solo el contacto) antes de borrar códigos.',
        );
      }
      setState(() => status = 'Guardando respaldo automático antes de borrar…');
      final backupCodes = <String, Object?>{};
      for (final kind in DtcKind.values) {
        final items = await connection.obd.readDtcs(kind);
        if (!mounted) return;
        backupCodes[kind.name] = [
          for (final item in items)
            {
              'code': item.code,
              'description': item.descriptionEs,
              'ecu': item.ecu,
            },
        ];
      }
      final frame = await connection.obd.readFreezeFrame();
      if (!mounted) return;
      final vehicle = await connection.obd.readVehicleInfo();
      if (!mounted) return;
      await ref.read(backupRepositoryProvider).save('pre_clear', {
        'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        'confirmed': backupCodes['confirmed'],
        'pending': backupCodes['pending'],
        'permanent': backupCodes['permanent'],
        'freezeFrame': [
          for (final item in frame.dtcs) {'code': item.code, 'ecu': item.ecu},
        ],
        'freezeFrameValues': {
          for (final entry in frame.values.entries)
            entry.key.toString(): entry.value,
        },
        'vin': vehicle.vin,
      });
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Antes de borrar'),
          content: const Text(
            'El borrado reinicia los monitores de emisiones. La verificación puede fallar hasta completar varios ciclos de manejo. El respaldo previo ya está guardado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final typed = await showDialog<bool>(
        context: context,
        builder: (context) => const _TypeDeleteDialog(),
      );
      if (!mounted || typed != true) return;
      await connection.obd.clearDtcs(Confirmation.userApproved('04'));
      if (!mounted) return;
      await read(DtcKind.confirmed);
      if (!mounted) return;
      setState(
        () => status = 'Borrado confirmado. Se volvió a leer la sección 03.',
      );
    } on Object catch (e) {
      if (mounted) setState(() => status = 'No se borraron los códigos: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _name(DtcKind kind) => switch (kind) {
    DtcKind.confirmed => 'Confirmadas · modo 03',
    DtcKind.pending => 'Pendientes · modo 07',
    DtcKind.permanent => 'Permanentes · modo 0A',
  };
  String _typeName(DtcKind kind) => switch (kind) {
    DtcKind.confirmed => 'Confirmada',
    DtcKind.pending => 'Pendiente',
    DtcKind.permanent => 'Permanente',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fallas')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final kind in DtcKind.values) _section(context, kind),
        OutlinedButton.icon(
          onPressed: busy ? null : readFreeze,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Leer freeze frame'),
        ),
        if (freeze != null) _freezeTile(freeze),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : clear,
          icon: const Icon(Icons.delete_sweep),
          label: const Text('Borrar códigos'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (status.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(status)),
      ],
    ),
  );

  Widget _section(BuildContext context, DtcKind kind) {
    final List<Dtc>? items = codes[kind];
    return Card(
      child: ExpansionTile(
        title: Text(_name(kind)),
        trailing: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Leer'),
          onPressed: busy ? null : () => read(kind),
        ),
        children: [
          for (final dtc in items ?? const <Dtc>[])
            ListTile(
              title: Text(
                dtc.code,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              subtitle: Text(
                '${dtc.descriptionEs ?? 'Sin descripción, búscalo como código genérico.'}\nTipo: ${_typeName(kind)} · ECU ${dtc.ecu}',
              ),
            ),
          if (items != null && items.isEmpty)
            const ListTile(title: Text('No hay códigos reportados.')),
        ],
      ),
    );
  }

  Widget _freezeTile(FreezeFrame? value) {
    if (value == null) return const SizedBox.shrink();
    final String codes = value.dtcs.map((dtc) => dtc.code).join(', ');
    return Card(
      child: ListTile(
        title: const Text('Freeze frame'),
        subtitle: Text(
          'DTC: ${codes.isEmpty ? 'Sin código' : codes} · ${value.values.length} valores',
        ),
      ),
    );
  }
}

class _TypeDeleteDialog extends StatefulWidget {
  const _TypeDeleteDialog();
  @override
  State<_TypeDeleteDialog> createState() => _TypeDeleteDialogState();
}

class _TypeDeleteDialogState extends State<_TypeDeleteDialog> {
  final TextEditingController controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirmación final'),
    content: TextField(
      controller: controller,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Escribe BORRAR'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: controller.text == 'BORRAR'
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Borrar'),
      ),
    ],
  );
}
