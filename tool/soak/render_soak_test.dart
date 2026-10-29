// Long-session soak of the whole game object (simulation, events, effects
// and drawing): 20 simulated minutes of endless play, reporting the frame
// cost per minute so any slowdown that builds up over time shows. CPU only;
// it cannot see GPU raster time. Run:
//   flutter test tool/soak/render_soak_test.dart
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/hud_model.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';

import 'soak_test.dart' show autoPlay;

void main() {
  testWidgets('20 minutes of endless play does not slow down', (tester) async {
    await tester.runAsync(() async {
      final game = BoomforgeGame(
        setup: RunSetup(
          loadout: Upgrades.dailyChallengeLoadout,
          seedFactory: () => 7,
        ),
        skin: Catalog.skins.first,
        theme: Catalog.themes.first,
        audio: AudioService.silent(),
        haptics: HapticsService()..enabled = false,
        hud: HudModel(),
        onRunEnded: (_) {},
      );
      game.onGameResize(Vector2(411, 914));
      final sim = game.sim!;

      const minutes = 20;
      final perMinute = <double>[];
      var maxParticles = 0;
      final watch = Stopwatch();
      for (var m = 0; m < minutes; m++) {
        var total = 0.0;
        for (var f = 0; f < 60 * 60; f++) {
          sim.invulnerableTimer = 1;
          autoPlay(sim);
          watch
            ..reset()
            ..start();
          game.update(1 / 60);
          final recorder = PictureRecorder();
          game.render(Canvas(recorder));
          recorder.endRecording().dispose();
          watch.stop();
          total += watch.elapsedMicroseconds / 1000;
          final p = game.effects.particleCount;
          if (p > maxParticles) maxParticles = p;
        }
        perMinute.add(total / 3600);
      }
      // ignore: avoid_print
      print(
        '[render-soak] wave ${sim.wave} balls ${sim.balls.length} max '
        'particles $maxParticles | ms/frame per minute: '
        '${perMinute.map((v) => v.toStringAsFixed(2)).join(' ')}',
      );
      expect(sim.isFinished, isFalse);
      // Later minutes have more enemies, so allow growth from content but
      // not the runaway growth of a leak.
      final early = perMinute.sublist(1, 4).reduce((a, b) => a + b) / 3;
      final late = perMinute.sublist(minutes - 3).reduce((a, b) => a + b) / 3;
      expect(late, lessThan(early * 3 + 1));
      expect(maxParticles, lessThanOrEqualTo(240));
    });
  });
}
