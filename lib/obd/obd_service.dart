import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/obd/dtc.dart';
import 'package:aveo_scanner/obd/pid.dart';
import 'package:aveo_scanner/obd/supported_pids.dart';
import 'package:aveo_scanner/obd/vehicle_info.dart';
import 'package:aveo_scanner/obd/standard_pids.dart';

typedef PreClearBackup = Future<void> Function(Map<String, Object?> payload);

class ObdService {
  ObdService(this.elm, {this.savePreClearBackup});
  final Elm327 elm;
  final PreClearBackup? savePreClearBackup;
  Future<ElmInfo> connectAndInit() => elm.initialize();
  Future<Map<int, PidValue>> readPids(List<int> pids) async {
    final Map<int, PidValue> values = {};
    for (final int pid in pids) {
      final PidDef? def = standardPids[pid];
      if (def == null) {
        continue;
      }
      final ElmResponse r = await elm.send(
        '01${pid.toRadixString(16).padLeft(2, '0')}'.toUpperCase(),
      );
      if (r.messages.isEmpty) {
        continue;
      }
      for (final EcuMessage m in r.messages) {
        final int index = m.data.indexOf(0x41);
        if (index >= 0 && m.data.length >= index + 2 + def.bytes) {
          values[pid] = PidValue(
            pid: pid,
            value: def.decode(m.data.sublist(index + 2, index + 2 + def.bytes)),
            at: DateTime.now(),
          );
          break;
        }
      }
    }
    return values;
  }

  Future<SupportedPids> readSupportedPids() async {
    final Set<int> all = {};
    for (final int base in [0, 32, 64, 96, 128, 160, 192, 224]) {
      final ElmResponse r = await elm.send(
        '01${base.toRadixString(16).padLeft(2, '0')}'.toUpperCase(),
      );
      if (r.messages.isEmpty) {
        break;
      }
      final List<int> data = r.messages.first.data;
      final int ix = data.indexOf(0x41);
      if (ix < 0 || data.length < ix + 6) {
        break;
      }
      final SupportedPids group = SupportedPids.fromMask(
        base,
        data.sublist(ix + 2, ix + 6),
      );
      all.addAll(group.pids);
      if (!group.contains(base + 32)) {
        break;
      }
    }
    return SupportedPids(all);
  }

  Future<List<Dtc>> readDtcs(DtcKind kind) async {
    final String mode = switch (kind) {
      DtcKind.confirmed => '03',
      DtcKind.pending => '07',
      DtcKind.permanent => '0A',
    };
    final ElmResponse r = await elm.send(mode);
    return [
      for (final EcuMessage m in r.messages)
        ...decodeDtcs(
          m.data,
          kind,
          ecu: m.ecu,
          hasCount: elm.protocolFamily != ProtocolFamily.kwp,
        ),
    ];
  }

  Future<FreezeFrame> readFreezeFrame() async {
    final ElmResponse r = await elm.send('0202');
    final List<Dtc> dtcs = [
      for (final EcuMessage m in r.messages)
        ...decodeDtcs(
          m.data.length >= 3 ? m.data.sublist(3) : const [],
          DtcKind.confirmed,
          ecu: m.ecu,
          hasCount: false,
        ),
    ];
    final ElmResponse supported = await elm.send('0200');
    final Map<int, double> values = {};
    if (supported.messages.isNotEmpty) {
      final List<int> data = supported.messages.first.data;
      final int index = data.indexOf(0x42);
      if (index >= 0 && data.length >= index + 6) {
        final SupportedPids pids = SupportedPids.fromMask(
          0,
          data.sublist(index + 2, index + 6),
        );
        for (final int pid in pids.pids) {
          final PidDef? def = standardPids[pid];
          if (def == null) {
            continue;
          }
          final ElmResponse value = await elm.send(
            '02${pid.toRadixString(16).padLeft(2, '0')}00'.toUpperCase(),
          );
          for (final EcuMessage message in value.messages) {
            final int responseIndex = message.data.indexOf(0x42);
            if (responseIndex >= 0 &&
                message.data.length >= responseIndex + 3 + def.bytes) {
              values[pid] = def.decode(
                message.data.sublist(
                  responseIndex + 3,
                  responseIndex + 3 + def.bytes,
                ),
              );
              break;
            }
          }
        }
      }
    }
    return FreezeFrame(dtcs: dtcs, values: Map.unmodifiable(values));
  }

  Future<VehicleInfo> readVehicleInfo() async {
    final ElmResponse vin = await elm.send('0902');
    final ElmResponse calid = await elm.send('0904');
    final ElmResponse cvn = await elm.send('0906');
    return VehicleInfo(
      vin: _identifierText(vin),
      calid: _identifierText(calid),
      cvn: _identifierHex(cvn),
    );
  }

  String _identifierText(ElmResponse response) => response.messages
      .expand((EcuMessage message) => message.data)
      .skip(3)
      .where((int byte) => byte >= 32 && byte < 127)
      .map((int byte) => String.fromCharCode(byte))
      .join();

  String _identifierHex(ElmResponse response) => response.messages
      .expand((EcuMessage message) => message.data)
      .skip(3)
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  Future<void> clearDtcs(Confirmation confirmation) async {
    final Map<int, PidValue> rpm = await readPids([12]);
    final PidValue? rpmValue = rpm[12];
    if (rpmValue == null) {
      throw StateError(
        'No se pudo confirmar que el motor esté apagado; no se borraron los códigos.',
      );
    }
    if (rpmValue.value > 0) {
      throw StateError(
        'Apaga el motor (deja solo el contacto) antes de borrar códigos.',
      );
    }
    final PreClearBackup? saveBackup = savePreClearBackup;
    if (saveBackup == null) {
      throw StateError(
        'No se configuró el respaldo previo; no se borraron los códigos.',
      );
    }
    final List<Dtc> confirmed = await readDtcs(DtcKind.confirmed);
    final List<Dtc> pending = await readDtcs(DtcKind.pending);
    final List<Dtc> permanent = await readDtcs(DtcKind.permanent);
    final FreezeFrame freezeFrame = await readFreezeFrame();
    final VehicleInfo vehicle = await readVehicleInfo();
    await saveBackup({
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'kind': 'pre_clear',
      'confirmed': _dtcPayload(confirmed),
      'pending': _dtcPayload(pending),
      'permanent': _dtcPayload(permanent),
      'freezeFrame': _dtcPayload(freezeFrame.dtcs),
      'freezeFrameValues': {
        for (final MapEntry<int, double> value in freezeFrame.values.entries)
          value.key.toString(): value.value,
      },
      'vin': vehicle.vin,
    });
    final ElmResponse cleared = await elm.send(
      '04',
      confirmation: confirmation,
    );
    if (!cleared.messages.any(
      (EcuMessage message) => message.data.contains(0x44),
    )) {
      throw StateError('El adaptador no confirmó el borrado de códigos.');
    }
    await readDtcs(DtcKind.confirmed);
  }

  List<Map<String, String>> _dtcPayload(List<Dtc> dtcs) => [
    for (final Dtc dtc in dtcs)
      {'code': dtc.code, 'kind': dtc.kind.name, 'ecu': dtc.ecu},
  ];
}
