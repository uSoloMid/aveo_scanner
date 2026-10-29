import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aveo_scanner/core/safety/command_guard.dart';
import 'package:aveo_scanner/core/transport/transport.dart';

final class MockTransport implements Transport {
  MockTransport({
    this.kwp = false,
    Duration Function()? latency,
    Random? random,
    this.engineRunning = false,
    this.noRpmData = false,
  }) : _random = random ?? Random(1) {
    _latency =
        latency ?? (() => Duration(milliseconds: 30 + _random.nextInt(51)));
  }
  final bool kwp, engineRunning, noRpmData;
  late final Duration Function() _latency;
  final Random _random;
  final StreamController<List<int>> _input = StreamController.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states = StreamController.broadcast(
    sync: true,
  );
  bool _connected = false;
  final List<String> writtenCommands = [];
  bool echo = true, spaces = true, headers = false, autoProtocol = false;
  bool _searched = false, _confirmedCodes = true, _pendingCodes = true;
  final DateTime _started = DateTime.now();
  @override
  String get label => 'mock';
  @override
  bool get isConnected => _connected;
  @override
  Stream<List<int>> get incoming => _input.stream;
  @override
  Stream<TransportState> get state => _states.stream;
  @override
  Future<void> connect() async {
    _connected = true;
    _states.add(TransportState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _states.add(TransportState.disconnected);
  }

  @override
  Future<void> write(List<int> bytes) async {
    final String cmd = ascii.decode(bytes).trim().toUpperCase();
    writtenCommands.add(cmd);
    if (CommandGuard.check(cmd).verdict == GuardVerdict.blocked) {
      assert(false, 'MockTransport received a command blocked by CommandGuard');
      _emit('?\r\r>');
      return;
    }
    if (!_connected) {
      throw const TransportException('No conectado');
    }
    await Future<void>.delayed(_latency());
    if (echo) {
      _emit('$cmd\r');
    }
    if (cmd.startsWith('AT')) {
      if (cmd == 'ATZ') {
        echo = true;
        spaces = true;
        headers = false;
        autoProtocol = false;
        _searched = false;
      }
      if (cmd == 'ATE0') {
        echo = false;
      }
      if (cmd == 'ATS0') {
        spaces = false;
      }
      if (cmd == 'ATH1') {
        headers = true;
      }
      if (cmd == 'ATSP0') {
        autoProtocol = true;
        _searched = false;
      }
      const Set<String> knownAt = {
        'ATZ',
        'ATI',
        'ATRV',
        'ATDPN',
        'ATE0',
        'ATL0',
        'ATS0',
        'ATH1',
        'ATAT1',
        'ATSP0',
        'ATWS',
      };
      final String answer = switch (cmd) {
        'ATZ' => 'ELM327 v1.5',
        'ATI' => 'ELM327 v1.5',
        'ATRV' => engineRunning ? '13.9V' : '12.4V',
        'ATDPN' => kwp ? 'A5' : 'A6',
        'ATSP0' => 'OK',
        _ when knownAt.contains(cmd) => 'OK',
        _ => '?',
      };
      _emit('$answer\r\r>');
      return;
    }
    if (cmd == '010C' && noRpmData) {
      _emit('NO DATA\r\r>');
      return;
    }
    if (autoProtocol && !_searched) {
      _searched = true;
      _emit('SEARCHING...\r');
    }
    if (cmd.startsWith('04')) {
      _confirmedCodes = false;
      _pendingCodes = false;
      _respond([0x44]);
      return;
    }
    if (cmd == '0202') {
      _respond([0x42, 0x02, 0x00, 0x03, 0x00]);
      return;
    }
    if (cmd == '0200') {
      _respond([0x42, 0x00, 0xBE, 0x3E, 0xB8, 0x11]);
      return;
    }
    if (cmd.startsWith('02') && cmd.endsWith('00')) {
      final int pid = int.parse(cmd.substring(2, 4), radix: 16);
      final List<int> value = switch (pid) {
        12 => [0x05, 0xDC],
        13 => [0x00],
        5 => [0x5A],
        _ => [],
      };
      if (value.isEmpty) {
        _emit('NO DATA\r\r>');
      } else {
        _respond([0x42, pid, 0x00, ...value]);
      }
      return;
    }
    if (cmd == '0100' || cmd == '0120' || cmd == '0140') {
      final List<int> mask = switch (cmd) {
        '0100' => [0xBE, 0x3E, 0xB8, 0x11],
        '0120' => [0x00, 0x02, 0x20, 0x01],
        _ => [0x40, 0x00, 0x00, 0x00],
      };
      _respond([0x41, int.parse(cmd.substring(2, 4), radix: 16), ...mask]);
      return;
    }
    if (cmd == '0902') {
      _respond([0x49, 0x02, 0x01, ...ascii.encode('KL1TD5DE5CB000000')]);
      return;
    }
    if (cmd == '0904') {
      _respond([0x49, 0x04, 0x01, ...ascii.encode('12345678ABCDEF')]);
      return;
    }
    if (cmd == '0906') {
      _respond([0x49, 0x06, 0x01, 1, 2, 3, 4]);
      return;
    }
    if (cmd == '03' || cmd == '07' || cmd == '0A') {
      final List<int> dtcs = cmd == '03'
          ? [
              0x43,
              _confirmedCodes ? 2 : 0,
              if (_confirmedCodes) ...[0x01, 0x33, 0x03, 0x00],
            ]
          : cmd == '07'
          ? [
              0x47,
              _pendingCodes ? 1 : 0,
              if (_pendingCodes) ...[0x01, 0x71],
            ]
          : [0x4A, 1, 0x01, 0x33];
      _respond(dtcs);
      return;
    }
    if (cmd == '22000D') {
      _respond([0x62, 0x00, 0x0D, 0x32]);
      return;
    }
    if (cmd == '221192') {
      // Desired idle: 0x42 * 12.5 = 825 rpm.
      _respond([0x62, 0x11, 0x92, 0x42]);
      return;
    }
    if (cmd == '221170') {
      _respond([0x62, 0x11, 0x70, 0x27]);
      return;
    }
    if (cmd == '221172') {
      _respond([0x62, 0x11, 0x72, engineRunning ? 0x2F : 0x3D]);
      return;
    }
    if (cmd == '2211A1') {
      _respond([0x62, 0x11, 0xA1, 1, 0xFF]);
      return;
    }
    if (cmd.startsWith('01')) {
      final int pid = int.parse(cmd.substring(2, 4), radix: 16);
      final List<int> data = switch (pid) {
        1 => [0x41, pid, 0x00, 0x00, 0x00, 0x00],
        3 => [0x41, pid, 0x02, 0x00],
        69 => [0x41, pid, 0x00],
        20 => [0x41, pid, 0x90, 0xFF],
        21 => [0x41, pid, 0x1C, 0xFF],
        12 => [0x41, pid, ..._word(_rpm() * 4)],
        13 => [0x41, pid, _speed()],
        5 => [
          0x41,
          pid,
          40 + min(50, DateTime.now().difference(_started).inSeconds),
        ],
        6 || 7 => [0x41, pid, 128],
        11 => [0x41, pid, 40],
        14 => [0x41, pid, 128],
        15 => [0x41, pid, 60],
        16 => [0x41, pid, 0x00, 0x64],
        17 => [0x41, pid, 64],
        31 => [0x41, pid, 0x00, 0x10],
        47 => [0x41, pid, 128],
        51 => [0x41, pid, 101],
        66 => [0x41, pid, 0x37, 0x14],
        4 => [0x41, pid, 0x40],
        _ => [],
      };
      if (data.isEmpty) {
        _emit('NO DATA\r\r>');
        return;
      }
      _respond(data);
      return;
    }
    _emit(cmd.startsWith('22') ? '7F2231\r\r>' : '?\r\r>');
  }

  void _respond(List<int> bytes) => _emit('${_frame(bytes)}\r\r>');

  String _frame(List<int> bytes) {
    if (kwp) {
      final List<int> frame = [0x86, 0xF1, 0x10, ...bytes];
      frame.add(
        frame.fold<int>(0, (int total, int byte) => (total + byte) & 0xFF),
      );
      return frame
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
    }
    final String payload = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    if (!headers) {
      return spaces
          ? bytes
                .map((int b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ')
                .toUpperCase()
          : payload;
    }
    const String head = '7E8';
    if (bytes.length <= 7) {
      return '$head${bytes.length.toRadixString(16).padLeft(2, '0')}${spaces ? ' ' : ''}$payload';
    }
    final StringBuffer result = StringBuffer(
      '$head${(0x10 | (bytes.length >> 8)).toRadixString(16)}${(bytes.length & 255).toRadixString(16).padLeft(2, '0')}${bytes.take(6).map((int b) => b.toRadixString(16).padLeft(2, '0')).join()}'
          .toUpperCase(),
    );
    int offset = 6;
    int sequence = 1;
    while (offset < bytes.length) {
      final List<int> chunk = [
        0x20 | (sequence++ & 15),
        ...bytes.skip(offset).take(7),
      ];
      result.write(
        '\r$head${chunk.map((int b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}',
      );
      offset += 7;
    }
    return result.toString();
  }

  void _emit(String value) => _input.add(ascii.encode(value));
  int _rpm() => !engineRunning
      ? 0
      : (750 +
                1125 *
                    (1 +
                        sin(
                          DateTime.now().difference(_started).inMilliseconds /
                              4500,
                        )))
            .round()
            .clamp(750, 3000)
            .toInt();
  int _speed() =>
      (40 *
              (1 +
                  sin(
                    DateTime.now().difference(_started).inMilliseconds / 7000,
                  )))
          .round()
          .clamp(0, 80)
          .toInt();
  List<int> _word(int value) => [(value >> 8) & 0xff, value & 0xff];
}
