import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/traffic_log.dart';

enum ProtocolFamily { can11, can29, kwp, unknown }

final class ResponseParser {
  const ResponseParser({this.log});
  final TrafficLog? log;
  ElmResponse parse(
    String raw, {
    required ProtocolFamily protocol,
    String? command,
  }) {
    final String cleaned = raw.replaceAll('>', '');
    final List<String> lines = cleaned
        .split(RegExp(r'\r|\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .where((String line) => !line.toUpperCase().contains('SEARCHING...'))
        .where((String line) => !line.toUpperCase().startsWith('BUS INIT'))
        .where((String line) => line.toUpperCase() != command?.toUpperCase())
        .map((String line) => line.replaceAll(RegExp(r'\s+'), ''))
        .toList();
    if (lines.isEmpty) {
      return ElmResponse.text('', raw: raw);
    }
    final String joined = lines.join(' ').toUpperCase();
    final String errorText = joined.replaceAll(' ', '');
    if (command?.toUpperCase().startsWith('AT') == true ||
        joined.startsWith('ELM') ||
        joined == 'OK' ||
        joined.endsWith('V')) {
      return ElmResponse.text(joined, raw: raw);
    }
    const Map<String, ElmError> errors = {
      'NO DATA': ElmError.noData,
      '?': ElmError.unknownCommand,
      'UNABLE TO CONNECT': ElmError.unableToConnect,
      'CAN ERROR': ElmError.canError,
      'BUS ERROR': ElmError.busError,
      'BUS BUSY': ElmError.busBusy,
      'FB ERROR': ElmError.fbError,
      'DATA ERROR': ElmError.dataError,
      'STOPPED': ElmError.stopped,
      'BUFFER FULL': ElmError.bufferFull,
      'LV RESET': ElmError.lowVoltageReset,
    };
    for (final MapEntry<String, ElmError> entry in errors.entries) {
      if (errorText.contains(entry.key.replaceAll(' ', ''))) {
        return ElmResponse.error(entry.value, raw: raw);
      }
    }
    if (RegExp(r'ERR\d+').hasMatch(joined)) {
      return ElmResponse.error(ElmError.adapterError, raw: raw);
    }
    final List<EcuMessage> result = [];
    final Map<String, List<int>> firstFrames = {};
    final Map<String, int> expectedLengths = {};
    final Map<String, Map<int, List<int>>> consecutiveFrames = {};
    final Map<String, int> nextSequences = {};
    for (final String line0 in lines) {
      final String line = line0.toUpperCase();
      if (!RegExp(r'^[0-9A-F]+$').hasMatch(line)) {
        continue;
      }
      final bool kwpFrame =
          protocol == ProtocolFamily.kwp || line.startsWith('86F1');
      final bool responseStartsWithoutHeader = RegExp(
        r'^(41|42|43|47|49|4A|61|62|7F)',
      ).hasMatch(line);
      final bool headers =
          protocol != ProtocolFamily.unknown &&
          !responseStartsWithoutHeader &&
          ((protocol == ProtocolFamily.can29 && line.length >= 16) ||
              (kwpFrame && line.length >= 10) ||
              (protocol == ProtocolFamily.can11 && line.length >= 8));
      if (!headers) {
        if (line.length.isOdd) {
          continue;
        }
        result.add(EcuMessage(ecu: '?', data: _bytes(line)));
        continue;
      }
      final int headLength = kwpFrame
          ? 0
          : protocol == ProtocolFamily.can29
          ? 8
          : 3;
      final String ecu = kwpFrame
          ? '?'
          : protocol == ProtocolFamily.can29
          ? line.substring(4, 8)
          : line.substring(0, 3);
      final List<int> bytes = _bytes(line.substring(headLength));
      if (bytes.isEmpty) {
        continue;
      }
      final int type = bytes[0] >> 4;
      if (kwpFrame) {
        if (bytes.length < 5) {
          continue;
        }
        final List<int> body = bytes.sublist(3, bytes.length - 1);
        final int sum = bytes
            .sublist(0, bytes.length - 1)
            .fold(0, (int a, int b) => (a + b) & 255);
        if (sum == bytes.last) {
          result.add(
            EcuMessage(
              ecu: bytes[2].toRadixString(16).padLeft(2, '0').toUpperCase(),
              data: body,
            ),
          );
        } else {
          log?.add(
            Direction.rx,
            'Checksum KWP inválido, línea descartada: $line',
          );
        }
      } else if (type == 0) {
        final int size = bytes[0] & 15;
        if (bytes.length >= size + 1) {
          result.add(EcuMessage(ecu: ecu, data: bytes.sublist(1, size + 1)));
        }
      } else if (type == 1 && bytes.length >= 2) {
        final int size = ((bytes[0] & 15) << 8) | bytes[1];
        expectedLengths[ecu] = size;
        final List<int> initialData = bytes.sublist(2).take(size).toList();
        firstFrames[ecu] = initialData;
        consecutiveFrames[ecu] = {};
        nextSequences[ecu] = 1;
        if (initialData.length >= size) {
          result.add(
            EcuMessage(ecu: ecu, data: initialData.take(size).toList()),
          );
          firstFrames.remove(ecu);
          expectedLengths.remove(ecu);
          consecutiveFrames.remove(ecu);
        }
      } else if (type == 2 && firstFrames.containsKey(ecu)) {
        final int sequence = bytes[0] & 0x0f;
        final Map<int, List<int>> frames = consecutiveFrames[ecu] ?? {};
        frames[sequence] = bytes.sublist(1);
        final List<int> assembled = firstFrames[ecu] ?? <int>[];
        final int expected = expectedLengths[ecu] ?? assembled.length;
        // ISO-TP sequence numbers run 1..F then wrap to 0; resume from the
        // next one still missing for this ECU.
        int nextSequence = nextSequences[ecu] ?? 1;
        while (assembled.length < expected &&
            frames.containsKey(nextSequence)) {
          final List<int>? chunk = frames.remove(nextSequence);
          if (chunk == null) {
            break;
          }
          assembled.addAll(chunk);
          nextSequence = (nextSequence + 1) & 0x0f;
        }
        nextSequences[ecu] = nextSequence;
        if (assembled.length >= expected) {
          result.add(
            EcuMessage(ecu: ecu, data: assembled.take(expected).toList()),
          );
          firstFrames.remove(ecu);
          expectedLengths.remove(ecu);
          consecutiveFrames.remove(ecu);
        }
      }
    }
    return result.isEmpty
        ? ElmResponse.text(joined, raw: raw)
        : ElmResponse.messages(result, raw: raw);
  }

  List<int> _bytes(String value) => [
    for (int i = 0; i + 1 < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];
}
