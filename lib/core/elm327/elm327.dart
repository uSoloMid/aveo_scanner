import 'dart:async';
import 'dart:convert';

import 'package:aveo_scanner/core/elm327/query_metric.dart';

import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/core/transport/transport.dart';
import 'package:aveo_scanner/core/elm327/elm_response.dart';
import 'package:aveo_scanner/core/elm327/response_parser.dart';
import 'package:aveo_scanner/core/elm327/traffic_log.dart';

typedef Clock = DateTime Function();

class Elm327 {
  Elm327(
    this.transport, {
    TrafficLog? log,
    Clock? clock,
    Future<void> Function(Duration)? delay,
    Duration latePromptTimeout = const Duration(seconds: 2),
  }) : log = log ?? TrafficLog(),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       // ignore: prefer_initializing_formals
       _latePromptTimeout = latePromptTimeout {
    _parser = ResponseParser(log: this.log);
    _subscription = transport.incoming.listen(
      _onData,
      onError: (Object error) {
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error);
        }
      },
    );
  }
  final Transport transport;
  int preferredAdaptive = 1;
  String preferredTimeoutHex = '32';
  Duration minimumGap = const Duration(milliseconds: 50);
  final StreamController<QueryMetric> _metrics = StreamController.broadcast();
  Stream<QueryMetric> get metrics => _metrics.stream;
  int queued = 0;
  int get pendingQueries => queued;

  final TrafficLog log;
  final Clock _clock;
  final Future<void> Function(Duration) _delay;
  final Duration _latePromptTimeout;
  late final ResponseParser _parser;
  late final StreamSubscription<List<int>> _subscription;
  Completer<String>? _pending;
  Completer<void>? _lateDrain;
  Timer? _timeoutTimer;
  int _pendingCount = 0;
  String _responseParts = '';
  String _buffer = '';
  Stopwatch? _wireWatch;
  double? _firstByteMs;
  double _wireMs = 0, _parseMs = 0;
  bool _discardLate = false;
  DateTime? _lastEnd;
  Future<void> _tail = Future<void>.value();
  ProtocolFamily protocolFamily = ProtocolFamily.can11;
  void _onData(List<int> bytes) {
    if (bytes.isNotEmpty && _pending != null && _firstByteMs == null) {
      _firstByteMs = (_wireWatch?.elapsedMicroseconds ?? 0) / 1000;
    }
    for (final int byte in bytes) {
      final String char = String.fromCharCode(byte);
      if (_discardLate) {
        if (char == '>') {
          _discardLate = false;
          final Completer<void>? drain = _lateDrain;
          if (drain != null && !drain.isCompleted) {
            drain.complete();
          }
        }
        continue;
      }
      if (char == '>') {
        final String frame = _buffer;
        if (RegExp(
              r'7F\s*[0-9A-F]{2}\s*78',
              caseSensitive: false,
            ).hasMatch(frame) &&
            _pendingCount < 3) {
          _responseParts += '$frame\r';
          _pendingCount++;
          _buffer = '';
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: 5), _timeoutPending);
          continue;
        }
        final Completer<String>? c = _pending;
        if (c != null && !c.isCompleted) {
          c.complete('$_responseParts$frame');
        }
        _timeoutTimer?.cancel();
        _buffer = '';
      } else {
        _buffer += char;
        if (_buffer.length > 65536) {
          final pending = _pending;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(
              StateError('Respuesta del adaptador demasiado larga'),
            );
          }
          _buffer = '';
          _discardLate = true;
          _lateDrain = Completer<void>();
        }
      }
    }
  }

  void _timeoutPending() {
    final Completer<String>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(TimeoutException('ELM327 timeout'));
    }
  }

  Future<ElmResponse> send(
    String cmd, {
    Duration timeout = const Duration(seconds: 2),
    Confirmation? confirmation,
  }) {
    final GuardResult check = CommandGuard.check(cmd);
    log.add(Direction.guard, '${check.normalized}: ${check.reason}');
    if (check.verdict == GuardVerdict.blocked) {
      return Future.error(CommandBlockedException(check));
    }
    if (check.verdict == GuardVerdict.needsConfirmation &&
        confirmation?.command != check.normalized) {
      return Future.error(ConfirmationRequiredException(check));
    }
    final Completer<ElmResponse> result = Completer<ElmResponse>();
    if (queued >= 32) {
      return Future.error(StateError('Cola de consultas llena'));
    }
    queued++;
    final queuedAt = Stopwatch()..start();
    _tail = _tail.then((_) async {
      try {
        final queueMs = queuedAt.elapsedMicroseconds / 1000;
        final watch = Stopwatch()..start();
        try {
          final response = await _send(check.normalized, timeout);
          _metrics.add(
            QueryMetric(
              command: check.normalized,
              at: _clock(),
              queueMs: queueMs,
              elapsedMs: watch.elapsedMicroseconds / 1000,
              raw: response.raw,
              firstByteMs: _firstByteMs,
              wireMs: _wireMs,
              parseMs: _parseMs,
              error:
                  response.error?.name ??
                  (response.isNegative
                      ? 'negative_${response.negativeCode}'
                      : null),
            ),
          );
          result.complete(response);
        } on Object catch (e) {
          _metrics.add(
            QueryMetric(
              command: check.normalized,
              at: _clock(),
              queueMs: queueMs,
              elapsedMs: watch.elapsedMicroseconds / 1000,
              raw: '',
              error: e.runtimeType.toString(),
            ),
          );
          rethrow;
        }
      } on Object catch (e, st) {
        result.completeError(e, st);
      } finally {
        queued--;
      }
    });
    return result.future;
  }

  Future<ElmResponse> _send(String command, Duration timeout) async {
    final Completer<void>? lateDrain = _lateDrain;
    if (_discardLate && lateDrain != null) {
      try {
        await lateDrain.future.timeout(_latePromptTimeout);
      } on TimeoutException {
        _discardLate = false;
        _lateDrain = null;
        _buffer = '';
      }
    }
    final DateTime? lastEnd = _lastEnd;
    if (lastEnd != null) {
      final Duration elapsed = _clock().difference(lastEnd);
      if (elapsed < minimumGap) {
        await _delay(minimumGap - elapsed);
      }
    }
    _buffer = '';
    _responseParts = '';
    _pendingCount = 0;
    _pending = Completer<String>();
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, _timeoutPending);
    log.add(Direction.tx, command);
    _firstByteMs = null;
    _wireMs = 0;
    _parseMs = 0;
    _wireWatch = Stopwatch()..start();
    try {
      await transport.write(ascii.encode('$command\r'));
    } on Object {
      _timeoutTimer?.cancel();
      _pending = null;
      rethrow;
    }
    String raw;
    try {
      final Completer<String>? pending = _pending;
      if (pending == null) {
        throw StateError('No hay una respuesta pendiente para el comando.');
      }
      raw = await pending.future;
    } on TimeoutException {
      _discardLate = true;
      _lateDrain = Completer<void>();
      _timeoutTimer?.cancel();
      _pending = null;
      _lastEnd = _clock();
      throw const ElmTimeoutException();
    } on Object {
      _timeoutTimer?.cancel();
      _pending = null;
      _lastEnd = _clock();
      rethrow;
    }
    _pending = null;
    _timeoutTimer?.cancel();
    _lastEnd = _clock();
    log.add(Direction.rx, raw);
    _wireMs = _wireWatch!.elapsedMicroseconds / 1000;
    final parseWatch = Stopwatch()..start();
    final parsed = _parser.parse(
      raw,
      protocol: protocolFamily,
      command: command,
    );
    _parseMs = parseWatch.elapsedMicroseconds / 1000;
    return parsed;
  }

  Future<ElmInfo> initialize() async {
    final ElmResponse reset = await send(
      'ATZ',
      timeout: const Duration(seconds: 3),
    );
    _requireInitSuccess(reset, 'ATZ');
    await _delay(const Duration(seconds: 1));
    _requireInitSuccess(await send('ATE0'), 'ATE0');
    await _sendOptional('ATL0');
    await _sendOptional('ATS0');
    _requireInitSuccess(await send('ATH1'), 'ATH1');
    await _sendOptional('ATST$preferredTimeoutHex');
    await _sendOptional('ATAT$preferredAdaptive');
    _requireInitSuccess(await send('ATSP0'), 'ATSP0');
    final ElmResponse version = await send('ATI');
    ElmResponse supported = await send(
      '0100',
      timeout: const Duration(seconds: 6),
    );
    // On the Aveo's K-Line the first slow/fast init often fails with
    // "BUS INIT: ERROR" and succeeds on the second try (seen 2026-10-22).
    for (
      int attempt = 0;
      attempt < 2 &&
          supported.error == null &&
          !supported.raw.replaceAll(RegExp(r'\s'), '').contains('4100');
      attempt++
    ) {
      supported = await send('0100', timeout: const Duration(seconds: 6));
    }
    if (supported.error == ElmError.unableToConnect) {
      throw const ElmInitException('¿Está el contacto encendido?');
    }
    final ElmResponse proto = await send('ATDPN');
    final String code = (proto.text ?? '').replaceFirst('A', '');
    protocolFamily = switch (code) {
      '3' || '4' || '5' => ProtocolFamily.kwp,
      '7' || '9' => ProtocolFamily.can29,
      '6' || '8' => ProtocolFamily.can11,
      _ => ProtocolFamily.unknown,
    };
    final ElmResponse parsedSupported = _parser.parse(
      supported.raw,
      protocol: protocolFamily,
      command: '0100',
    );
    _requireInitSuccess(parsedSupported, '0100');
    if (parsedSupported.messages.isEmpty) {
      throw const ElmInitException(
        'El adaptador responde, pero no hay datos de la ECU.',
      );
    }
    final ElmResponse voltage = await send('ATRV');
    return ElmInfo(
      version: version.text ?? reset.text ?? '',
      protocolCode: code,
      protocolName: _protocolName(code),
      voltage: double.tryParse((voltage.text ?? '').replaceAll('V', '')) ?? 0,
      supportedPids: parsedSupported.messages,
    );
  }

  Future<void> _sendOptional(String command) async {
    final ElmResponse response = await send(command);
    if (response.error == ElmError.unknownCommand ||
        response.text?.trim() == '?') {
      log.add(
        Direction.guard,
        '$command: respuesta ? ignorada durante inicialización',
      );
    }
  }

  void _requireInitSuccess(ElmResponse response, String command) {
    if (response.error != null || response.text?.trim() == '?') {
      throw ElmInitException(
        'Falló el comando de inicialización $command: ${response.error}',
      );
    }
  }

  String _protocolName(String code) =>
      const {
        '1': 'J1850 PWM',
        '2': 'J1850 VPW',
        '3': 'ISO 9141-2',
        '4': 'ISO 14230 (5 baud)',
        '5': 'ISO 14230 (rápido)',
        '6': 'CAN 11b 500k',
        '7': 'CAN 29b 500k',
        '8': 'CAN 11b 250k',
        '9': 'CAN 29b 250k',
      }[code] ??
      'Desconocido';
  Future<void> close() async {
    _timeoutTimer?.cancel();
    await _subscription.cancel();
    await _metrics.close();
    await transport.disconnect();
  }
}
