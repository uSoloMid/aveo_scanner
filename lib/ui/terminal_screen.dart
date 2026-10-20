import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveo_scanner/core/elm327/traffic_log.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/ui/providers.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<List<TrafficEntry>>? _subscription;
  List<TrafficEntry> _entries = const [];
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final oldSubscription = _subscription;
    if (oldSubscription != null) unawaited(oldSubscription.cancel());
    final log = ref.read(trafficLogProvider);
    _entries = log.entries;
    _subscription = log.changes.listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  Future<void> _send() async {
    final String command = _controller.text;
    try {
      final response = await ref.read(terminalSenderProvider)(command);
      if (!mounted) return;
      setState(
        () => _message =
            response.error?.name ?? response.text ?? 'Respuesta recibida.',
      );
      _controller.clear();
    } on CommandBlockedException catch (error) {
      if (mounted) setState(() => _message = error.result.reason);
    } on ConfirmationRequiredException {
      if (mounted) {
        setState(() => _message = 'Para esta acción, usa la pantalla Fallas.');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'No se pudo enviar: $error');
    }
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Terminal')),
    body: Column(
      children: [
        if (_message != null) ListTile(title: Text(_message ?? '')),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final color = switch (entry.dir) {
                Direction.tx => Colors.lightBlueAccent,
                Direction.rx => Colors.greenAccent,
                Direction.guard => Colors.orangeAccent,
              };
              return ListTile(
                dense: true,
                title: Text(
                  '${entry.dir.name.toUpperCase()}  ${entry.text}',
                  style: TextStyle(color: color, fontFamily: 'monospace'),
                ),
                subtitle: Text(entry.at.toLocal().toString()),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Comando AT u OBD de lectura',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  tooltip: 'Enviar',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
