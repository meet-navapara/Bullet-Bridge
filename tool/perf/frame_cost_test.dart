// Measures the Dart-side cost of one gameplay frame (simulation update +
// recording the frame's draw commands) on a deliberately busy scene.
//
// This runs on the development machine's CPU without a GPU, so it says
// nothing about raster time on a phone. It is useful for comparing code
// changes against each other. Run:
//   flutter test tool/perf/frame_cost_test.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/hud_model.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/frame_monitor.dart';
import 'package:orbit_blast/services/haptics_service.dart';

void main() {
  testWidgets('frame cost on a busy scene', (tester) async {
    await tester.runAsync(() async {
      final game = BoomforgeGame(
        setup: RunSetup(
          loadout: Upgrades.dailyChallengeLoadout,
          plan: StagePlan(6),
          seedFactory: () => 42,
        ),
        skin: Catalog.skins.first,
        theme: Catalog.themes.first,
        audio: AudioService.silent(),
        haptics: HapticsService()..enabled = false,
        hud: HudModel(),
        onRunEnded: (_) {},
      );
      // A 1080x2400 phone at 2.625 dpr.
      game.onGameResize(Vector2(411, 914));
      final sim = game.sim!;
      final rng = math.Random(1);

      final update = <double>[];
      final render = <double>[];
      final watch = Stopwatch();
      var particles = 0;
      for (var frame = 0; frame < 900; frame++) {
        // Keep the arena full: a dozen crystals of every tier.
        while (sim.balls.length < 12) {
          final tier = rng.nextInt(5);
          sim.balls.add(
            Ball(
              id: 10000 + frame * 20 + sim.balls.length,
              tier: tier,
              maxHp: 400,
              x: 60 + rng.nextDouble() * (sim.width - 120),
              y: 120 + rng.nextDouble() * 300,
              vx: rng.nextBool() ? 70 : -70,
              vy: 0,
              kind: tier.isEven ? EnemyKind.shard : EnemyKind.geode,
              armor: tier.isEven ? 0 : 120,
            ),
          );
        }
        sim.cannonX = sim.width / 2 + math.sin(frame / 30) * 120;
        sim.invulnerableTimer = 10; // the run must not end mid-benchmark
        particles += game.effects.particleCount;
        watch
          ..reset()
          ..start();
        game.update(1 / 60);
        watch.stop();
        update.add(watch.elapsedMicroseconds / 1000);

        final recorder = PictureRecorder();
        watch
          ..reset()
          ..start();
        game.render(Canvas(recorder));
        final picture = recorder.endRecording();
        watch.stop();
        render.add(watch.elapsedMicroseconds / 1000);
        picture.dispose();
      }
      // Skip warm-up frames (sprite and text caches filling).
      final summary = FrameMonitor.summarize(
        update.sublist(60),
        render.sublist(60),
      ).replaceAll('ui ', 'update ').replaceAll('raster ', 'record ');
      // ignore: avoid_print
      print(
        '[frame-cost] $summary | avg particles ${particles ~/ 900} | balls ${sim.balls.length} | finished ${sim.isFinished}',
      );
    });
  });
}
