import 'package:aveo_scanner/obd/pid.dart';

int _a(List<int> d) => d[0];
int _ab(List<int> d) => d[0] * 256 + d[1];
final Map<int, PidDef> standardPids = {
  for (final PidDef p in <PidDef>[
    const PidDef(
      pid: 3,
      nameEs: 'Estado de combustible',
      unit: '',
      bytes: 1,
      decode: _aD,
      min: 0,
      max: 255,
    ),
    const PidDef(
      pid: 20,
      nameEs: 'Sensor O2 1',
      unit: 'V',
      bytes: 2,
      decode: _o2Volts,
      min: 0,
      max: 1.275,
    ),
    const PidDef(
      pid: 21,
      nameEs: 'Sensor O2 2',
      unit: 'V',
      bytes: 2,
      decode: _o2Volts,
      min: 0,
      max: 1.275,
    ),
    const PidDef(
      pid: 69,
      nameEs: 'Mariposa relativa',
      unit: '%',
      bytes: 1,
      decode: _load,
      min: 0,
      max: 100,
    ),
    const PidDef(
      pid: 4,
      nameEs: 'Carga del motor',
      unit: '%',
      bytes: 1,
      decode: _load,
      min: 0,
      max: 100,
    ),
    const PidDef(
      pid: 5,
      nameEs: 'Temperatura refrigerante',
      unit: '°C',
      bytes: 1,
      decode: _temp,
      min: -40,
      max: 215,
    ),
    const PidDef(
      pid: 6,
      nameEs: 'Trim combustible corto',
      unit: '%',
      bytes: 1,
      decode: _trim,
      min: -100,
      max: 100,
    ),
    const PidDef(
      pid: 7,
      nameEs: 'Trim combustible largo',
      unit: '%',
      bytes: 1,
      decode: _trim,
      min: -100,
      max: 100,
    ),
    const PidDef(
      pid: 11,
      nameEs: 'Presión del múltiple',
      unit: 'kPa',
      bytes: 1,
      decode: _aD,
      min: 0,
      max: 255,
    ),
    const PidDef(
      pid: 12,
      nameEs: 'RPM',
      unit: 'rpm',
      bytes: 2,
      decode: _rpm,
      min: 0,
      max: 16383,
    ),
    const PidDef(
      pid: 13,
      nameEs: 'Velocidad',
      unit: 'km/h',
      bytes: 1,
      decode: _speed,
      min: 0,
      max: 255,
    ),
    const PidDef(
      pid: 14,
      nameEs: 'Avance de encendido',
      unit: '°',
      bytes: 1,
      decode: _advance,
      min: -64,
      max: 63.5,
    ),
    const PidDef(
      pid: 15,
      nameEs: 'Temperatura de admisión',
      unit: '°C',
      bytes: 1,
      decode: _temp,
      min: -40,
      max: 215,
    ),
    const PidDef(
      pid: 16,
      nameEs: 'Flujo de aire',
      unit: 'g/s',
      bytes: 2,
      decode: _maf,
      min: 0,
      max: 655.35,
    ),
    const PidDef(
      pid: 17,
      nameEs: 'Posición del acelerador',
      unit: '%',
      bytes: 1,
      decode: _load,
      min: 0,
      max: 100,
    ),
    const PidDef(
      pid: 31,
      nameEs: 'Tiempo desde arranque',
      unit: 's',
      bytes: 2,
      decode: _abD,
      min: 0,
      max: 65535,
    ),
    const PidDef(
      pid: 47,
      nameEs: 'Nivel de combustible',
      unit: '%',
      bytes: 1,
      decode: _load,
      min: 0,
      max: 100,
    ),
    const PidDef(
      pid: 1,
      nameEs: 'Estado de monitores',
      unit: '',
      bytes: 4,
      decode: _monitor,
      min: 0,
      max: 255,
    ),
    const PidDef(
      pid: 51,
      nameEs: 'Presión barométrica',
      unit: 'kPa',
      bytes: 1,
      decode: _aD,
      min: 0,
      max: 255,
    ),
    const PidDef(
      pid: 66,
      nameEs: 'Voltaje del módulo',
      unit: 'V',
      bytes: 2,
      decode: _voltage,
      min: 0,
      max: 65.535,
    ),
  ])
    p.pid: p,
};
double _load(List<int> d) => _a(d) * 100 / 255;
double _temp(List<int> d) => _a(d) - 40;
double _trim(List<int> d) => (_a(d) - 128) * 100 / 128;
double _aD(List<int> d) => _a(d).toDouble();
double _rpm(List<int> d) => _ab(d) / 4;
double _speed(List<int> d) => _a(d).toDouble();
double _advance(List<int> d) => _a(d) / 2 - 64;
double _maf(List<int> d) => _ab(d) / 100;
double _o2Volts(List<int> d) => _a(d) / 200;
double _abD(List<int> d) => _ab(d).toDouble();
double _voltage(List<int> d) => _ab(d) / 1000;
double _monitor(List<int> d) =>
    (((_a(d) & 0x80) != 0 ? 1 : 0) * 100 + (_a(d) & 0x7f)).toDouble();
double fuelLph(double maf) => maf * 3600 / (14.7 * 740);
double? kmPerL(double speed, double lph) => lph < 0.05 ? null : speed / lph;
