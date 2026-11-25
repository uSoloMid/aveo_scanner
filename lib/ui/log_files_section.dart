import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:aveo_scanner/data/csv_log_writer.dart';

Future<void> shareLogs(List<File> files) async {
  if (files.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [for (final f in files) XFile(f.path, mimeType: 'text/csv')],
      text: 'Registros Aveo Scanner (${files.length})',
    ),
  );
}

Future<void> shareLog(File file) => shareLogs([file]);

class LogFilesSection extends StatefulWidget {
  const LogFilesSection({super.key, this.directory, this.standalone = false});
  final Directory? directory;
  final bool standalone;
  @override
  State<LogFilesSection> createState() => LogFilesSectionState();
}

class LogFilesSectionState extends State<LogFilesSection> {
  List<File> _files = const [];
  final Set<String> _selected = {};
  final Map<String, int> _sizes = {};
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final files = await listLogs(directory: widget.directory);
      final sizes = <String, int>{};
      for (final f in files) {
        sizes[f.path] = await f.length();
      }
      if (!mounted) return;
      setState(() {
        _files = files;
        _sizes
          ..clear()
          ..addAll(sizes);
        _selected.removeWhere(
          (p) =>
              !files.any((f) => f.path == p) ||
              CsvLogWriter.activePaths.contains(p),
        );
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudieron leer los registros: $e');
      }
    }
  }

  List<File> get _chosen =>
      _files.where((f) => _selected.contains(f.path)).toList();
  Future<void> _share(List<File> files) async {
    try {
      await shareLogs(files);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'No se pudo compartir: $e');
    }
  }

  Future<void> _delete() async {
    final files = _chosen
        .where((f) => !CsvLogWriter.activePaths.contains(f.path))
        .toList();
    if (files.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${files.length} registros?'),
        content: const Text(
          'Se eliminarán del celular. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    final failed = <String>[];
    for (final f in files) {
      if (CsvLogWriter.activePaths.contains(f.path)) continue;
      try {
        await f.delete();
      } on Object {
        failed.add(path.basename(f.path));
      }
    }
    await refresh();
    if (mounted) {
      setState(() {
        _busy = false;
        if (failed.isNotEmpty) {
          _error = 'No se pudieron eliminar: ${failed.join(', ')}';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.standalone
                  ? '${_files.length} registros'
                  : 'Mis registros (${_files.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            onPressed: _busy ? null : refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      if (_files.isNotEmpty)
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      final available = _files.where(
                        (f) => !CsvLogWriter.activePaths.contains(f.path),
                      );
                      if (_selected.length == available.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(available.map((f) => f.path));
                      }
                    }),
              child: const Text('Seleccionar todos / ninguno'),
            ),
            TextButton.icon(
              onPressed: _busy || _selected.isEmpty
                  ? null
                  : () => _share(_chosen),
              icon: const Icon(Icons.share),
              label: Text('Compartir (${_selected.length})'),
            ),
            TextButton.icon(
              onPressed: _busy || _selected.isEmpty ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar seleccionados'),
            ),
          ],
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_files.isEmpty) const Text('Todavía no hay registros.'),
      for (final f in _files)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Checkbox(
            value: _selected.contains(f.path),
            onChanged: _busy || CsvLogWriter.activePaths.contains(f.path)
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(f.path);
                    } else {
                      _selected.remove(f.path);
                    }
                  }),
          ),
          title: Text(path.basename(f.path)),
          subtitle: Text(
            CsvLogWriter.activePaths.contains(f.path)
                ? 'Grabando · archivo protegido'
                : '${((_sizes[f.path] ?? 0) / 1024).toStringAsFixed(1)} KB',
          ),
          trailing: IconButton(
            onPressed: CsvLogWriter.activePaths.contains(f.path)
                ? null
                : () => _share([f]),
            icon: const Icon(Icons.share),
            tooltip: 'Compartir este registro',
          ),
        ),
    ],
  );
}
