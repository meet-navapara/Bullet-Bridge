import 'dart:io';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';
import 'package:orbit_blast/ui/screens/game_screen.dart';
import 'package:orbit_blast/ui/widgets/common.dart';

/// Chapter 51 has the longest names in the campaign: "Shattered Crystal
/// Highlands" and its boss, "Shattered Crystal Colossus". These run on the
/// narrowest supported phone with the largest text the app allows.
const int longestChapter = 51;
const int bossLevel = 510;

Future<void> boot(WidgetTester tester, SaveData save) async {
  tester.view.physicalSize = const Size(320, 568) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = 1.25;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    OrbitBlastApp(
      bootstrap: () async => AppServices(
        progress: PlayerProgress(SaveRepository(InMemoryStore()), save),
        audio: AudioService.silent(),
        haptics: HapticsService(),
        ads: AdsService.disabled(),
        version: 'test',
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
}

void main() {
  // Text widths must be real ones: the default test font is much wider.
  setUpAll(() async {
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final path in paths) {
        final bytes = File(path).readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    // Captions use the system font, Roboto on Android. The test runner lives
    // inside the Flutter SDK, next to the SDK's copy of it.
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

  test('chapter 51 really has the longest names', () {
    int longest(Iterable<String> names) =>
        names.map((n) => n.length).reduce((a, b) => a > b ? a : b);
    final chapter = Campaign.chapter(longestChapter);
    expect(chapter.name.length, longest(Campaign.chapters.map((c) => c.name)));
    expect(
      chapter.boss.name.length,
      longest(Campaign.chapters.map((c) => c.boss.name)),
    );
  });

  testWidgets('the level map fits the longest chapter and boss names', (
    tester,
  ) async {
    await boot(
      tester,
      SaveData(tutorialDone: true, highestStageCleared: bossLevel - 10),
    );
    await tester.tap(find.text('Levels').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(Campaign.chapter(longestChapter).name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked chapter with a long name fits the level map', (
    tester,
  ) async {
    await boot(
      tester,
      SaveData(tutorialDone: true, highestStageCleared: bossLevel - 11),
    );
    await tester.tap(find.text('Levels').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(find.byType(ListView).first, const Offset(0, -1100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(Campaign.chapter(longestChapter).name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the boss card and boss bar fit the longest boss name', (
    tester,
  ) async {
    await boot(
      tester,
      SaveData(tutorialDone: true, highestStageCleared: bossLevel - 1),
    );
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(gameRoute<void>(const GameScreen(stage: bossLevel)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SHATTERED CRYSTAL COLOSSUS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final game = tester
        .widget<GameWidget<BoomforgeGame>>(
          find.byType(GameWidget<BoomforgeGame>),
        )
        .game!;
    for (var frame = 0; frame < 4000; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final sim = game.sim;
      if (sim == null) continue;
      if (sim.boss != null) break;
      for (final ball in List<Ball>.of(sim.balls)) {
        ball.armor = 0;
        sim.damageBall(ball, ball.hp);
      }
      sim.hazards.clear();
    }
    await tester.pump(const Duration(seconds: 1));
    expect(game.sim!.boss, isNotNull, reason: 'the boss must have arrived');
    expect(find.text('SHATTERED CRYSTAL COLOSSUS'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
