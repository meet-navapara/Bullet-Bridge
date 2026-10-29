import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Optional frame-time logger for measuring gameplay performance on a real
/// device. Off by default; enable with
/// `flutter run --profile --dart-define=PERF_LOG=true` and read the
/// `[perf]` lines in the console / `adb logcat`.
class FrameMonitor {
  static const bool enabled = bool.fromEnvironment('PERF_LOG');

  /// Report window in frames (~5 s at 60 Hz).
  static const int window = 300;

  final List<double> _build = [];
  final List<double> _raster = [];
  bool _attached = false;

  void start() {
    if (!enabled || _attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _build.clear();
    _raster.clear();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    if (_build.length >= window) {
      debugPrint('[perf] ${summarize(_build, _raster)}');
      _build.clear();
      _raster.clear();
    }
  }

  /// One-line summary: frame count, average / p90 / max of UI (build) and
  /// raster times in milliseconds, and frames over the 60 Hz budget.
  static String summarize(List<double> build, List<double> raster) {
    String stats(List<double> v) {
      final s = [...v]..sort();
      final avg = s.reduce((a, b) => a + b) / s.length;
      final p90 = s[math.min(s.length - 1, (s.length * 0.9).floor())];
      return 'avg ${avg.toStringAsFixed(1)} '
          'p90 ${p90.toStringAsFixed(1)} max ${s.last.toStringAsFixed(1)}';
    }

    var slow = 0;
    for (var i = 0; i < build.length; i++) {
      if (math.max(build[i], raster[i]) > 16.7) slow++;
    }
    return 'frames ${build.length} | ui ${stats(build)} | '
        'raster ${stats(raster)} | over16.7ms $slow';
  }
}
