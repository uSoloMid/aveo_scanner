import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:aveo_scanner/core/transport/bt_classic_transport.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:aveo_scanner/ui/providers.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool busy = false;
  String progress = '';
  String? error;
  Future<void> connect(Transport transport) async {
    setState(() {
      busy = true;
      error = null;
      progress = 'Conectando al adaptador…';
    });
    try {
      setState(() => progress = 'Inicializando ELM327 y detectando protocolo…');
      final connection = await ref
          .read(connectionProvider.notifier)
          .connect(transport);
      if (!mounted) return;
      setState(() {
        busy = false;
        progress = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${connection.info.version} · ${connection.info.protocolName} · ${connection.info.voltage.toStringAsFixed(1)} V',
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        progress = '';
        error = _spanishError(e);
      });
    }
  }

  String _spanishError(Object e) {
    final String message = e.toString();
    if (message.contains('contacto')) {
      return 'No hubo respuesta del vehículo. Enciende el contacto y vuelve a intentar.';
    }
    if (message.contains('NO_PERMISSION')) {
      return 'Falta permiso de Bluetooth. En Ajustes > Apps > Aveo Scanner > Permisos, permite "Dispositivos cercanos". Detalle: $message';
    }
    if (message.contains('CONNECT_FAILED')) {
      return 'No se pudo conectar. Verifica que el ELM327 esté emparejado y libre.';
    }
    return 'Falló la conexión: $message. Revisa el contacto, Bluetooth y el adaptador.';
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);
    final devices = ref.watch(bondedDevicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aveo Scanner'),
        actions: [
          if (connection != null)
            IconButton(
              onPressed: () async {
                await ref.read(connectionProvider.notifier).disconnect();
              },
              icon: const Icon(Icons.link_off),
              tooltip: 'Desconectar',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            connection == null ? 'Conecta tu adaptador' : 'Conectado',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science),
              title: const Text('Simulador (sin carro)'),
              subtitle: const Text('Datos de demostración'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () => connect(ref.read(mockTransportProvider)()),
            ),
          ),
          devices.when(
            data: (listing) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (listing.error != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(listing.error ?? 'Error de Bluetooth.'),
                      subtitle: listing.needsSettings
                          ? const Text(
                              'Abre los ajustes de la aplicación y permite Bluetooth.',
                            )
                          : null,
                      trailing: listing.needsSettings
                          ? TextButton(
                              onPressed: openAppSettings,
                              child: const Text('Ajustes'),
                            )
                          : null,
                    ),
                  ),
                for (final device in listing.devices)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(device.name ?? 'ELM327'),
                      subtitle: Text(device.address),
                      onTap: busy
                          ? null
                          : () => connect(BtClassicTransport(device.address)),
                    ),
                  ),
              ],
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => Text('No se pudo consultar Bluetooth: $e'),
          ),
          if (busy)
            Card(
              child: ListTile(
                leading: const CircularProgressIndicator(),
                title: Text(progress),
              ),
            ),
          if (error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error ?? 'Error de conexión.'),
              ),
            ),
          if (connection != null)
            Card(
              child: ListTile(
                title: Text(connection.info.version),
                subtitle: Text(
                  'Protocolo ${connection.info.protocolName} · ${connection.info.voltage.toStringAsFixed(1)} V',
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => ref.invalidate(bondedDevicesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar dispositivos'),
          ),
        ],
      ),
    );
  }
}
