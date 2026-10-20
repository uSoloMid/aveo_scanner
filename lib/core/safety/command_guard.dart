enum GuardVerdict { allowed, needsConfirmation, blocked }

final class GuardResult {
  const GuardResult(this.verdict, this.normalized, this.reason);
  final GuardVerdict verdict;
  final String normalized;
  final String reason;
}

abstract final class CommandGuard {
  static const Set<String> _allowed = {
    '01',
    '02',
    '03',
    '07',
    '09',
    '0A',
    '22',
    '13',
  };
  static const Set<String> _confirm = {'04', '14', 'AE'};

  static GuardResult check(String raw) {
    if (raw.codeUnits.any((int c) => c < 0x20 || c == 0x7f)) {
      return GuardResult(
        GuardVerdict.blocked,
        '',
        'caracteres de control no permitidos',
      );
    }
    final String command = raw.replaceAll(' ', '').toUpperCase();
    if (command.isEmpty) {
      return GuardResult(GuardVerdict.blocked, command, 'comando vacío');
    }
    if (command.length > 32) {
      return GuardResult(
        GuardVerdict.blocked,
        command,
        'comando demasiado largo',
      );
    }
    if (command.startsWith('AT')) {
      final String suffix = command.substring(2);
      if (!RegExp(r'^[A-Z0-9]*$').hasMatch(suffix)) {
        return GuardResult(
          GuardVerdict.blocked,
          command,
          'comando AT inválido',
        );
      }
      if (const ['MA', 'MR', 'MT', 'PP', 'BRD', 'BRT'].any(suffix.startsWith)) {
        return GuardResult(
          GuardVerdict.blocked,
          command,
          'comando AT bloqueado por seguridad',
        );
      }
      return GuardResult(GuardVerdict.allowed, command, 'comando AT permitido');
    }
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(command) ||
        command.length < 2 ||
        command.length.isOdd) {
      return GuardResult(GuardVerdict.blocked, command, 'comando OBD inválido');
    }
    final String service = command.substring(0, 2);
    if (_allowed.contains(service)) {
      return GuardResult(GuardVerdict.allowed, command, 'lectura permitida');
    }
    if (_confirm.contains(service)) {
      return GuardResult(
        GuardVerdict.needsConfirmation,
        command,
        'requiere confirmación del usuario',
      );
    }
    return GuardResult(
      GuardVerdict.blocked,
      command,
      'servicio bloqueado por seguridad',
    );
  }
}

final class Confirmation {
  const Confirmation._(this.command);
  final String command;
  factory Confirmation.userApproved(String command) {
    final GuardResult result = CommandGuard.check(command);
    if (result.verdict == GuardVerdict.blocked) {
      throw ArgumentError(result.reason);
    }
    return Confirmation._(result.normalized);
  }
}
