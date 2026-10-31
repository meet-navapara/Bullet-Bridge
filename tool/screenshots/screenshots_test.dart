// Renders every screen (and live gameplay frames) to PNGs for visual review
// without a device. Uses the real game fonts plus Roboto/Material Icons
// from the Flutter SDK cache.
//
//   flutter test tool/screenshots/screenshots_test.dart --update-goldens
//
// Images are written to tool/screenshots/out/.
import 'dart:io';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/config/bosses.dart';
import 'package:orbit_blast/game/sim/boss.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';
import 'package:orbit_blast/ui/screens/game_screen.dart';
import 'package:orbit_blast/ui/widgets/common.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

String get _sdkFonts {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  return '$root/bin/cache/artifacts/material_fonts';
}

/// STORE_SHOTS=1 renders at 1080x1920 into store/screenshots/, because Google
/// Play rejects screenshots taller than 2:1. tool/render_store_art_test.dart
/// then removes their alpha channel.
final bool _forStore = Platform.environment['STORE_SHOTS'] == '1';

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(OrbitBlastApp),
    matchesGoldenFile(
      _forStore ? '../../store/screenshots/$name.png' : 'out/$name.png',
    ),
  );
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

GameSimulation _sim(WidgetTester tester) => tester
    .widget<GameWidget<BoomforgeGame>>(find.byType(GameWidget<BoomforgeGame>))
    .game!
    .sim!;

/// Destroys everything on screen so the wave/stage advances quickly.
void _clearArena(GameSimulation sim) {
  for (final b in List<Ball>.of(sim.balls)) {
    b.armor = 0;
    sim.damageBall(b, b.hp);
  }
  sim.hazards.clear();
}

void main() {
  setUpAll(() async {
    await _loadFont('LilitaOne', ['assets/fonts/LilitaOne-Regular.ttf']);
    await _loadFont('Roboto', [
      '$_sdkFonts/roboto-regular.ttf',
      '$_sdkFonts/roboto-medium.ttf',
      '$_sdkFonts/roboto-bold.ttf',
    ]);
    await _loadFont('MaterialIcons', ['$_sdkFonts/materialicons-regular.otf']);
  });

  testWidgets('screens', (tester) async {
    tester.view.physicalSize = Size(1080, _forStore ? 1920 : 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final data =
        SaveData(
            tutorialDone: true,
            coins: 2450,
            bestScore: 8920,
            bestWave: 12,
            highestStageCleared: 6,
            stageStars: {1: 3, 2: 3, 3: 2, 4: 3, 5: 1, 6: 2},
          )
          ..upgrades[UpgradeType.fireRate] = 5
          ..upgrades[UpgradeType.bulletPower] = 4
          ..upgrades[UpgradeType.cannonLevel] = 3
          ..upgrades[UpgradeType.coinBonus] = 2
          ..ownedSkins.add('ember')
          ..stats.ballsDestroyed = 320
          ..stats.upgradesBought = 3;
    await tester.pumpWidget(
      OrbitBlastApp(
        bootstrap: () async => AppServices(
          progress: PlayerProgress(SaveRepository(InMemoryStore()), data),
          audio: AudioService.silent(),
          haptics: HapticsService(),
          ads: AdsService.disabled(),
          version: '1.0.0 (1)',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '01_splash');
    await tester.pump(const Duration(milliseconds: 800));
    await _frames(tester, 30);
    await _shot(tester, '02_menu');

    Future<void> visit(String button, String name) async {
      await tester.tap(find.text(button).first);
      await _frames(tester, 30);
      await _shot(tester, name);
      await tester.tap(find.bySemanticsLabel('Back'));
      await _frames(tester, 30);
    }

    await visit('Levels', '03_levels');
    await visit('Upgrade', '04_upgrades');
    await visit('Shop', '05_shop');
    await visit('Daily', '06_daily_reward');
    await visit('Goals', '07_missions');
    await visit('How to', '08_tutorial');
    await tester.tap(find.bySemanticsLabel('Settings'));
    await _frames(tester, 30);
    await _shot(tester, '09_settings');
    await tester.tap(find.bySemanticsLabel('Back'));
    await _frames(tester, 30);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);

    // Level 7: geodes, skyrays, every hazard type, two hazards per wave.
    nav.push(gameRoute<void>(const GameScreen(stage: 7)));
    await _frames(tester, 30);
    await _shot(tester, '10_stage_intro');
    var sim = _sim(tester);
    sim.setElement(Element.fire);
    for (
      var i = 0;
      i < 120 * 40 && (sim.balls.length < 3 || sim.hazards.length < 2);
      i++
    ) {
      sim.invulnerableTimer = 1;
      sim.step(1 / 120);
      sim.drainEvents();
    }
    sim.invulnerableTimer = 0;
    await _frames(tester, 150);
    await _shot(tester, '11_gameplay');
    // Trigger a chain reaction by shooting the first hazard.
    if (sim.hazards.isNotEmpty) {
      final hz = sim.hazards.first;
      sim.bullets.add(
        Bullet(hz.x, hz.y + hz.radius + 2, 1e6, element: Element.fire),
      );
    }
    await _frames(tester, 9);
    await _shot(tester, '12_chain_reaction');

    await tester.tap(find.bySemanticsLabel('Pause'));
    await _frames(tester, 20);
    await _shot(tester, '13_pause');
    await tester.tap(find.text('Resume'));
    await _frames(tester, 10);

    // Clear the remaining waves to reach the stage-clear screen.
    for (var i = 0; i < 120 * 60 && !sim.isFinished; i++) {
      sim.invulnerableTimer = 1;
      _clearArena(sim);
      sim.step(1 / 120);
      sim.drainEvents();
    }
    await _frames(tester, 140);
    await _shot(tester, '14_stage_clear');
    await tester.tap(find.text('Menu'));
    await _frames(tester, 40);

    // Boss stage.
    nav.push(gameRoute<void>(const GameScreen(stage: 10)));
    await _frames(tester, 20);
    sim = _sim(tester);
    sim.setElement(Element.electric);
    for (var i = 0; i < 120 * 60 && (sim.boss == null); i++) {
      sim.invulnerableTimer = 1;
      _clearArena(sim);
      sim.step(1 / 120);
      sim.drainEvents();
    }
    final boss = sim.boss!;
    boss
      ..transition = 0
      ..y = boss.homeY
      ..unitsLeft = boss.unitsTotal ~/ 2
      ..phase = 2
      ..slam = SlamState.none
      ..armPhase();
    boss.timers.updateAll((_, _) => 99);
    boss.timers[BossAttack.slam] = 0.6;
    boss.timers[BossAttack.rain] = 0.2;
    boss.plates[0] = 0;
    sim.cannonX = 260;
    await _frames(tester, 70);
    await _shot(tester, '15_boss');

    // Defeat.
    sim
      ..invulnerableTimer = 0
      ..shieldTimer = 0
      ..hull = 1;
    sim.shots.add(EnemyShot(sim.cannonX, sim.floorY - 30, 0, 0));
    await _frames(tester, 90);
    await _shot(tester, '16_defeat');
  });
}
