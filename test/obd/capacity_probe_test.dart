import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/obd/capacity_probe.dart';

void main() {
  test('rejects wrong PID, short payloads and negative responses', () {
    expect(
      CapacityProbe.validResponse(
        '010C',
        ElmResponse.messages([
          const EcuMessage(ecu: '7E8', data: [0x41, 0x0D, 0, 0]),
        ]),
      ),
      false,
    );
    expect(
      CapacityProbe.validResponse(
        '010C',
        ElmResponse.messages([
          const EcuMessage(ecu: '7E8', data: [0x41, 0x0C, 0]),
        ]),
      ),
      false,
    );
    expect(
      CapacityProbe.validResponse(
        '221172',
        ElmResponse.messages([
          const EcuMessage(ecu: '7E8', data: [0x7F, 0x22, 0x31]),
        ]),
      ),
      false,
    );
    expect(
      CapacityProbe.validResponse(
        '010C',
        ElmResponse.messages([
          const EcuMessage(ecu: '7E8', data: [0x41, 0x0C, 0x0C, 0xE4]),
        ]),
      ),
      true,
    );
  });
  test(
    'exports every query, restores timing and validates mixed configuration',
    () async {
      final mock = MockTransport(
        engineRunning: true,
        latency: () => Duration.zero,
      );
      await mock.connect();
      final elm = Elm327(mock, delay: (_) async {});
      elm.minimumGap = const Duration(milliseconds: 150);
      final probe = CapacityProbe(
        elm,
        phaseDuration: const Duration(milliseconds: 120),
        enduranceDuration: const Duration(milliseconds: 150),
      );
      var exported = 0;
      await probe.run(
        onProgress: () {},
        onQuery: (phase, command, valid, error, metric) async {
          exported++;
          expect(metric?.command, command);
          expect(metric?.queueMs, greaterThanOrEqualTo(0));
        },
      );
      expect(exported, greaterThan(20));
      expect(probe.results.length, 10);
      expect(mock.writtenCommands, containsAll(['ATST64', 'ATAT0', 'ATAT2']));
      expect(probe.recommendation, isNotNull);
      expect(elm.minimumGap, const Duration(milliseconds: 150));
      expect(elm.pendingQueries, 0);
      await elm.close();
    },
  );
  test(
    'cancellation leaves no recommendation and restores configuration',
    () async {
      final mock = MockTransport(latency: () => Duration.zero);
      await mock.connect();
      final elm = Elm327(mock, delay: (_) async {});
      final probe = CapacityProbe(elm);
      await probe.run(
        onProgress: () {},
        onQuery: (_, command, valid, error, metric) async {
          probe.cancel();
        },
      );
      expect(probe.recommendation, isNull);
      expect(probe.results, isEmpty);
      expect(elm.minimumGap, const Duration(milliseconds: 50));
      await elm.close();
    },
  );
  test('sparse successful samples cannot qualify as stable', () {
    final phase = CapacityPhase(
      'x',
      ['010C'],
      50,
      1,
      const Duration(seconds: 15),
    );
    expect(
      CapacityResult(phase, 2, 2, const Duration(seconds: 15), [
        10,
        10,
      ], false).stable,
      false,
    );
    expect(
      CapacityResult(phase, 100, 97, const Duration(seconds: 15), [
        10,
      ], false).stable,
      false,
    );
  });
}
