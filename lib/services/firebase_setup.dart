import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Starts Firebase if this build is configured for it.
///
/// Configuration comes from the native files added during setup
/// (android/app/google-services.json, ios/Runner/GoogleService-Info.plist);
/// see docs/FIREBASE_SETUP.md. Without them initialisation fails quickly
/// and the game runs exactly as before with local saves only. This never
/// throws and never waits longer than [timeout].
abstract final class FirebaseSetup {
  static bool _ready = false;
  static bool get ready => _ready;

  static Future<bool> init({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_ready) return true;
    try {
      await Firebase.initializeApp().timeout(timeout);
      // Firestore keeps an offline cache: progress made without a
      // connection is uploaded once the phone is back online.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
      _installCrashReporting();
      _ready = true;
    } catch (e) {
      debugPrint('Firebase not configured, cloud features off: $e');
      _ready = false;
    }
    return _ready;
  }

  static void _installCrashReporting() {
    final crashlytics = FirebaseCrashlytics.instance;
    // Debug builds never report; release builds follow the player's
    // "share usage data" setting (see [setCrashReporting]).
    unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode));
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      crashlytics.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Applies the player's "share usage data" setting to crash reports.
  static Future<void> setCrashReporting(bool enabled) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enabled && !kDebugMode,
      );
    } catch (_) {}
  }
}
