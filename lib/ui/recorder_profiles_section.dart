import 'dart:convert';
import 'dart:io';

import 'package:aveo_scanner/obd/recorder_profile.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RecorderProfilesSection extends StatefulWidget {
  const RecorderProfilesSection({
    super.key,
    required this.profile,
    required this.onSelected,
    required this.enabled,
  });

  final RecorderProfile profile;
  final ValueChanged<RecorderProfile> onSelected;
  final bool enabled;

  @override
  State<RecorderProfilesSection> createState() =>
      _RecorderProfilesSectionState();
}

class _RecorderProfilesSectionState extends State<RecorderProfilesSection> {
  static final _presets = [
    RecorderProfile.idle,
    RecorderProfile.tps,
    RecorderProfile.comparison,
  ];
  final _saved = <RecorderProfile>[];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<File> _file() async => File(
    path.join(
      (await getApplicationSupportDirectory()).path,
      'recorder_profiles_v1.json',
    ),
  );

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      final loaded = list
          .map(
            (entry) => RecorderProfile.fromJson(entry as Map<String, dynamic>),
          )
          .toList();
      if (mounted) _saved.addAll(loaded);
    } on Object {
      _error = 'No se pudieron cargar los perfiles guardados.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final existing = _saved.any(
      (profile) => profile.name == widget.profile.name,
    );
    final profile = await showDialog<RecorderProfile>(
      context: context,
      builder: (_) =>
          _ProfileEditor(profile: widget.profile, existing: existing),
    );
    if (!mounted || profile == null) return;
    if (_presets.any((preset) => preset.name == profile.name) ||
        (profile.name != widget.profile.name &&
            _saved.any((saved) => saved.name == profile.name))) {
      setState(() => _error = 'Ya existe un perfil con ese nombre.');
      return;
    }
    await _save([
      ..._saved.where((saved) => saved.name != profile.name),
      profile,
    ], profile);
  }

  Future<void> _save(
    List<RecorderProfile> profiles,
    RecorderProfile selected,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
        flush: true,
      );
      await temp.rename(file.path);
      if (!mounted) return;
      _saved
        ..clear()
        ..addAll(profiles);
      widget.onSelected(selected);
    } on Object {
      _error = 'No se pudieron guardar los perfiles.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = [..._presets, ..._saved];
    final editable = widget.enabled && !_busy;
    final custom = _saved.any((profile) => profile.name == widget.profile.name);
    final selected =
        profiles.any((profile) => profile.name == widget.profile.name)
        ? widget.profile.name
        : _presets.first.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(selected),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Perfil de grabación'),
          items: [
            for (final profile in profiles)
              DropdownMenuItem(value: profile.name, child: Text(profile.name)),
          ],
          onChanged: editable
              ? (name) => widget.onSelected(
                  profiles.firstWhere((p) => p.name == name),
                )
              : null,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: editable ? _edit : null,
              child: const Text('Configurar perfil'),
            ),
            if (custom)
              TextButton(
                onPressed: editable
                    ? () => _save(
                        _saved
                            .where((p) => p.name != widget.profile.name)
                            .toList(),
                        _presets.first,
                      )
                    : null,
                child: const Text('Quitar perfil'),
              ),
          ],
        ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.profile, required this.existing});
  final RecorderProfile profile;
  final bool existing;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(
    text: widget.existing ? widget.profile.name : '',
  );
  late final _signals = Map<String, bool>.of(widget.profile.priorities);
  late int _dtc = widget.profile.dtcMinutes;
  final _catalog = recorderCatalog();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurar perfil'),
    content: SizedBox(
      width: 480,
      child: ListView(
        shrinkWrap: true,
        children: [
          TextField(
            controller: _name,
            maxLength: 48,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nombre del perfil'),
          ),
          DropdownButtonFormField<int>(
            initialValue: _dtc,
            decoration: const InputDecoration(
              labelText: 'Consultar códigos DTC',
            ),
            items: [
              for (final minutes in [0, 1, 3, 5])
                DropdownMenuItem(
                  value: minutes,
                  child: Text(
                    minutes == 0 ? 'Desactivado' : 'Cada $minutes min',
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _dtc = value!),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Lee las señales prioritarias en cada ciclo. Más señales prioritarias reducen la frecuencia de cada una.',
            ),
          ),
          for (final signal in _catalog)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(signal.nameEs),
              value: _signals.containsKey(signal.key),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _signals[signal.key] = false;
                } else {
                  _signals.remove(signal.key);
                }
              }),
              subtitle: _signals.containsKey(signal.key)
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Prioritaria'),
                        selected: _signals[signal.key]!,
                        onSelected: (priority) =>
                            setState(() => _signals[signal.key] = priority),
                      ),
                    )
                  : null,
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _signals.isEmpty || _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                RecorderProfile(
                  name: _name.text.trim(),
                  priorities: _signals,
                  dtcMinutes: _dtc,
                ),
              ),
        child: const Text('Guardar perfil'),
      ),
    ],
  );
}
