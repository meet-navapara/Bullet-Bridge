import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';

late InMemoryStore store;

Future<AppServices> fakeBootstrap(SaveData data) async {
  final progress = PlayerProgress(SaveRepository(store), data);
  return AppServices(
    progress: progress,
    audio: AudioService.silent(),
    haptics: HapticsService(),
    ads: AdsService.disabled(),
    version: 'test',
  );
}

Future<void> boot(
  WidgetTester tester, {
  required Size size,
  SaveData? data,
}) async {
  // [size] is in logical pixels.
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final save = data ?? SaveData(tutorialDone: true, coins: 1000);
  await tester.pumpWidget(OrbitBlastApp(bootstrap: () => fakeBootstrap(save)));
  // Splash has a minimum display time.
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => store = InMemoryStore());

  for (final size in const [
    Size(320, 568),
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets('main menu renders without overflow at $size', (tester) async {
      await boot(tester, size: size);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Upgrade'), findsOneWidget);
      expect(find.text('Challenge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('buying an upgrade updates coins and persists', (tester) async {
    await boot(tester, size: const Size(393, 852));
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(find.text('Fire Rate'), findsOneWidget);
    expect(find.text('Lv. 1'), findsWidgets);
    // First card's price button.
    await tester.tap(find.text('60'));
    await tester.pumpAndSettle();
    expect(find.text('940'), findsOneWidget);
    final saved = await SaveRepository(store).load();
    expect(saved.data.coins, 940);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings toggles persist', (tester) async {
    await boot(tester, size: const Size(393, 852));
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final saved = await SaveRepository(store).load();
    expect(saved.data.settings.music, isFalse);
  });

  testWidgets('every menu destination opens', (tester) async {
    await boot(tester, size: const Size(393, 852));
    for (final (button, expected) in const [
      ('Shop', 'Cannons'),
      ('Levels', 'Crystal Highlands'),
      ('Daily', 'Come back every day!'),
      ('Challenge', "Today's Challenge"),
      ('Goals', 'Shatter 100 crystals'),
      ('How to', 'Drag to Move'),
    ]) {
      await tester.tap(find.text(button).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(expected), findsWidgets, reason: button);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
  });

  testWidgets('the level map opens on the current chapter of a late save', (
    tester,
  ) async {
    await boot(
      tester,
      size: const Size(393, 852),
      data: SaveData(tutorialDone: true, highestStageCleared: 995),
    );
    await tester.tap(find.text('Levels').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Eternal World's Edge"), findsOneWidget);
    expect(find.text('Crystal Highlands'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first Play shows the tutorial, then the game; pause works', (
    tester,
  ) async {
    await boot(tester, size: const Size(393, 852), data: SaveData());
    await tester.tap(find.text('Play'));
    // The tutorial animates forever, so pump fixed frames.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Drag to Move'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Wave 1'), findsOneWidget);
    expect((await SaveRepository(store).load()).data.tutorialDone, isTrue);

    // Let the simulation run a little.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paused'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finger left down keeps steering after the first lifts', (
    tester,
  ) async {
    await boot(tester, size: const Size(393, 852));
    await tester.tap(find.text('Play'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final sim = tester
        .widget<GameWidget<BoomforgeGame>>(
          find.byType(GameWidget<BoomforgeGame>),
        )
        .game!
        .sim!;
    final first = await tester.startGesture(const Offset(200, 500));
    final second = await tester.startGesture(
      const Offset(250, 500),
      pointer: 7,
    );
    await first.up();
    final before = sim.cannonX;
    for (var i = 0; i < 5; i++) {
      await second.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(sim.cannonX, lessThan(before - 20));
    await second.up();
    expect(tester.takeException(), isNull);
  });
}
