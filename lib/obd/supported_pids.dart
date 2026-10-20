final class SupportedPids {
  SupportedPids(Iterable<int> pids) : pids = Set.unmodifiable(pids);
  final Set<int> pids;
  factory SupportedPids.fromMask(int base, List<int> bytes) {
    final Set<int> found = {};
    for (int i = 0; i < 32 && i < bytes.length * 8; i++) {
      if ((bytes[i ~/ 8] & (1 << (7 - i % 8))) != 0) {
        found.add(base + i + 1);
      }
    }
    return SupportedPids(found);
  }
  bool contains(int pid) => pids.contains(pid);
  int? nextBase(int base) => contains(base + 32) ? base + 32 : null;
}
