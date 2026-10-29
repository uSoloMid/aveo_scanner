/// GM mode 22 (read data by identifier) parameters for the Aveo T250
/// (Delphi MR-140 / HV-240 ECU over KWP2000).
///
/// Source: OBDb/Chevrolet-Aveo signalsets/v3/default.json. Entries marked
/// [GmPidDef.verified] were confirmed on the owner's 2012 Mexican Aveo
/// (2026-10-22): 1192 read 0x41 (812 rpm) at a warm idle of 847 rpm.
library;

final class GmPidDef {
  const GmPidDef({
    required this.id,
    required this.key,
    required this.nameEs,
    required this.unit,
    required this.bytes,
    required this.decode,
    this.verified = false,
    this.recordByDefault = false,
  });

  /// 16-bit data identifier, e.g. 0x1192 is sent as `221192`.
  final int id;

  /// Column name used in CSV files.
  final String key;
  final String nameEs, unit;
  final int bytes;
  final double Function(List<int>) decode;
  final bool verified;

  /// Optional extras recorded every session (each one slows the loop).
  final bool recordByDefault;

  String get command =>
      '22${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

int _a(List<int> d) => d[0];
int _ab(List<int> d) => d[0] * 256 + d[1];

double _desiredIdle(List<int> d) => _a(d) * 12.5;
double _raw8(List<int> d) => _a(d).toDouble();
double _raw16(List<int> d) => _ab(d).toDouble();
double _knock(List<int> d) => _a(d) * 22 / 100;
double _tenths(List<int> d) => _a(d) / 10;
double _percent(List<int> d) => _a(d) * 100 / 255;
double _millivolts(List<int> d) => _ab(d) / 1000;

const GmPidDef gmDesiredIdle = GmPidDef(
  id: 0x1192,
  key: 'ralenti_deseado_rpm',
  nameEs: 'Ralentí deseado',
  unit: 'rpm',
  bytes: 1,
  decode: _desiredIdle,
  verified: true,
);

const GmPidDef gmIacPosition = GmPidDef(
  id: 0x1172,
  key: 'iac_pasos',
  nameEs: 'Posición IAC',
  unit: 'pasos',
  bytes: 1,
  decode: _raw8,
  verified: true,
);

/// Everything the recorder tries. Unverified ones are probed once at the
/// start of a session and dropped if the ECU does not answer.
const List<GmPidDef> gmPids = [
  gmDesiredIdle,
  gmIacPosition,
  // Found by the 2026-10-22 scan; meaning unknown. 1170 read 39 (= normal
  // IAC steps) and 1176 read 48 (= current IAC) while idling high.
  GmPidDef(
    id: 0x1170,
    key: 'gm_1170',
    nameEs: 'GM 1170 (¿IAC base?)',
    unit: '',
    bytes: 1,
    decode: _raw8,
    recordByDefault: true,
  ),
  GmPidDef(
    id: 0x1176,
    key: 'gm_1176',
    nameEs: 'GM 1176 (¿IAC?)',
    unit: '',
    bytes: 1,
    decode: _raw8,
    recordByDefault: true,
  ),
  GmPidDef(
    id: 0x11A6,
    key: 'retardo_cascabeleo_grados',
    nameEs: 'Retardo por cascabeleo',
    unit: '°',
    bytes: 1,
    decode: _knock,
  ),
  GmPidDef(
    id: 0x1141,
    key: 'voltaje_ignicion_v',
    nameEs: 'Voltaje de ignición',
    unit: 'V',
    bytes: 1,
    decode: _tenths,
  ),
  GmPidDef(
    id: 0x0042,
    key: 'voltaje_modulo_v',
    nameEs: 'Voltaje del módulo',
    unit: 'V',
    bytes: 2,
    decode: _millivolts,
  ),
  GmPidDef(
    id: 0x13AF,
    key: 'ventilador_pct',
    nameEs: 'Ventilador (comando)',
    unit: '%',
    bytes: 1,
    decode: _percent,
  ),
  GmPidDef(
    id: 0x11A1,
    key: 'tiempo_encendido_s',
    nameEs: 'Tiempo desde arranque',
    unit: 's',
    bytes: 2,
    decode: _raw16,
  ),
  GmPidDef(
    id: 0x1200,
    key: 'fallas_encendido_total',
    nameEs: 'Fallas de encendido',
    unit: '',
    bytes: 1,
    decode: _raw8,
  ),
];

/// Extracts the data bytes that follow `62 HI LO` for [id], or null when the
/// ECU answered negatively (`7F 22 xx`) or with something else.
List<int>? mode22Payload(List<List<int>> messages, int id) {
  final int hi = (id >> 8) & 0xff, lo = id & 0xff;
  for (final List<int> data in messages) {
    for (int i = 0; i + 2 < data.length; i++) {
      if (data[i] == 0x62 && data[i + 1] == hi && data[i + 2] == lo) {
        return data.sublist(i + 3);
      }
    }
  }
  return null;
}
