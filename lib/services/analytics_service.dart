import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// What players do in the game: screens, button taps and gameplay actions.
/// [AnalyticsService.disabled] (tests, builds without Firebase) does nothing.
/// Every call is fire-and-forget and never throws. No personal data is sent:
/// only screen and button names, level numbers, results and item ids. All of
/// it stops when the player turns off "Share Usage Data".
class AnalyticsService {
  AnalyticsService.firebase() : _fa = FirebaseAnalytics.instance, _sink = null;
  AnalyticsService.disabled() : _fa = null, _sink = null;

  /// Hands events to [sink] instead of Firebase (tests).
  @visibleForTesting
  AnalyticsService.recording(void Function(String, Map<String, Object>) sink)
    : _fa = null,
      _sink = sink;

  final FirebaseAnalytics? _fa;
  final void Function(String, Map<String, Object>)? _sink;
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
    if (!_enabled) return;
    _sink?.call(name, params);
    _fa?.logEvent(name: name, parameters: params).catchError((Object e) {
      debugPrint('analytics: $e');
    });
  }

  void screen(String name) {
    if (!_enabled) return;
    _sink?.call('screen_view', {'screen': name});
    _fa?.logScreenView(screenName: name).catchError((Object _) {});
  }

  void buttonTap(String button) => _log('button_tap', {'button': button});

  void accountChoice(String choice) =>
      _log('account_choice', {'choice': choice});

  void signedOut() => _log('account_signed_out', const {});

  void cloudDeleted() => _log('account_deleted', const {});

  void elementSelected(String element) =>
      _log('element_selected', {'element': element});

  void powerUpUsed(String powerUp) =>
      _log('power_up_used', {'power_up': powerUp});

  /// [placement] says where it was offered: `continue` or `shop`.
  void rewardedAd(String placement, {required bool earned}) =>
      _log('rewarded_ad', {'placement': placement, 'earned': earned ? 1 : 0});

  void interstitialShown() => _log('interstitial_shown', const {});

  void itemBought(String item) => _log('item_bought', {'item': item});

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
