import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/safety/command_guard.dart';

void main() {
  test('mandatory allowed and confirmation commands', () {
    for (final String command in [
      '010C',
      '01 0c',
      '0100',
      '03',
      '07',
      '0A',
      '0902',
      '22 11A1',
      '134000',
      'ATZ',
      'atsp6',
      'ATSH7E0',
      'ATRV',
    ]) {
      expect(
        CommandGuard.check(command).verdict,
        GuardVerdict.allowed,
        reason: command,
      );
    }
    for (final String command in ['04', '14FF00', 'AE01']) {
      expect(
        CommandGuard.check(command).verdict,
        GuardVerdict.needsConfirmation,
      );
    }
  });
  test('mandatory blocked commands', () {
    for (final String command in [
      '10 03',
      '1101',
      '2701',
      '2E1234',
      '3B01',
      '3101',
      '34',
      '36',
      '37',
      'FF',
      'ATMA',
      'AT MA',
      'ATMR01',
      'ATMT01',
      'ATPPS',
      'ATPP0CSV',
      'ATBRD45',
      'ATBRT',
      '',
      '   ',
      '010C\r04',
      '010C\n',
      'ST DI',
      '01G0',
      '010',
      '0',
      'X' * 33,
    ]) {
      expect(
        CommandGuard.check(command).verdict,
        GuardVerdict.blocked,
        reason: command,
      );
    }
  });
}
