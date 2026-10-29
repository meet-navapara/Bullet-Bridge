import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';
import 'package:orbit_blast/ui/screens/game_screen.dart';

/// Rewarded ads that, like the real full-screen ad Activity on Android,
/// take the app out of the foreground while showing.
class FakeAds extends AdsService {
  FakeAds() : super.disabled() {
    rewardedReady.value = true;
  }

  @override
  Future<bool> showRewarded() async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    rewardedReady.value = false;
    return true;
  }
}

class CountingStore extends InMemoryStore {
  int writes = 0;
  @override
  Future<bool> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}

late CountingStore store;

Future<void> boot(WidgetTester tester, {AdsService? ads}) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final save = SaveData(tutorialDone: true, coins: 1000);
  await tester.pumpWidget(
    OrbitBlastApp(
      bootstrap: () async => AppServices(
        progress: PlayerProgress(SaveRepository(store), save),
        audio: AudioService.silent(),
        haptics: HapticsService(),
        ads: ads ?? AdsService.disabled(),
        version: 'test',
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

Future<void> frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

GameSimulation simOf(WidgetTester tester) => tester
    .widget<GameWidget<BoomforgeGame>>(find.byType(GameWidget<BoomforgeGame>))
    .game!
    .sim!;

/// Drops a crystal onto the cannon with one hull left.
Future<void> loseRun(WidgetTester tester) async {
  final sim = simOf(tester);
  sim
    ..hull = 1
    ..invulnerableTimer = 0
    ..shieldTimer = 0
    ..balls.add(
      Ball(
        id: 9999,
        tier: 0,
        maxHp: 999,
        x: sim.cannonX,
        y: sim.floorY - 40,
        vx: 0,
        vy: 0,
      ),
    );
  await frames(tester, 100);
}

Future<int> savedCoins() async =>
    (await SaveRepository(store).load()).data.coins;

void main() {
  setUp(() => store = CountingStore());

  testWidgets('coins earned after an ad revive are saved', (tester) async {
    await boot(tester, ads: FakeAds());
    await tester.tap(find.text('Play'));
    await frames(tester, 40);
    simOf(tester).coins = 30;
    await loseRun(tester);
    await tester.tap(find.text('Continue'));
    await frames(tester, 30);
    expect(find.text('DEFEATED'), findsNothing, reason: 'revived');

    simOf(tester).coins += 500; // earned after the revive
    await loseRun(tester);
    expect(await savedCoins(), 1000 + 530);
  });

  testWidgets('a run whose save failed is saved once storage recovers', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.text('Play'));
    await frames(tester, 40);
    simOf(tester).coins = 40;
    store.failWrites = true;
    await loseRun(tester);
    store.failWrites = false;
    await tester.tap(find.text('Menu'));
    await frames(tester, 40);
    expect(await savedCoins(), 1040);
  });

  testWidgets('the next level waits until the cleared level is saved', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.text('Play'));
    await frames(tester, 40);
    store.failWrites = true;
    // Finish level 1 at once: last wave, nothing left to spawn.
    final sim = simOf(tester)
      ..debugClearSpawnQueue()
      ..invulnerableTimer = 99;
    sim.balls.clear();
    sim.wave = sim.plan.waveCount!;
    await frames(tester, 200);
    expect(sim.isStageCleared, isTrue);
    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('Next Level'), findsNothing);

    store.failWrites = false;
    await tester.tap(find.text('Retry Save'));
    await frames(tester, 30);
    expect(find.text('Retry Save'), findsNothing);
    expect(find.text('Next Level'), findsOneWidget);
    final saved = (await SaveRepository(store).load()).data;
    expect(saved.highestStageCleared, 1);
  });

  testWidgets('double-tapping Play opens one game', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Play'), warnIfMissed: false);
    await frames(tester, 40);
    expect(find.byType(GameScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('dragging a volume slider does not write the save per tick', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    final before = store.writes;
    // A half-second drag at 60 Hz, like a real finger.
    await tester.timedDrag(
      find.byType(Slider).first,
      const Offset(-120, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(store.writes - before, lessThanOrEqualTo(2));
    // ...but the new value is still saved once the finger lifts.
    final saved = (await SaveRepository(store).load()).data.settings;
    expect(saved.musicVolume, lessThan(GameSettings().musicVolume));
  });
}
