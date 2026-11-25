import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/data/csv_log_writer.dart';
import 'package:aveo_scanner/obd/gm_pids.dart';
import 'package:aveo_scanner/obd/idle_recorder.dart';
import 'package:aveo_scanner/obd/mode22_scanner.dart';
import 'package:aveo_scanner/obd/obd_service.dart';
import 'package:aveo_scanner/obd/recorder_profile.dart';

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
  test(
    'TPS profiles keep priorities and comparison pairs the readings',
    () async {
      final profile = RecorderProfile.fromJson(RecorderProfile.tps.toJson());
      expect(profile.channels().map((c) => c.key), ['mariposa_pct', 'rpm']);
      expect(profile.channels().every((c) => c.fast), isTrue);
      expect(profile.dtcMinutes, 0);

      final (_, elm, obd) = await _setup();
      var now = DateTime(2026, 11, 25);
      var rpm = 0.0;
      var relative = 4.0;
      final values = <String, double Function()>{
        'mariposa_pct': () => 11,
        'mariposa_relativa_pct': () => relative,
        'rpm': () => rpm,
        'velocidad_kmh': () => 0,
      };
      final recorder = IdleRecorder(
        obd,
        now: () => now,
        channels: [
          for (final entry in values.entries)
            RecorderChannel(
              key: entry.key,
              nameEs: entry.key,
              unit: '',
              fast: true,
              read: (_) async => entry.value(),
            ),
        ],
      );
      addTearDown(recorder.dispose);
      addTearDown(elm.close);
      await recorder.cycle();
      rpm = 1500;
      final started = await recorder.cycle();
      expect(started[estimatedThrottleReferenceKey], 7);
      expect(started.events.any((e) => e.contains('relativa elevada')), isTrue);
      now = now.add(const Duration(seconds: 5));
      final settled = await recorder.cycle();
      expect(settled.events.single, contains('ARRANQUE'));
      expect(
        RecorderCsvFormat(recorder.logChannels).header(),
        contains(estimatedThrottleReferenceKey),
      );
      relative = 0;
      final normal = await recorder.cycle();
      expect(normal[estimatedThrottleReferenceKey], 11);
      expect(normal.events, isEmpty);
    },
  );

  test('parses real KWP mode 22 frames captured on the Aveo', () {
    const ResponseParser parser = ResponseParser();
    final iac = parser.parse(
      '83F111621172258F\r\r>',
      protocol: ProtocolFamily.kwp,
      command: '221172',
    );
    expect(mode22Payload([for (final m in iac.messages) m.data], 0x1172), [
      0x25,
    ]);
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

  test(
    'probe keeps verified channels and drops unanswered optional ones',
    () async {
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
    },
  );

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
    final marker = first.events.singleWhere((e) => e.endsWith(' SE ACELERÓ'));
    expect(marker, endsWith(' SE ACELERÓ'));
    expect(marker, startsWith('2026-10-22T10:59:03.120'));
    expect(second.events, isEmpty);
    final RecorderCsvFormat csv = RecorderCsvFormat(recorder.channels);
    expect(csv.header(), startsWith('hora,evento,ralenti_alto,rpm,iac_pasos,'));
    expect(
      csv.row(first),
      startsWith('10:59:03.120,2026-10-22T10:59:03.120 SE ACELERÓ'),
    );
    expect(csv.row(first), contains(',47,'));
    await recorder.dispose();
    await elm.close();
  });

  test('failed readings clear values and cannot sustain high idle', () async {
    final (_, elm, obd) = await _setup();
    var fails = false;
    var time = DateTime(2026, 11, 3);
    final recorder = IdleRecorder(
      obd,
      now: () => time,
      channels: [
        for (final entry in {
          'rpm': 1500.0,
          'ralenti_deseado_rpm': 825.0,
          'velocidad_kmh': 0.0,
          'mariposa_pct': 11.0,
        }.entries)
          RecorderChannel(
            key: entry.key,
            nameEs: entry.key,
            unit: '',
            fast: true,
            read: (_) async => fails ? null : entry.value,
          ),
      ],
    );
    await recorder.cycle();
    expect((await recorder.cycle()).highIdle, isTrue);
    fails = true;
    time = time.add(const Duration(seconds: 1));
    final failed = await recorder.cycle();
    expect(failed['rpm'], isNull);
    expect(failed.canEvaluate, isFalse);
    expect(failed.highIdle, isFalse);
    expect(failed.readAt['rpm'], time.subtract(const Duration(seconds: 1)));
    await recorder.dispose();
    await elm.close();
  });

  test('slow measurements expire while waiting for their next turn', () async {
    final (_, elm, obd) = await _setup();
    var time = DateTime(2026, 11, 3);
    final recorder = IdleRecorder(
      obd,
      now: () => time,
      slowPerCycle: 1,
      channels: [
        RecorderChannel(
          key: 'map',
          nameEs: 'MAP',
          unit: 'kPa',
          read: (_) async => 40,
        ),
        RecorderChannel(
          key: 'temperature',
          nameEs: 'Temperature',
          unit: 'C',
          read: (_) async => 90,
        ),
      ],
    );
    expect((await recorder.cycle())['map'], 40);
    time = time.add(const Duration(seconds: 16));
    final expired = await recorder.cycle();
    expect(expired['map'], isNull);
    expect(expired['temperature'], 90);
    expect(expired.readAt['map'], DateTime(2026, 11, 3));
    await recorder.dispose();
    await elm.close();
  });

  test(
    'recovers ECU loss even while adapter voltage keeps answering',
    () async {
      final (_, elm, obd) = await _setup();
      var recovered = false;
      var attempts = 0;
      final recorder = IdleRecorder(
        obd,
        recover: () async {
          attempts++;
          recovered = true;
        },
        channels: [
          RecorderChannel(
            key: 'rpm',
            nameEs: 'RPM',
            unit: 'rpm',
            fast: true,
            read: (_) async => recovered ? 825 : null,
          ),
          RecorderChannel(
            key: 'voltaje_bateria_v',
            nameEs: 'OBD',
            unit: 'V',
            read: (_) async => 14.7,
          ),
        ],
      );
      final samples = <RecorderSample>[];
      final subscription = recorder.samples.listen(samples.add);
      final restored = recorder.samples.firstWhere((s) => s['rpm'] == 825);
      recorder.start();
      await restored.timeout(const Duration(seconds: 5));
      await recorder.stop();
      expect(attempts, 1);
      expect(samples.first['rpm'], isNull);
      expect(samples.first['voltaje_bateria_v'], 14.7);
      expect(
        samples.expand((s) => s.events),
        contains('COMUNICACIÓN: lecturas del motor recuperadas'),
      );
      await subscription.cancel();
      await recorder.dispose();
      await elm.close();
    },
  );

  test('missing RPM does not reset an ECU that still answers IAC', () async {
    final (_, elm, obd) = await _setup();
    var recoveries = 0;
    final recorder = IdleRecorder(
      obd,
      delay: (_) async {},
      recover: () async {
        recoveries++;
      },
      channels: [
        RecorderChannel(
          key: 'rpm',
          nameEs: 'RPM',
          unit: 'rpm',
          fast: true,
          read: (_) async => null,
        ),
        RecorderChannel(
          key: 'iac_pasos',
          nameEs: 'IAC',
          unit: '',
          fast: true,
          read: (_) async => 35,
        ),
      ],
    );
    final samples = <RecorderSample>[];
    final subscription = recorder.samples.listen(samples.add);
    final three = recorder.samples.take(3).toList();
    recorder.start();
    await three;
    await recorder.stop();
    expect(recoveries, 0);
    expect(
      samples.expand((s) => s.events),
      contains('LECTURA: falta RPM; otras señales del motor responden'),
    );
    expect(
      samples.expand((s) => s.events),
      isNot(contains('COMUNICACIÓN: sin respuesta del motor')),
    );
    expect(elm.minimumGap.inMilliseconds, greaterThan(100));
    await subscription.cancel();
    await recorder.dispose();
    await elm.close();
  });

  test('one spaced retry recovers an isolated critical reading', () async {
    final (_, elm, obd) = await _setup();
    var reads = 0;
    final waits = <Duration>[];
    final recorder = IdleRecorder(
      obd,
      delay: (d) async {
        waits.add(d);
      },
      channels: [
        RecorderChannel(
          key: 'rpm',
          nameEs: 'RPM',
          unit: 'rpm',
          fast: true,
          read: (_) async => ++reads == 1 ? null : 825,
        ),
      ],
    );
    final sample = await recorder.cycle();
    expect(sample['rpm'], 825);
    expect(reads, 2);
    expect(waits, [const Duration(milliseconds: 200)]);
    expect(sample.events, contains('LECTURA: RPM recuperada en reintento'));
    expect(elm.minimumGap, const Duration(milliseconds: 150));
    await recorder.dispose();
    await elm.close();
  });

  test(
    'slow readings with longer intervals still meet their due turn',
    () async {
      final (_, elm, obd) = await _setup();
      var now = DateTime(2026, 11, 3);
      final calls = <String, List<DateTime>>{};
      final recorder = IdleRecorder(
        obd,
        now: () => now,
        slowPerCycle: 1,
        channels: [
          for (final key in ['map_kpa', 'trim_corto_pct', 'refrigerante_c'])
            RecorderChannel(
              key: key,
              nameEs: key,
              unit: '',
              read: (_) async {
                calls.putIfAbsent(key, () => []).add(now);
                return 1;
              },
            ),
        ],
      );
      for (var i = 0; i < 30; i++) {
        await recorder.cycle();
        now = now.add(const Duration(seconds: 1));
      }
      final temperatures = calls['refrigerante_c']!;
      expect(temperatures.length, greaterThanOrEqualTo(3));
      for (var i = 1; i < temperatures.length; i++) {
        expect(
          temperatures[i].difference(temperatures[i - 1]).inSeconds,
          lessThanOrEqualTo(12),
        );
      }
      await recorder.dispose();
      await elm.close();
    },
  );

  test('mode 22 scanner finds the identifiers the ECU answers', () async {
    final (_, elm, obd) = await _setup();
    final List<ScanProgress> steps = await Mode22Scanner(obd)
        .scan(0x1170, 0x11A1)
        .toList();
    final hits = steps.last.hits.map((h) => h.idHex).toList();
    expect(hits, ['1170', '1172', '1192', '11A1']);
    expect(steps.last.done, 0x11A1 - 0x1170 + 1);
    expect(mode22HitsCsv(steps.last.hits), contains('1172,221172,2F,47,'));
    await elm.close();
  });
}
