import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/data/csv_log_writer.dart';
import 'package:aveo_scanner/obd/gm_pids.dart';
import 'package:aveo_scanner/obd/idle_recorder.dart';
import 'package:aveo_scanner/obd/mode22_scanner.dart';
import 'package:aveo_scanner/obd/obd_service.dart';

Future<(MockTransport, Elm327, ObdService)> _setup({bool kwp = false}) async {
  final MockTransport mock = MockTransport(
    kwp: kwp,
    engineRunning: true,
    latency: () => Duration.zero,
  );
  await mock.connect();
  final Elm327 elm = Elm327(mock, delay: (_) async {});
  if (kwp) elm.protocolFamily = ProtocolFamily.kwp;
  return (mock, elm, ObdService(elm));
}

void main() {
  test('parses real KWP mode 22 frames captured on the Aveo', () {
    const ResponseParser parser = ResponseParser();
    final iac = parser.parse(
      '83F111621172258F\r\r>',
      protocol: ProtocolFamily.kwp,
      command: '221172',
    );
    expect(
      mode22Payload([for (final m in iac.messages) m.data], 0x1172),
      [0x25],
    );
    final desired = parser.parse(
      '83F11162119241CB\r\r>',
      protocol: ProtocolFamily.kwp,
      command: '221192',
    );
    final payload = mode22Payload([
      for (final m in desired.messages) m.data,
    ], 0x1192)!;
    expect(gmDesiredIdle.decode(payload), 812.5);
  });

  test('reads desired idle and IAC through ObdService', () async {
    for (final bool kwp in [false, true]) {
      final (_, elm, obd) = await _setup(kwp: kwp);
      expect(await obd.readGm(gmDesiredIdle), 825);
      expect(await obd.readGm(gmIacPosition), 47);
      expect(await obd.probeMode22(0x1234), isNull);
      await elm.close();
    }
  });

  test('probe keeps verified channels and drops unanswered optional ones', () async {
    final (_, elm, obd) = await _setup();
    final IdleRecorder recorder = IdleRecorder(obd);
    final List<String> dropped = await recorder.probe();
    final keys = recorder.channels.map((c) => c.key).toSet();
    expect(keys, containsAll(['rpm', 'ralenti_deseado_rpm', 'iac_pasos']));
    expect(keys, contains('mariposa_relativa_pct'));
    expect(keys, contains('gm_1170')); // mock answers 221170
    expect(keys, isNot(contains('gm_1176')));
    expect(dropped, ['GM 1176 (¿IAC?)']);
    final RecorderSample sample = await recorder.cycle();
    expect(sample['ralenti_deseado_rpm'], 825);
    expect(sample['iac_pasos'], 47);
    expect(sample['rpm'], isNotNull);
    await recorder.dispose();
    await elm.close();
  });

  test('high idle detector needs two samples and has hysteresis', () {
    final HighIdleDetector d = HighIdleDetector();
    Map<String, double?> v(double rpm, {double speed = 0}) => {
      'rpm': rpm,
      'ralenti_deseado_rpm': 825,
      'velocidad_kmh': speed,
      'mariposa_pct': 11,
    };
    expect(d.update(v(1470)), isNull);
    expect(d.update(v(1470)), startsWith('AUTO: ralentí alto'));
    expect(d.isHigh, isTrue);
    expect(d.update(v(1100)), isNull); // still above exit threshold
    expect(d.update(v(850)), startsWith('AUTO: ralentí normal'));
    expect(d.isHigh, isFalse);
    expect(d.update(v(2000, speed: 40)), isNull); // driving is not idle
    expect(d.update(v(2000, speed: 40)), isNull);
  });

  test('marks appear once in the next sample and in the CSV row', () async {
    final (_, elm, obd) = await _setup();
    final IdleRecorder recorder = IdleRecorder(
      obd,
      channels: [
        RecorderChannel.pid(12, 'rpm', 'RPM', 'rpm', fast: true),
        RecorderChannel.gm(gmIacPosition, fast: true),
      ],
      now: () => DateTime(2026, 10, 22, 10, 59, 3, 120),
    );
    recorder.mark('SE ACELERÓ');
    final RecorderSample first = await recorder.cycle();
    final RecorderSample second = await recorder.cycle();
    expect(first.events, ['SE ACELERÓ']);
    expect(second.events, isEmpty);
    final RecorderCsvFormat csv = RecorderCsvFormat(recorder.channels);
    expect(csv.header(), 'hora,evento,ralenti_alto,rpm,iac_pasos');
    expect(csv.row(first), startsWith('10:59:03.120,SE ACELERÓ,0,'));
    expect(csv.row(first), endsWith(',47'));
    await recorder.dispose();
    await elm.close();
  });

  test('mode 22 scanner finds the identifiers the ECU answers', () async {
    final (_, elm, obd) = await _setup();
    final List<ScanProgress> steps = await Mode22Scanner(
      obd,
    ).scan(0x1170, 0x11A1).toList();
    final hits = steps.last.hits.map((h) => h.idHex).toList();
    expect(hits, ['1170', '1172', '1192', '11A1']);
    expect(steps.last.done, 0x11A1 - 0x1170 + 1);
    expect(mode22HitsCsv(steps.last.hits), contains('1172,221172,2F,47,'));
    await elm.close();
  });
}
