import 'package:flutter/foundation.dart';

/// App-level configuration. Values can be overridden at build time with
/// `--dart-define=KEY=value` so nothing environment-specific is committed.
abstract final class AppConfig {
  /// Display title. Rename the game by passing `--dart-define=APP_TITLE=...`
  /// (and changing the launcher label, see docs/PRODUCTION_SETUP.md).
  static const String title = String.fromEnvironment(
    'APP_TITLE',
    defaultValue: 'BOOMFORGE',
  );

  /// Ribbon under the logo.
  static const String tagline = String.fromEnvironment(
    'APP_TAGLINE',
    defaultValue: 'Break the World',
  );

  /// Title split for the two-line logo ("ORBIT" / "BLAST").
  static List<String> get titleLines {
    final parts = title.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return [title];
    final mid = (parts.length / 2).ceil();
    return [parts.take(mid).join(' '), parts.skip(mid).join(' ')];
  }

  /// The game's website on Firebase Hosting (source in `website/`).
  static const String websiteUrl = String.fromEnvironment(
    'WEBSITE_URL',
    defaultValue: 'https://ball-blast-d0a65.web.app',
  );

  /// Public URLs of the hosted privacy policy, terms and account-deletion
  /// page. If a page cannot be opened, the in-app versions in
  /// `lib/ui/screens/legal_screen.dart` are shown.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: '$websiteUrl/privacy',
  );
  static const String termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: '$websiteUrl/terms',
  );
  static const String deleteAccountUrl = String.fromEnvironment(
    'DELETE_ACCOUNT_URL',
    defaultValue: '$websiteUrl/delete-account',
  );
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  /// Upper bound for the splash screen so the player never waits forever.
  static const Duration initTimeout = Duration(seconds: 8);
}

/// AdMob configuration.
///
/// Debug/profile builds fall back to Google's public test ad units. Release
/// builds show ads only when real unit IDs are supplied via --dart-define;
/// otherwise ads are disabled and the game is fully playable without them.
abstract final class AdConfig {
  static const bool _forceDisabled = bool.fromEnvironment('ADS_DISABLED');

  static const _rewardedAndroid = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
  );
  static const _rewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS');
  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
  );
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
  );

  /// Set to true if the app is directed at children (COPPA / Families).
  static const bool childDirected = bool.fromEnvironment(
    'ADMOB_CHILD_DIRECTED',
  );

  // Google's official sample ad units (always serve test ads).
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  static String? _pick(String android, String ios, String testA, String testI) {
    if (_forceDisabled || !_isMobile) return null;
    final real = _isIos ? ios : android;
    if (real.isNotEmpty) return real;
    return kReleaseMode ? null : (_isIos ? testI : testA);
  }

  static String? get rewardedUnitId => _pick(
    _rewardedAndroid,
    _rewardedIos,
    _testRewardedAndroid,
    _testRewardedIos,
  );

  static String? get interstitialUnitId => _pick(
    _interstitialAndroid,
    _interstitialIos,
    _testInterstitialAndroid,
    _testInterstitialIos,
  );

  static bool get enabled =>
      rewardedUnitId != null || interstitialUnitId != null;

  static bool get usingTestAds =>
      enabled && (_isIos ? _rewardedIos.isEmpty : _rewardedAndroid.isEmpty);
}
