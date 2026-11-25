import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:aveo_scanner/ui/backup_screen.dart';
import 'package:aveo_scanner/ui/connect_screen.dart';
import 'package:aveo_scanner/ui/dashboard_screen.dart';
import 'package:aveo_scanner/ui/diagnostic_screen.dart';
import 'package:aveo_scanner/ui/dtc_screen.dart';
import 'package:aveo_scanner/ui/providers.dart';
import 'package:aveo_scanner/ui/terminal_screen.dart';
import 'package:aveo_scanner/ui/theme.dart';
import 'package:aveo_scanner/ui/log_files_section.dart';

class AveoApp extends StatelessWidget {
  const AveoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Aveo Scanner',
    theme: buildAppTheme(),
    home: const AppShell(),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selected = 0;
  final GlobalKey _diagnosticKey = GlobalKey();
  bool? _lastConnected;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Conectar'),
    NavigationDestination(icon: Icon(Icons.dashboard), label: 'Tablero'),
    NavigationDestination(icon: Icon(Icons.troubleshoot), label: 'Diagnóstico'),
    NavigationDestination(icon: Icon(Icons.warning_amber), label: 'Fallas'),
    NavigationDestination(icon: Icon(Icons.backup), label: 'Respaldo'),
    NavigationDestination(icon: Icon(Icons.terminal), label: 'Terminal'),
    NavigationDestination(icon: Icon(Icons.folder_open), label: 'Registros'),
  ];

  Widget _page(int index) => switch (index) {
    0 => const ConnectScreen(),
    1 => const DashboardScreen(),
    2 => const DiagnosticScreen(),
    3 => const DtcScreen(),
    4 => const BackupScreen(),
    5 => const TerminalScreen(),
    _ => Scaffold(
      appBar: AppBar(title: const Text('Mis registros')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: LogFilesSection(standalone: true),
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final bool connected = ref.watch(connectionProvider) != null;
    if (_lastConnected != connected) {
      _lastConnected = connected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (connected) {
          unawaited(_setWakelock(true));
        } else {
          unawaited(_setWakelock(false));
          if (mounted && _selected != 0 && _selected != 6) {
            setState(() => _selected = 0);
          }
        }
      });
    }
    if (_selected > 0 && _selected != 6 && !connected) _selected = 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool landscape = constraints.maxWidth > constraints.maxHeight;
        final busy = ref.watch(acquisitionProvider);
        final Widget page = Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: _selected != 2,
              child: connected
                  ? DiagnosticScreen(key: _diagnosticKey)
                  : const SizedBox.shrink(),
            ),
            if (_selected != 2)
              Positioned.fill(
                child: busy != null && _selected != 6
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '$busy. Sigue trabajando en Diagnóstico. '
                            'Las otras consultas están en pausa para conservar la frecuencia de lectura.',
                          ),
                        ),
                      )
                    : _page(_selected),
              ),
          ],
        );
        if (landscape) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selected,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) {
                    if (index == 0 || index == 6 || connected) {
                      setState(() => _selected = index);
                    }
                  },
                  destinations: [
                    for (var i = 0; i < _destinations.length; i++)
                      NavigationRailDestination(
                        icon: _destinations[i].icon,
                        label: Text(_destinations[i].label),
                        disabled: i > 0 && i != 6 && !connected,
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          );
        }
        return Scaffold(
          body: page,
          bottomNavigationBar: NavigationBar(
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            selectedIndex: _selected,
            onDestinationSelected: (index) {
              if (index == 0 || index == 6 || connected) {
                setState(() => _selected = index);
              }
            },
            destinations: [
              for (var i = 0; i < _destinations.length; i++)
                NavigationDestination(
                  icon: _destinations[i].icon,
                  label: _destinations[i].label,
                  enabled: i == 0 || i == 6 || connected,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on Object {
      // The desktop simulator and widget tests do not expose the Android plugin.
    }
  }
}
