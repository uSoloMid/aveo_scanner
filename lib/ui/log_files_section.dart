import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:aveo_scanner/data/csv_log_writer.dart';

/// Opens Android's share sheet (WhatsApp, Gmail, Drive, Claude…) for a log.
Future<void> shareLog(File file) => SharePlus.instance.share(
  ShareParams(
    files: [XFile(file.path, mimeType: 'text/csv')],
    text: 'Registro Aveo Scanner: ${path.basename(file.path)}',
  ),
);

/// Lists saved CSV logs with a share button each. Call [refresh] through a
/// [GlobalKey] after a recording or scan finishes.
class LogFilesSection extends StatefulWidget {
  const LogFilesSection({super.key});

  @override
  State<LogFilesSection> createState() => LogFilesSectionState();
}

class LogFilesSectionState extends State<LogFilesSection> {
  List<File> _files = const [];
  String? _folder;
  String? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final Directory dir = await logsDirectory();
      final List<File> files = await listLogs();
      if (!mounted) return;
      setState(() {
        _folder = dir.path;
        _files = files;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'No se pudo leer la carpeta: $error');
    }
  }

  Future<void> _share(File file) async {
    try {
      await shareLog(file);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'No se pudo compartir: $error');
    }
  }

  String _size(File f) {
    final int bytes = f.lengthSync();
    return bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Mis registros',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      if (_folder != null) Text('Carpeta: $_folder'),
      if (_error != null) Text(_error ?? ''),
      if (_files.isEmpty) const Text('Todavía no hay registros.'),
      for (final File f in _files.take(20))
        Card(
          child: ListTile(
            title: Text(path.basename(f.path)),
            subtitle: Text(_size(f)),
            trailing: FilledButton.icon(
              onPressed: () => _share(f),
              icon: const Icon(Icons.share),
              label: const Text('Compartir'),
            ),
          ),
        ),
    ],
  );
}
