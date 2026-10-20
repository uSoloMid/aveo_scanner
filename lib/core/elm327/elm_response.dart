import 'package:aveo_scanner/core/safety/command_guard.dart';

enum ElmError {
  noData,
  unknownCommand,
  unableToConnect,
  canError,
  busError,
  busBusy,
  fbError,
  dataError,
  stopped,
  bufferFull,
  adapterError,
  lowVoltageReset,
}

final class EcuMessage {
  const EcuMessage({required this.ecu, required this.data});
  final String ecu;
  final List<int> data;
}

final class ElmResponse {
  const ElmResponse._({
    this.raw = '',
    this.text,
    this.messages = const [],
    this.error,
  });
  factory ElmResponse.text(String value, {String raw = ''}) =>
      ElmResponse._(text: value, raw: raw);
  factory ElmResponse.messages(List<EcuMessage> values, {String raw = ''}) =>
      ElmResponse._(messages: List.unmodifiable(values), raw: raw);
  factory ElmResponse.error(ElmError value, {String raw = ''}) =>
      ElmResponse._(error: value, raw: raw);
  final String raw;
  final String? text;
  final List<EcuMessage> messages;
  final ElmError? error;
  bool get isNegative =>
      messages.any((EcuMessage m) => m.data.length >= 3 && m.data[0] == 0x7f);
  int? get negativeCode {
    for (final EcuMessage m in messages) {
      if (m.data.length >= 3 && m.data[0] == 0x7f) {
        return m.data[2];
      }
    }
    return null;
  }
}

final class ElmTimeoutException implements Exception {
  const ElmTimeoutException();
}

final class CommandBlockedException implements Exception {
  const CommandBlockedException(this.result);
  final GuardResult result;
}

final class ConfirmationRequiredException implements Exception {
  const ConfirmationRequiredException(this.result);
  final GuardResult result;
}

final class ElmInitException implements Exception {
  const ElmInitException(this.message);
  final String message;
}

final class ElmInfo {
  const ElmInfo({
    required this.version,
    required this.protocolCode,
    required this.protocolName,
    required this.voltage,
    required this.supportedPids,
  });
  final String version, protocolCode, protocolName;
  final double voltage;
  final List<EcuMessage> supportedPids;
}
