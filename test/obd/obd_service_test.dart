import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/elm327.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/core/transport/mock_transport.dart';
import 'package:aveo_scanner/obd/dtc.dart';
import 'package:aveo_scanner/obd/obd_service.dart';

void main() {
  test(
    'reads standard PIDs, supported masks, DTCs, and mode 09 identifiers',
    () async {
      final MockTransport mock = MockTransport(
        engineRunning: true,
        latency: () => Duration.zero,
      );
      await mock.connect();
      final Elm327 elm = Elm327(mock, delay: (_) async {});
      final ObdService service = ObdService(elm);
      final values = await service.readPids([12, 13, 5, 999]);
      expect(values.keys, {12, 13, 5});
      expect(values[12]!.value, inInclusiveRange(750, 3000));
      expect(values[13]!.value, inInclusiveRange(0, 80));
      expect((await service.readSupportedPids()).pids, isNotEmpty);
      expect(
        mock.writtenCommands.where((String c) => c.startsWith('01')),
        containsAll(['0100', '0120', '0140']),
      );
      expect(
        (await service.readDtcs(DtcKind.confirmed)).map((Dtc d) => d.code),
        contains('P0133'),
      );
      final info = await service.readVehicleInfo();
      expect(info.vin, 'KL1TD5DE5CB000000');
      expect(info.calid, '12345678ABCDEF');
      expect(info.cvn, '01020304');
      final freeze = await service.readFreezeFrame();
      expect(freeze.dtcs.map((Dtc d) => d.code), contains('P0300'));
      expect(freeze.values[5], 50);
      await elm.close();
    },
  );
  test('refuses clear if RPM cannot be confirmed', () async {
    final MockTransport mock = MockTransport(
      noRpmData: true,
      latency: () => Duration.zero,
    );
    await mock.connect();
    final Elm327 elm = Elm327(mock, delay: (_) async {});
    final ObdService service = ObdService(
      elm,
      savePreClearBackup: (_) async {},
    );
    await expectLater(
      service.clearDtcs(Confirmation.userApproved('04')),
      throwsA(isA<StateError>()),
    );
    expect(mock.writtenCommands, ['010C']);
    await elm.close();
  });
  test('refuses clear while RPM is positive and never sends 04', () async {
    final MockTransport mock = MockTransport(
      engineRunning: true,
      latency: () => Duration.zero,
    );
    await mock.connect();
    final Elm327 elm = Elm327(mock, delay: (_) async {});
    final ObdService service = ObdService(
      elm,
      savePreClearBackup: (_) async {},
    );
    await expectLater(
      service.clearDtcs(Confirmation.userApproved('04')),
      throwsA(isA<StateError>()),
    );
    expect(mock.writtenCommands, ['010C']);
    await elm.close();
  });
  test('does not clear when the pre-clear backup fails', () async {
    final MockTransport mock = MockTransport(latency: () => Duration.zero);
    await mock.connect();
    final Elm327 elm = Elm327(mock, delay: (_) async {});
    final ObdService service = ObdService(
      elm,
      savePreClearBackup: (_) async {
        throw StateError('disk');
      },
    );
    await expectLater(
      service.clearDtcs(Confirmation.userApproved('04')),
      throwsA(isA<StateError>()),
    );
    await elm.close();
  });
  test('backs up before clearing when RPM is zero', () async {
    final MockTransport mock = MockTransport(latency: () => Duration.zero);
    await mock.connect();
    final Elm327 elm = Elm327(mock, delay: (_) async {});
    Map<String, Object?>? backup;
    final ObdService service = ObdService(
      elm,
      savePreClearBackup: (Map<String, Object?> payload) async {
        backup = payload;
      },
    );
    await service.clearDtcs(Confirmation.userApproved('04'));
    expect(backup?['kind'], 'pre_clear');
    expect(backup?['vin'], 'KL1TD5DE5CB000000');
    expect(backup?['confirmed'], isNotEmpty);
    expect(await service.readDtcs(DtcKind.confirmed), isEmpty);
    expect(await service.readDtcs(DtcKind.permanent), isNotEmpty);
    await elm.close();
  });
}
