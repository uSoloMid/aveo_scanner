import 'package:flutter_test/flutter_test.dart';
import 'package:aveo_scanner/core/elm327/traffic_log.dart';

void main() {
  test('keeps the newest 500 entries and broadcasts changes', () async {
    final TrafficLog log = TrafficLog(now: () => DateTime.utc(2026));
    final List<List<TrafficEntry>> events = [];
    final subscription = log.changes.listen(events.add);
    for (int i = 0; i < 505; i++) {
      log.add(Direction.tx, '$i');
    }
    await Future<void>.delayed(Duration.zero);
    expect(log.entries, hasLength(500));
    expect(log.entries.first.text, '5');
    expect(events, isNotEmpty);
    await subscription.cancel();
    await log.close();
  });
}
