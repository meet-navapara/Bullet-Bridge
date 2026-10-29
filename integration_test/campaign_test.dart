// Plays representative campaign levels on a real device the way a player
// does (the first levels, a chapter's challenge and boss, a recovery level,
// and the bosses of levels 50, 90 and 100), steering with real touch drags.
// Records per-level frame timings (from the engine's FrameTiming) and
// checks the game state every frame.
//
// Run (profile mode, so timings are representative):
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/campaign_test.dart -d <device>
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:orbit_blast/app/app.dart';
import 'package:orbit_blast/app/app_services.dart';
import 'package:flutter/widgets.dart' show Navigator;
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';
import 'package:orbit_blast/services/ads_service.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';
import 'package:orbit_blast/ui/screens/game_screen.dart';
import 'package:orbit_blast/ui/screens/main_menu_screen.dart';
import 'package:orbit_blast/ui/widgets/common.dart';

/// Late-game upgrades so every sampled level finishes in a few minutes.
final Map<UpgradeType, int> lateGame = {
  UpgradeType.fireRate: 14,
  UpgradeType.bulletPower: 16,
  UpgradeType.cannonLevel: 5,
  UpgradeType.coinBonus: 2,
  UpgradeType.startingShield: 0,
  UpgradeType.elementPower: 4,
};

/// Levels played: chapter 1 start, challenge, final test and boss, chapter 2
/// start, a mid-campaign recovery level and three late bosses.
const levels = [1, 5, 9, 10, 11, 26, 50, 90, 100];

class StageReport {
  StageReport(this.stage);
  final int stage;
  final List<double> build = [];
  final List<double> raster = [];
  final List<String> problems = [];
  double seconds = 0;
  int score = 0;
  int coins = 0;
  int maxBalls = 0;
  int maxParticles = 0;
  int spriteMisses = 0;
  int spriteCount = 0;
  int spriteMb = 0;
  bool cleared = false;

  Map<String, Object?> toJson() {
    double pct(List<double> v, double p) {
      if (v.isEmpty) return 0;
      final s = [...v]..sort();
      return s[math.min(s.length - 1, (s.length * p).floor())];
    }

    double avg(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    final over = [
      for (var i = 0; i < build.length; i++)
        if (math.max(build[i], raster[i]) > 16.7) 1,
    ].length;
    return {
      'stage': stage,
      'cleared': cleared,
      'seconds': seconds.round(),
      'frames': build.length,
      'buildAvg': avg(build),
      'buildP90': pct(build, 0.9),
      'buildMax': pct(build, 1),
      'rasterAvg': avg(raster),
      'rasterP90': pct(raster, 0.9),
      'rasterP99': pct(raster, 0.99),
      'rasterMax': pct(raster, 1),
      'over16ms': over,
      'score': score,
      'coins': coins,
      'maxBalls': maxBalls,
      'maxParticles': maxParticles,
      'spriteMisses': spriteMisses,
      'spriteCount': spriteCount,
      'spriteMb': spriteMb,
      'problems': problems,
    };
  }
}

GameWidget<BoomforgeGame>? gameWidget(WidgetTester tester) {
  final f = find.byType(GameWidget<BoomforgeGame>);
  return f.evaluate().isEmpty ? null : tester.widget(f);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('play the whole campaign', (tester) async {
    final reports = <StageReport>[];
    StageReport? current;
    void onTimings(List<FrameTiming> timings) {
      final r = current;
      if (r == null) return;
      for (final t in timings) {
        r.build.add(t.buildDuration.inMicroseconds / 1000);
        r.raster.add(t.rasterDuration.inMicroseconds / 1000);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);

    final save = SaveData(tutorialDone: true, coins: 0, highestStageCleared: 99)
      ..upgrades.addAll(lateGame);
    final audio = AudioService();
    final audioWatch = Stopwatch()..start();
    await audio.init(save.settings);
    audioWatch.stop();

    await tester.pumpWidget(
      OrbitBlastApp(
        bootstrap: () async => AppServices(
          progress: PlayerProgress(SaveRepository(InMemoryStore()), save),
          audio: audio,
          haptics: HapticsService(),
          ads: AdsService.disabled(),
          version: 'it',
        ),
      ),
    );
    // The menu animates forever, so pumpAndSettle would never return.
    while (find.text('Play').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final stage in levels) {
      // Open the level from the menu.
      Navigator.of(tester.element(find.byType(MainMenuScreen)))
          .push(gameRoute<void>(GameScreen(stage: stage)));
      await tester.pump(const Duration(milliseconds: 500));
      final report = StageReport(stage);
      reports.add(report);
      current = report;
      final watch = Stopwatch()..start();

      // Wait for this stage's game.
      while (gameWidget(tester)?.game?.sim == null) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final game = gameWidget(tester)!.game!;
      final sim = game.sim!;
      expect(sim.plan.waveCount, Campaign.level(stage).waves);

      // Use the newest unlocked element (each stage exercises a new one).
      final elements = sim.loadout.elements.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      game.selectElement(elements[(stage - 1) % elements.length]);

      // One finger held down for the whole stage, steering like a player.
      final finger = await tester.startGesture(
        Offset(size.width / 2, size.height * 0.6),
      );
      var lastScore = -1;
      var lastProgress = 0.0;
      while (!sim.isFinished && watch.elapsed.inSeconds < 300) {
        // The test checks playback, not survival: keep the run alive.
        sim.invulnerableTimer = 1;
        Ball? target;
        for (final b in sim.balls) {
          if (target == null || b.y > target.y) target = b;
        }
        final boss = sim.boss;
        double goal = target?.x ?? sim.width / 2;
        if (boss != null && !boss.dead) {
          final plate = boss.plates.indexWhere((p) => p > 0);
          goal = plate < 0 ? boss.x : boss.plateX(plate);
        }
        final dxWorld = (goal - sim.cannonX).clamp(-14.0, 14.0);
        await finger.moveBy(Offset(dxWorld * size.width / sim.width, 0));
        await tester.pump(const Duration(milliseconds: 16));

        // State checks.
        for (final b in sim.balls) {
          final r = b.radius;
          if (!b.x.isFinite || !b.y.isFinite) {
            report.problems.add('non-finite ball t${b.tier}');
          } else if (b.x < -3 * r ||
              b.x > sim.width + 3 * r ||
              b.y > sim.floorY + 2) {
            report.problems.add(
              'ball outside arena x${b.x.round()} y${b.y.round()}',
            );
          }
        }
        report.maxBalls = math.max(report.maxBalls, sim.balls.length);
        report.maxParticles = math.max(
          report.maxParticles,
          game.effects.particleCount,
        );
        final t = watch.elapsedMilliseconds / 1000;
        if (sim.score != lastScore || sim.phase != RunPhase.playing) {
          lastScore = sim.score;
          lastProgress = t;
        } else if (t - lastProgress > 30) {
          report.problems.add('no progress for 30 s in wave ${sim.wave}');
          lastProgress = t;
        }
        if (report.problems.length > 20) break;
      }
      await finger.up();
      report
        ..seconds = watch.elapsedMilliseconds / 1000
        ..score = sim.score
        ..coins = sim.coins
        ..spriteMisses = game.art.spriteMisses
        ..spriteCount = game.art.spriteCount
        ..spriteMb = game.art.spriteBytes >> 20
        ..cleared = sim.isStageCleared;
      current = null;
      if (!sim.isStageCleared) break;

      // The stage-clear card appears after the finishing effects.
      final next = find.text('Menu');
      var waited = 0;
      while (next.evaluate().isEmpty && waited < 200) {
        await tester.pump(const Duration(milliseconds: 50));
        waited++;
      }
      if (next.evaluate().isEmpty) {
        report.problems.add('stage-clear button never appeared');
        break;
      }
      // Let the card's entrance animation finish before tapping.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(next.first);
      while (find.byType(MainMenuScreen).hitTestable().evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 600));
    }
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    binding.reportData = {
      'audioInitMs': audioWatch.elapsedMilliseconds,
      'audioVoices': audio.voiceCount,
      'stages': [for (final r in reports) r.toJson()],
    };
    for (final r in reports) {
      expect(r.cleared, isTrue, reason: 'stage ${r.stage} did not clear');
      expect(r.problems, isEmpty, reason: 'stage ${r.stage}');
    }
  });
}
