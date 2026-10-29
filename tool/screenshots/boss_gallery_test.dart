// Renders every boss mid-fight, and sample levels, with the real game
// renderer, into tool/screenshots/out/bosses for visual review.
//   flutter test tool/screenshots/boss_gallery_test.dart
import 'dart:io';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/bosses.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/boomforge_game.dart';
import 'package:orbit_blast/game/hud_model.dart';
import 'package:orbit_blast/game/sim/boss.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';
import 'package:orbit_blast/services/audio_service.dart';
import 'package:orbit_blast/services/haptics_service.dart';

const width = 411.0;
const height = 914.0;

Future<void> save(BoomforgeGame game, String name) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..scale(1.0);
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final png = await image.toByteData(format: ImageByteFormat.png);
  final dir = Directory('tool/screenshots/out/bosses')
    ..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

BoomforgeGame gameFor(int level) {
  final game = BoomforgeGame(
    setup: RunSetup(
      loadout: Upgrades.loadoutFor({
        UpgradeType.fireRate: 10,
        UpgradeType.bulletPower: 1,
        UpgradeType.cannonLevel: 5,
      }, elements: Element.values.toSet()),
      plan: StagePlan(level),
      seedFactory: () => level,
    ),
    skin: Catalog.skins.first,
    theme: level > 10
        ? Campaign.level(level).chapterDef.theme
        : Catalog.themes.first,
    audio: AudioService.silent(),
    haptics: HapticsService()..enabled = false,
    hud: HudModel(),
    onRunEnded: (_) {},
  );
  game.onGameResize(Vector2(width, height));
  return game;
}

void main() {
  testWidgets('boss gallery', (tester) async {
    await tester.runAsync(() async {
      for (final def in Bosses.all) {
        final level = (def.id.index + 1) * 10;
        final game = gameFor(level);
        final sim = game.sim!;
        // Skip the warm-up wave.
        for (var i = 0; i < 120 * 300 && sim.boss == null; i++) {
          sim.invulnerableTimer = 1;
          for (final b in List<Ball>.of(sim.balls)) {
            b.armor = 0;
            sim.damageBall(b, b.hp, source: DamageSource.bomb);
          }
          sim.hazards.clear();
          sim.step(Physics.fixedStep);
          sim.drainEvents();
        }
        final boss = sim.boss!;
        // Let it enter and fight for a while: the middle phase with one
        // plate broken shows plates, attacks and the phase colour.
        boss.phase = (def.phases.length + 1) ~/ 2;
        boss.armPhase();
        if (boss.plates.length > 1) boss.plates[0] = 0;
        for (var f = 0; f < 60 * 6; f++) {
          sim.invulnerableTimer = 1;
          game.update(1 / 60);
        }
        // Force one telegraphed attack on screen.
        boss.timers.updateAll((_, _) => 0.0);
        boss.attackGap = 0;
        for (var f = 0; f < 20; f++) {
          sim.invulnerableTimer = 1;
          game.update(1 / 60);
        }
        if (def.phases.any((p) => p.weakWindows)) {
          boss.phase = def.phases.indexWhere((p) => p.weakWindows) + 1;
          boss.weak = WeakState.open;
        }
        await save(game, '${level}_${def.id.name}');
        game.onRemove();
      }
      // Sample levels: treasure, giants, hazard cluster, elemental.
      for (final level in [11, 21, 24, 34, 51, 64]) {
        final game = gameFor(level);
        final sim = game.sim!;
        for (var f = 0; f < 60 * 9; f++) {
          sim.invulnerableTimer = 1;
          game.update(1 / 60);
        }
        await save(game, 'level_$level');
        game.onRemove();
      }
    });
  });
}
