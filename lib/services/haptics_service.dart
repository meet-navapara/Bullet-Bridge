import 'package:flutter/services.dart';

enum Haptic { light, medium, heavy, selection }

/// Thin wrapper over the platform haptics that respects the vibration
/// setting and rate-limits light feedback.
class HapticsService {
  bool enabled = true;
  int _lastLightMs = 0;

  void trigger(Haptic kind) {
    if (!enabled) return;
    try {
      switch (kind) {
        case Haptic.light:
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastLightMs < 80) return;
          _lastLightMs = now;
          HapticFeedback.lightImpact();
        case Haptic.medium:
          HapticFeedback.mediumImpact();
        case Haptic.heavy:
          HapticFeedback.heavyImpact();
        case Haptic.selection:
          HapticFeedback.selectionClick();
      }
    } catch (_) {
      // Haptics are optional.
    }
  }
}
