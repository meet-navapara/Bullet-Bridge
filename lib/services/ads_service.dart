import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';
import '../config/balance.dart';

/// Optional AdMob integration.
///
/// Rules this class enforces:
/// * consent is gathered (UMP) before any ad request;
/// * a rewarded ad reports success only if the SDK's earned-reward callback
///   fired, and each ad can report success at most once;
/// * failures, no-fill and timeouts simply mean "no ad" and never block play.
class AdsService {
  AdsService({bool? enabled}) : _enabled = enabled ?? AdConfig.enabled;

  /// A service that never loads ads (tests, unsupported platforms).
  AdsService.disabled() : _enabled = false;

  final bool _enabled;
  bool _canRequestAds = false;
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  bool _loadingRewarded = false;
  bool _loadingInterstitial = false;
  bool _showing = false;
  DateTime? _lastInterstitial;

  /// True when a rewarded ad is loaded and can be offered to the player.
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false);

  bool get enabled => _enabled && _canRequestAds;

  Future<void> initialize() async {
    if (!_enabled) return;
    // Consent from an earlier session is good for this one, so returning
    // players get ads even if the update below is slow or fails.
    await _startAdsIfAllowed();
    await _gatherConsent();
    await _startAdsIfAllowed();
  }

  Future<void> _startAdsIfAllowed() async {
    if (_canRequestAds) return;
    try {
      if (!await ConsentInformation.instance.canRequestAds()) return;
      _canRequestAds = true;
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          maxAdContentRating: MaxAdContentRating.pg,
          ageRestrictedTreatment: AdConfig.childDirected
              ? AgeRestrictedTreatment.child
              : AgeRestrictedTreatment.unspecified,
        ),
      );
      _loadRewarded();
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
      _canRequestAds = false;
    }
  }

  /// Completes when the player has dismissed the consent form, however long
  /// they take, so this must not have a timeout. Nothing waits on it.
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (error != null) debugPrint('Consent form: ${error.message}');
          });
        } catch (e) {
          debugPrint('Consent form failed: $e');
        }
        if (!done.isCompleted) done.complete();
      },
      (error) {
        debugPrint('Consent info update failed: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  Future<bool> isPrivacyOptionsRequired() async {
    if (!_enabled) return false;
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) debugPrint('Privacy options: ${error.message}');
      });
      await _startAdsIfAllowed();
    } catch (e) {
      debugPrint('Privacy options failed: $e');
    }
  }

  void _loadRewarded() {
    final unit = AdConfig.rewardedUnitId;
    if (!enabled || unit == null || _loadingRewarded || _rewarded != null) {
      return;
    }
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
          rewardedReady.value = false;
          debugPrint('Rewarded failed to load: ${error.message}');
          // Retry later rather than hammering the network.
          Timer(const Duration(seconds: 45), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    final unit = AdConfig.interstitialUnitId;
    if (!enabled || unit == null || _loadingInterstitial) return;
    if (_interstitial != null) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          debugPrint('Interstitial failed to load: ${error.message}');
          Timer(const Duration(seconds: 60), _loadInterstitial);
        },
      ),
    );
  }

  /// Shows a rewarded ad. Completes with true only if the player earned the
  /// reward; the caller grants it. Never throws.
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null || _showing) return false;
    _rewarded = null;
    rewardedReady.value = false;
    _showing = true;
    final result = Completer<bool>();
    var earned = false;
    void finish() {
      _showing = false;
      if (!result.isCompleted) result.complete(earned);
      ad.dispose();
      _loadRewarded();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, error) {
        debugPrint('Rewarded failed to show: ${error.message}');
        earned = false;
        finish();
      },
    );
    try {
      await ad.show(
        onUserEarnedReward: (_, _) {
          earned = true;
        },
      );
    } catch (e) {
      debugPrint('Rewarded show error: $e');
      finish();
    }
    return result.future;
  }

  /// Shows an interstitial at a natural break if frequency limits allow.
  /// Completes when the ad is gone (or immediately when none is shown).
  Future<bool> maybeShowInterstitial({
    required int gamesSinceLast,
    required Duration lastRunLength,
  }) async {
    final ad = _interstitial;
    if (ad == null || _showing) return false;
    if (gamesSinceLast < AdSpec.gamesBetweenInterstitials) return false;
    if (lastRunLength < AdSpec.minRunForInterstitial) return false;
    final last = _lastInterstitial;
    if (last != null &&
        DateTime.now().difference(last) < AdSpec.minTimeBetweenInterstitials) {
      return false;
    }
    _interstitial = null;
    _showing = true;
    final done = Completer<bool>();
    void finish(bool shown) {
      _showing = false;
      if (shown) _lastInterstitial = DateTime.now();
      if (!done.isCompleted) done.complete(shown);
      ad.dispose();
      _loadInterstitial();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(true),
      onAdFailedToShowFullScreenContent: (_, _) => finish(false),
    );
    try {
      await ad.show();
    } catch (_) {
      finish(false);
    }
    return done.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
  }

  void dispose() {
    _rewarded?.dispose();
    _interstitial?.dispose();
    rewardedReady.dispose();
  }
}
