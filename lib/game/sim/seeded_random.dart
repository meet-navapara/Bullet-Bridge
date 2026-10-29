/// Small deterministic PRNG (mulberry32).
///
/// `dart:math`'s `Random(seed)` is not guaranteed to produce the same
/// sequence on every platform/compiler, and the daily challenge must be
/// identical for everyone on the same date, so we use our own generator.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// Next 32-bit unsigned integer.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform integer in [0, max).
  int nextInt(int max) {
    assert(max > 0);
    return (nextDouble() * max).floor();
  }

  bool nextBool() => nextUint32() & 1 == 1;

  double range(double min, double max) => min + (max - min) * nextDouble();

  /// 32-bit multiply that matches JavaScript's Math.imul semantics.
  static int _imul(int a, int b) {
    final aHi = (a >> 16) & 0xFFFF;
    final aLo = a & 0xFFFF;
    final bHi = (b >> 16) & 0xFFFF;
    final bLo = b & 0xFFFF;
    return ((aLo * bLo) + (((aHi * bLo + aLo * bHi) << 16) & 0xFFFFFFFF)) &
        0xFFFFFFFF;
  }

  /// Stable hash of a string (FNV-1a), used to derive seeds from dates.
  static int hashString(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
