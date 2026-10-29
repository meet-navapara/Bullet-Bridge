import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Gameplay analytics. [AnalyticsService.disabled] (tests, builds without
/// Firebase) does nothing. Every call is fire-and-forget and never throws.
/// No personal data is sent: only level numbers, results and item ids.
class AnalyticsService {
  AnalyticsService.firebase() : _fa = FirebaseAnalytics.instance;
  AnalyticsService.disabled() : _fa = null;

  final FirebaseAnalytics? _fa;
  bool _enabled = true;

  bool get available => _fa != null;

  /// Follows the player's "share usage data" setting.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.setAnalyticsCollectionEnabled(enabled);
    } catch (e) {
      debugPrint('analytics: $e');
    }
  }

  void _log(String name, Map<String, Object> params) {
    final fa = _fa;
    if (fa == null || !_enabled) return;
    fa.logEvent(name: name, parameters: params).catchError((Object e) {
      debugPrint('analytics: $e');
    });
  }

  void levelStart(int level) {
    final fa = _fa;
    if (fa == null || !_enabled) return;
    fa.logLevelStart(levelName: 'level_$level').catchError((Object _) {});
  }

  void levelEnd({
    required int level,
    required bool cleared,
    required int stars,
    required int seconds,
    required int score,
  }) {
    final fa = _fa;
    if (fa == null || !_enabled) return;
    fa
        .logLevelEnd(
          levelName: 'level_$level',
          success: cleared ? 1 : 0,
          parameters: {'stars': stars, 'seconds': seconds, 'score': score},
        )
        .catchError((Object _) {});
  }

  void bossDefeated(int level, String boss) =>
      _log('boss_defeated', {'level': level, 'boss': boss});

  void chapterComplete(int chapter) =>
      _log('chapter_complete', {'chapter': chapter});

  void endlessEnd({required int wave, required int score}) =>
      _log('endless_end', {'wave': wave, 'score': score});

  void upgradeBought(String upgrade, int level) =>
      _log('upgrade_bought', {'upgrade': upgrade, 'level': level});

  void cloudLinked() => _log('cloud_linked', const {});
}
