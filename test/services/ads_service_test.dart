import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ump/user_messaging_channel.dart';
import 'package:orbit_blast/services/ads_service.dart';

class _FakeConsent implements ConsentInformation {
  bool allowed = false;
  bool updateCalled = false;

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    OnConsentInfoUpdateSuccessListener successListener,
    OnConsentInfoUpdateFailureListener failureListener,
  ) {
    updateCalled = true;
    successListener();
  }

  @override
  Future<bool> canRequestAds() async => allowed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChannel extends UserMessagingChannel {
  _FakeChannel() : super(const MethodChannel('unused'));

  // Late: it must be created inside the test's fake-async zone, not in setUp.
  late final form = Completer<FormError?>();

  @override
  Future<FormError?> loadAndShowConsentFormIfRequired() => form.future;
}

void main() {
  late _FakeConsent consent;
  late _FakeChannel channel;
  late int sdkStarts;
  final originalConsent = ConsentInformation.instance;
  final originalChannel = UserMessagingChannel.instance;
  const adsChannel = 'plugins.flutter.io/google_mobile_ads';

  setUp(() {
    consent = _FakeConsent();
    channel = _FakeChannel();
    sdkStarts = 0;
    ConsentInformation.instance = consent;
    UserMessagingChannel.instance = channel;
  });

  void listenForSdkStart(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(adsChannel, (
      message,
    ) async {
      const codec = StandardMethodCodec();
      final call = codec.decodeMethodCall(message);
      if (call.method == 'MobileAds#initialize') sdkStarts++;
      return codec.encodeSuccessEnvelope(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        adsChannel,
        null,
      ),
    );
  }

  tearDown(() {
    ConsentInformation.instance = originalConsent;
    UserMessagingChannel.instance = originalChannel;
  });

  testWidgets('ads start after a consent form that took a long time', (
    tester,
  ) async {
    listenForSdkStart(tester);
    final ads = AdsService(enabled: true);
    unawaited(ads.initialize());

    await tester.pump(const Duration(minutes: 1));
    expect(sdkStarts, 0, reason: 'no ad SDK before the player has answered');

    consent.allowed = true;
    channel.form.complete(null);
    await tester.pump();
    expect(sdkStarts, 1);
  });

  testWidgets('consent from an earlier session starts ads straight away', (
    tester,
  ) async {
    listenForSdkStart(tester);
    consent.allowed = true;
    final ads = AdsService(enabled: true);
    unawaited(ads.initialize());
    await tester.pump();

    expect(sdkStarts, 1);
    expect(consent.updateCalled, isTrue, reason: 'consent is still refreshed');
  });

  testWidgets('a disabled service never touches consent or the SDK', (
    tester,
  ) async {
    listenForSdkStart(tester);
    await AdsService.disabled().initialize();
    await tester.pump();

    expect(sdkStarts, 0);
    expect(consent.updateCalled, isFalse);
  });
}
