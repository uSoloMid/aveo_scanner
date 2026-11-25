import 'package:aveo_scanner/obd/idle_recorder.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';

List<RecorderChannel> recorderCatalog() {
  final defaults = defaultRecorderChannels();
  return [
    ...defaults,
    for (final pid in standardPids.values)
      if (!const {
        3,
        4,
        5,
        6,
        7,
        11,
        12,
        13,
        14,
        15,
        17,
        20,
        21,
        66,
        69,
      }.contains(pid.pid))
        RecorderChannel.pid(
          pid.pid,
          'pid_${pid.pid.toRadixString(16).padLeft(2, '0')}',
          pid.nameEs,
          pid.unit,
          optional: true,
        ),
  ];
}

final class RecorderProfile {
  RecorderProfile({
    required this.name,
    required Map<String, bool> priorities,
    this.dtcMinutes = 0,
  }) : priorities = Map.unmodifiable(priorities);

  final String name;
  final Map<String, bool> priorities;
  final int dtcMinutes;

  static RecorderProfile get idle => RecorderProfile(
    name: 'Ralentí completo',
    priorities: {for (final c in defaultRecorderChannels()) c.key: c.fast},
    dtcMinutes: 3,
  );

  static final tps = RecorderProfile(
    name: 'TPS rápido',
    priorities: const {'mariposa_pct': true, 'rpm': true},
  );

  static final comparison = RecorderProfile(
    name: 'TPS absoluto y relativo',
    priorities: const {
      'mariposa_pct': true,
      'mariposa_relativa_pct': true,
      'rpm': true,
      'velocidad_kmh': false,
    },
  );

  factory RecorderProfile.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String).trim();
    final dtcMinutes = json['dtcMinutes'] as int;
    final supported = recorderCatalog().map((c) => c.key).toSet();
    final priorities = {
      for (final entry in (json['priorities'] as Map<String, dynamic>).entries)
        if (supported.contains(entry.key)) entry.key: entry.value as bool,
    };
    if (name.isEmpty ||
        priorities.isEmpty ||
        !const [0, 1, 3, 5].contains(dtcMinutes)) {
      throw const FormatException('Perfil inválido');
    }
    return RecorderProfile(
      name: name,
      priorities: priorities,
      dtcMinutes: dtcMinutes,
    );
  }

  Map<String, Object> toJson() => {
    'name': name,
    'priorities': priorities,
    'dtcMinutes': dtcMinutes,
  };

  List<RecorderChannel> channels() {
    final catalog = {
      for (final channel in recorderCatalog()) channel.key: channel,
    };
    final ordered = {'mariposa_pct', 'mariposa_relativa_pct', ...catalog.keys};
    return [
      for (final key in ordered)
        if (priorities.containsKey(key))
          catalog[key]!.withPriority(priorities[key]!),
    ];
  }
}
