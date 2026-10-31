import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/analytics_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/cloud/cloud_backend.dart';
import 'package:orbit_blast/services/cloud/cloud_sync.dart';
import 'package:orbit_blast/services/haptics_service.dart';
import 'package:orbit_blast/ui/screens/settings_screen.dart';
import 'package:orbit_blast/ui/widgets/common.dart';

/// Counts what happens to accounts: guests must never create one.
class FakeCloud implements CloudBackend {
  Map<String, Object?>? doc;
  String? uid;
  int signIns = 0;
  int googleSignIns = 0;
  int pushes = 0;
  bool cancel = false;
  Object? failure;

  @override
  Future<CloudAccount> signIn() async {
    signIns++;
    if (uid == null) throw const CloudFailure('Not signed in.');
    return CloudAccount(uid: uid!, email: 'a@b.c', linked: true);
  }

  @override
  Future<Map<String, Object?>?> fetchSave() async => doc;

  @override
  Future<void> pushSave(Map<String, Object?> save) async {
    pushes++;
    doc = save;
  }

  @override
  Future<CloudAccount> linkGoogle() async {
    googleSignIns++;
    if (cancel) throw const CloudCancelled();
    if (failure != null) throw failure!;
    uid = 'g1';
    return const CloudAccount(uid: 'g1', email: 'a@b.c', linked: true);
  }

  @override
  Future<void> signOut() async => uid = null;

  @override
  Future<void> deleteAccount() async {
    doc = null;
    uid = null;
  }
}

late FakeCloud cloud;
late InMemoryStore store;
late List<(String, Map<String, Object>)> events;

Future<AppServices> services(SaveData save, {bool withCloud = true}) async {
  final progress = PlayerProgress(SaveRepository(store), save);
  return AppServices(
    progress: progress,
    audio: AudioService.silent(),
    haptics: HapticsService(),
    ads: AdsService.disabled(),
    version: 'test',
    cloud: withCloud ? CloudSync(backend: cloud, progress: progress) : null,
    analytics: AnalyticsService.recording((n, p) => events.add((n, p))),
  );
}

Future<AppServices> boot(
  WidgetTester tester, {
  SaveData? save,
  bool withCloud = true,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final s = await services(
    save ?? SaveData(tutorialDone: true),
    withCloud: withCloud,
  );
  await tester.pumpWidget(OrbitBlastApp(bootstrap: () async => s));
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
  return s;
}

const google = 'Continue with Google';
const guest = 'Continue as Guest';

Iterable<String> taps() => events
    .where((e) => e.$1 == 'button_tap')
    .map((e) => e.$2['button']! as String);

Iterable<String> screens() => events
    .where((e) => e.$1 == 'screen_view')
    .map((e) => e.$2['screen']! as String);

void main() {
  setUpAll(() async {
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final path in paths) {
        final bytes = File(path).readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    var dir = File(Platform.resolvedExecutable).parent;
    while (!Directory('${dir.path}/material_fonts').existsSync()) {
      dir = dir.parent;
    }
    final fonts = '${dir.path}/material_fonts';
    await load('LilitaOne', ['assets/fonts/LilitaOne-Regular.ttf']);
    await load('Roboto', [
      '$fonts/roboto-regular.ttf',
      '$fonts/roboto-medium.ttf',
      '$fonts/roboto-bold.ttf',
    ]);
  });

  setUp(() {
    cloud = FakeCloud();
    store = InMemoryStore();
    events = [];
  });

  testWidgets('first launch asks before anything else', (tester) async {
    await boot(tester);
    expect(find.text(google), findsOneWidget);
    expect(find.text(guest), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(cloud.signIns + cloud.googleSignIns + cloud.pushes, 0);
    expect(screens(), ['WelcomeScreen']);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
    testWidgets('the welcome screen fits $size with large text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await boot(tester, size: size);
      expect(find.text(guest), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a guest has no account and uploads nothing', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.text(guest));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(s.progress.data.settings.accountMode, AccountMode.guest);
    expect(s.cloud.status, CloudStatus.signedOut);

    await s.progress.updateSettings((x) => x.music = false);
    await tester.pump(const Duration(seconds: 10));
    expect(cloud.signIns + cloud.googleSignIns + cloud.pushes, 0);
    expect(events.map((e) => e.$1), contains('account_choice'));
    expect(screens().last, 'MainMenuScreen');
  });

  testWidgets('the choice is remembered on the next launch', (tester) async {
    await boot(
      tester,
      save: SaveData(
        tutorialDone: true,
        settings: GameSettings(accountMode: AccountMode.guest),
      ),
    );
    expect(find.text(guest), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Google signs in, restores the save and opens the menu', (
    tester,
  ) async {
    cloud.doc = SaveData(highestStageCleared: 40, updatedAtMs: 9).toJson();
    final s = await boot(tester);
    await tester.tap(find.text(google));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(s.progress.data.settings.accountMode, AccountMode.google);
    expect(s.progress.data.highestStageCleared, 40);
    expect(s.cloud.status, CloudStatus.synced);
    expect(cloud.pushes, 1);
    // Saving the choice is itself a change, uploaded after the usual delay.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('cancelling Google stays on the choice', (tester) async {
    cloud.cancel = true;
    final s = await boot(tester);
    await tester.tap(find.text(google));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(guest), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(s.progress.data.settings.accountMode, AccountMode.undecided);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(guest));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('a failed sign-in explains and leaves guest available', (
    tester,
  ) async {
    cloud.failure = Exception('no internet');
    final s = await boot(tester);
    await tester.tap(find.text(google));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Could not sign in'), findsOneWidget);
    expect(find.text(guest), findsOneWidget);
    expect(s.progress.data.settings.accountMode, AccountMode.undecided);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('builds without cloud saves skip the choice', (tester) async {
    await boot(tester, withCloud: false);
    expect(find.text(guest), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('a returning Google player signs out from their account', (
    tester,
  ) async {
    final s = await boot(tester, withCloud: true);
    await tester.tap(find.text(google));
    await tester.pump();
    await tester.pumpAndSettle();
    await s.signOut();
    await tester.pump();

    expect(s.progress.data.settings.accountMode, AccountMode.guest);
    expect(s.cloud.status, CloudStatus.signedOut);
    expect(s.cloud.account, isNull);
    expect(cloud.doc, isNotNull, reason: 'the cloud save stays');

    final pushes = cloud.pushes;
    await s.progress.updateSettings((x) => x.music = false);
    await tester.pump(const Duration(seconds: 10));
    expect(cloud.pushes, pushes, reason: 'signed out players upload nothing');
  });

  testWidgets('deleting cloud data returns to guest', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.text(google));
    await tester.pump();
    await tester.pumpAndSettle();
    await s.deleteCloudData();
    await tester.pump();

    expect(s.progress.data.settings.accountMode, AccountMode.guest);
    expect(cloud.doc, isNull);
    expect(s.cloud.status, CloudStatus.signedOut);
  });

  testWidgets('taps and screens are reported, and the setting stops them', (
    tester,
  ) async {
    final s = await boot(
      tester,
      save: SaveData(
        tutorialDone: true,
        settings: GameSettings(accountMode: AccountMode.guest),
      ),
    );
    await tester.tap(find.text('Shop'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(taps(), contains('Shop'));
    expect(screens().last, 'ShopScreen');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pumpAndSettle();

    await s.progress.updateSettings((x) => x.shareUsageData = false);
    await tester.pump();
    final count = events.length;
    await tester.tap(find.text('Upgrade'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(events.length, count, reason: 'opted out: nothing is recorded');
  });

  testWidgets('Google sign-in comes first in Settings', (tester) async {
    await boot(
      tester,
      save: SaveData(
        tutorialDone: true,
        settings: GameSettings(accountMode: AccountMode.guest),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(gameRoute<void>(const SettingsScreen()));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(google)).dy,
      lessThan(tester.getTopLeft(find.text('Music')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  test('old saves without a choice ask once; the choice round-trips', () {
    expect(GameSettings.fromJson(const {}).accountMode, AccountMode.undecided);
    final saved = GameSettings(accountMode: AccountMode.google).toJson();
    expect(GameSettings.fromJson(saved).accountMode, AccountMode.google);
  });
}
