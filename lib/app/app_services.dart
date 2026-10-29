import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../progress/player_progress.dart';
import '../progress/save_repository.dart';
import '../services/ads_service.dart';
import '../services/analytics_service.dart';
import '../services/audio_service.dart';
import '../services/cloud/cloud_sync.dart';
import '../services/cloud/firebase_cloud_backend.dart';
import '../services/firebase_setup.dart';
import '../services/haptics_service.dart';

/// Long-lived services shared by every screen.
class AppServices with WidgetsBindingObserver {
  AppServices({
    required this.progress,
    required this.audio,
    required this.haptics,
    required this.ads,
    required this.version,
    this.storageWarning = false,
    CloudSync? cloud,
    AnalyticsService? analytics,
  }) : cloud = cloud ?? CloudSync.disabled(progress: progress),
       analytics = analytics ?? AnalyticsService.disabled() {
    progress.addListener(_syncSettings);
    _syncSettings();
  }

  final PlayerProgress progress;
  final AudioService audio;
  final HapticsService haptics;
  final AdsService ads;
  final String version;

  /// Cloud save (Firebase). Disabled when Firebase is not configured.
  final CloudSync cloud;
  final AnalyticsService analytics;
  bool? _shareUsage;

  /// True when persistent storage was unavailable and progress is kept in
  /// memory only for this session.
  final bool storageWarning;

  /// Loads everything needed before the main menu. Never hangs: each step
  /// has a timeout and falls back to a safe default.
  static Future<AppServices> bootstrap({
    Future<String> Function()? versionLoader,
    bool enableAudio = true,
    bool enableAds = true,
    bool enableFirebase = true,
  }) async {
    var storageWarning = false;
    KeyValueStore store;
    try {
      store = await SharedPreferencesStore.create().timeout(
        AppConfig.initTimeout,
      );
    } catch (_) {
      store = InMemoryStore();
      storageWarning = true;
    }
    final repository = SaveRepository(store);
    final loaded = await repository.load();
    final progress = PlayerProgress(repository, loaded.data);

    final audio = enableAudio ? AudioService() : AudioService.silent();
    unawaited(
      audio
          .init(loaded.data.settings)
          .timeout(const Duration(seconds: 5), onTimeout: () {}),
    );

    var version = '1.0.0';
    if (versionLoader != null) {
      try {
        version = await versionLoader().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    // Firebase starts in well under a second when configured and fails at
    // once when it is not; the 3 s cap guards against a stuck start. The
    // first cloud sync then runs in the background.
    final firebase = enableFirebase
        ? await FirebaseSetup.init(timeout: const Duration(seconds: 3))
        : false;
    final services = AppServices(
      progress: progress,
      audio: audio,
      haptics: HapticsService(),
      ads: enableAds ? AdsService() : AdsService.disabled(),
      version: version,
      storageWarning: storageWarning,
      cloud: firebase
          ? CloudSync(
              backend: FirebaseCloudBackend(
                appVersion: version,
                platform: defaultTargetPlatform.name,
              ),
              progress: progress,
            )
          : null,
      analytics: firebase
          ? AnalyticsService.firebase()
          : AnalyticsService.disabled(),
    );
    WidgetsBinding.instance.addObserver(services);
    unawaited(services.cloud.start());
    // Consent + ad loading happen in the background; play never waits.
    unawaited(services.ads.initialize());
    return services;
  }

  void _syncSettings() {
    final settings = progress.data.settings;
    audio.applySettings(settings);
    haptics.enabled = settings.vibration;
    if (_shareUsage != settings.shareUsageData) {
      _shareUsage = settings.shareUsageData;
      unawaited(analytics.setEnabled(settings.shareUsageData));
      unawaited(FirebaseSetup.setCrashReporting(settings.shareUsageData));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      audio.resume();
    } else {
      audio.suspend();
      // Upload unsent progress before the system may kill the app.
      if (state == AppLifecycleState.paused) unawaited(cloud.flush());
    }
  }
}

/// Makes [AppServices] available to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above $context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
