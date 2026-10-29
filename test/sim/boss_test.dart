import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/bosses.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/sim/boss.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/seeded_random.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

import '../support/auto_player.dart';
import 'mechanics_test.dart' show arena, quiet, shoot, steps;

/// A run that is only [def]'s boss wave.
class BossOnlyPlan implements RunPlan {
  const BossOnlyPlan(this.def);
  final BossDef def;
  @override
  int get waveCount => 1;
  @override
  WavePlan wave(int number, SeededRandom rng) => WavePlan(
    spawns: const [],
    hazards: const [],
    difficulty: 3,
    boss: def,
    scale: 20,
    pace: 0.6,
  );
}

/// A boss that has finished its entrance, hovering at home with all
/// attacks far in the future (tests trigger what they need).
GameSimulation bossSim(BossDef def) {
  final sim = GameSimulation(
    loadout: quiet,
    seed: 7,
    arenaHeight: arena,
    plan: BossOnlyPlan(def),
  );
  sim.drainEvents();
  final b = sim.boss!
    ..transition = 0
    ..y = sim.boss!.homeY;
  b.timers.updateAll((_, _) => 999);
  return sim;
}

void hitCore(GameSimulation sim, double damage, {Element? element}) {
  final b = sim.boss!;
  shoot(
    sim,
    b.x,
    b.y + b.coreRadius + 2,
    damage: damage,
    element: element ?? Element.kinetic,
  );
}

void main() {
  group('boss data', () {
    test('ten distinct bosses, one per chapter', () {
      expect(Bosses.all, hasLength(10));
      expect(Bosses.all.map((b) => b.name).toSet(), hasLength(10));
      expect(Bosses.all.map((b) => b.shape).toSet(), hasLength(10));
      for (var c = 1; c <= 10; c++) {
        expect(Campaign.chapter(c).boss, Bosses.all[c - 1]);
      }
    });

    test('every boss definition is consistent and fits the arena', () {
      for (final b in Bosses.all) {
        expect(b.exposure, hasLength(b.plates.length + 1), reason: b.name);
        expect(b.exposure.last, 1.0, reason: b.name);
        expect(b.phases.length, inInclusiveRange(2, 4), reason: b.name);
        for (final p in b.phases) {
          expect(p.attacks, isNotEmpty, reason: b.name);
          expect(p.tempo, inInclusiveRange(0.8, 1.2), reason: b.name);
        }
        expect(b.margin * 2, lessThan(Physics.worldWidth), reason: b.name);
        expect(b.reward.coins, greaterThan(0));
        if (b.reward.skinId != null) {
          expect(Catalog.isSkin(b.reward.skinId!), isTrue);
        }
      }
    });

    test('every plate and head can be hit from below', () {
      for (final def in Bosses.all) {
        for (var i = 0; i < def.plates.length; i++) {
          final p = def.plates[i];
          // Some bullet column must reach this plate before anything else.
          var reachable = false;
          for (var dx = p.dx - p.radius + 1; dx < p.dx + p.radius; dx += 1) {
            final hitsPlate = (dx - p.dx).abs() < p.radius;
            // Lowest leading edge (largest y) is hit first.
            double bottom(double cx, double cy, double r) {
              final d = (dx - cx).abs();
              return d >= r ? double.negativeInfinity : cy + r;
            }

            final mine = bottom(p.dx, p.dy, p.radius);
            var blocked = bottom(0, 0, def.coreRadius) > mine;
            for (var j = 0; j < def.plates.length; j++) {
              if (j == i) continue;
              final o = def.plates[j];
              if (bottom(o.dx, o.dy, o.radius) > mine) blocked = true;
            }
            if (hitsPlate && !blocked) reachable = true;
          }
          // Plates hidden behind other plates are fine: those break first.
          final behindPlate = [
            for (var j = 0; j < def.plates.length; j++)
              if (j != i &&
                  (def.plates[j].dx - p.dx).abs() <
                      def.plates[j].radius + p.radius &&
                  def.plates[j].dy > p.dy)
                j,
          ].isNotEmpty;
          expect(
            reachable || behindPlate,
            isTrue,
            reason: '${def.name} plate $i is shielded by the core',
          );
        }
      }
    });

    test('no two bosses fight with the same set of attacks', () {
      final signatures = {
        for (final b in Bosses.all)
          '${b.phases.map((p) => (p.attacks.toList()..sort((a, c) => a.index - c.index)).join(',')).join('|')}'
              '${b.phases.any((p) => p.weakWindows) ? '+weak' : ''}'
              '+${b.plates.length}',
      };
      expect(signatures, hasLength(10));
    });
  });

  group('boss engine', () {
    final colossus = Bosses.of(BossId.crystalColossus);

    test('entrance: starts above the arena, invulnerable, then descends', () {
      final sim = GameSimulation(
        loadout: quiet,
        seed: 1,
        arenaHeight: arena,
        plan: BossOnlyPlan(colossus),
      );
      final b = sim.boss!;
      expect(b.y, lessThan(0));
      expect(b.transition, BossSpec.entranceTime);
      final core = b.core;
      steps(sim, 0.5);
      sim.bullets.add(Bullet(b.x, b.y + b.coreRadius + 2, 50));
      sim.step(Physics.fixedStep);
      expect(b.core, core, reason: 'invulnerable during the entrance');
      steps(sim, BossSpec.entranceTime + 2);
      expect(b.y, closeTo(b.homeY, 2));
    });

    test('plates shield the core until broken', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      hitCore(sim, 100);
      expect(b.core, closeTo(b.coreMax - 100 * colossus.exposure[0], 1e-6));
      for (var i = 0; i < b.plates.length; i++) {
        sim.bullets.add(
          Bullet(
            b.plateX(i),
            b.plateY(i) + b.plateRadius(i) + 2,
            b.plateMax,
            element: Element.fire,
          ),
        );
        sim.step(Physics.fixedStep);
      }
      expect(b.platesLeft, 0);
      expect(sim.events.whereType<BossPlateBroken>(), hasLength(2));
      final before = b.core;
      hitCore(sim, 10);
      expect(b.core, closeTo(before - 10, 1e-6));
    });

    test('every boss walks through all its phases in order', () {
      for (final def in Bosses.all) {
        final sim = bossSim(def);
        final b = sim.boss!;
        b.plates.fillRange(0, b.plates.length, 0);
        b.weak = WeakState.open;
        final seen = <int>[1];
        var guard = 0;
        while (!b.dead && guard++ < 400) {
          b.transition = 0;
          b.y = b.homeY;
          b.slam = SlamState.none;
          if (b.hasWeakWindows) b.weak = WeakState.open;
          hitCore(sim, b.coreMax * 0.05);
          if (b.phase != seen.last) seen.add(b.phase);
        }
        expect(b.dead, isTrue, reason: def.name);
        expect(seen, [
          for (var p = 1; p <= def.phases.length; p++) p,
        ], reason: def.name);
        expect(
          sim.events.whereType<BossPhaseChanged>(),
          hasLength(def.phases.length - 1),
          reason: def.name,
        );
      }
    });

    test('a phase change is an invulnerable transition', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      b.plates.fillRange(0, 2, 0);
      b.core = b.coreMax * 0.67;
      hitCore(sim, b.coreMax * 0.02);
      expect(b.phase, 2);
      expect(b.transition, greaterThan(0));
      final core = b.core;
      hitCore(sim, 50);
      expect(b.core, core);
    });

    test('shard rain is telegraphed before it falls', () {
      final sim = bossSim(colossus);
      sim.boss!.timers[BossAttack.rain] = 0.001;
      sim.step(Physics.fixedStep);
      expect(sim.telegraphs, hasLength(3));
      expect(sim.shots, isEmpty);
      steps(sim, BossSpec.rainTelegraph + 0.02);
      expect(sim.shots, hasLength(3));
    });

    test('shots at an invulnerable boss show a shield spark', () {
      final sim = bossSim(colossus);
      final b = sim.boss!..transition = 1;
      final core = b.core;
      hitCore(sim, 50);
      expect(b.core, core);
      expect(sim.events.whereType<BossShielded>(), hasLength(1));
    });

    test('rain columns always leave a safe band for the cannon', () {
      const reach = EnemySpec.shotRadius + CannonSpec.bodyHalfWidth;
      for (var seed = 0; seed < 200; seed++) {
        final sim = GameSimulation(
          loadout: quiet,
          seed: seed,
          arenaHeight: arena,
          plan: BossOnlyPlan(colossus),
        );
        final b = sim.boss!
          ..transition = 0
          ..y = sim.boss!.homeY;
        b.timers.updateAll((_, _) => 999);
        sim.setCannonX(40 + (seed * 37) % 280);
        b.timers[BossAttack.rain] = 0.001;
        sim.step(Physics.fixedStep);
        final xs = sim.telegraphs.map((t) => t.x).toList()..sort();
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], greaterThan(reach * 2), reason: '$seed');
        }
      }
    });

    test('aimed attacks wait while the cannon is frozen', () {
      final sim = bossSim(colossus);
      final b = sim.boss!
        ..phase = 2
        ..armPhase();
      b.timers.updateAll((_, _) => 999);
      b.timers[BossAttack.slam] = 0.001;
      sim.cannonSlowTimer = 1;
      sim.step(Physics.fixedStep);
      expect(b.slam, SlamState.none);
      // The retry timer runs on the boss's pace.
      steps(sim, 3);
      expect(b.slam, isNot(SlamState.none), reason: 'starts once free');
    });

    test('a slam lands on the telegraphed spot and can hurt the cannon', () {
      final sim = bossSim(colossus);
      final b = sim.boss!
        ..phase = 2
        ..armPhase();
      b.timers.updateAll((_, _) => 999);
      b.timers[BossAttack.slam] = 0.001;
      sim.step(Physics.fixedStep);
      expect(b.slam, SlamState.aiming);
      expect(sim.telegraphs.where((t) => t.slam), hasLength(1));
      steps(sim, BossSpec.slamTelegraph / sim.ballTimeScale + 1.5);
      expect(sim.hull, PlayerSpec.baseHull - 1);
    });

    test('attacks never start closer together than the attack gap', () {
      for (final def in Bosses.all) {
        final sim = bossSim(def);
        final b = sim.boss!
          ..phase = def.phases.length
          ..armPhase();
        b.timers.updateAll((_, _) => 0.0);
        final starts = <double>[];
        var lastTelegraphs = 0;
        var lastZones = 0;
        var lastShots = 0;
        for (var i = 0; i < 120 * 30; i++) {
          sim.invulnerableTimer = 1;
          final gapBefore = b.attackGap;
          sim.step(Physics.fixedStep);
          if (b.attackGap > gapBefore + 1e-9) starts.add(sim.elapsed);
          lastTelegraphs = sim.telegraphs.length;
          lastZones = sim.zones.length;
          lastShots = sim.shots.length;
          if (b.dead) break;
        }
        expect(lastTelegraphs + lastZones + lastShots, greaterThanOrEqualTo(0));
        for (var i = 1; i < starts.length; i++) {
          // Attack gaps tick in paced time.
          expect(
            starts[i] - starts[i - 1],
            greaterThanOrEqualTo(BossSpec.attackGap - 0.02),
            reason: def.name,
          );
        }
        expect(starts.length, greaterThan(3), reason: def.name);
      }
    });

    test('defeating the boss clears the stage and every attack', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      b.plates.fillRange(0, 2, 0);
      b.core = 5;
      sim.zones.add(
        FloorZone(
          kind: ZoneKind.lava,
          x: 100,
          halfWidth: 40,
          warning: 1,
          active: 3,
        ),
      );
      hitCore(sim, 10);
      expect(b.dead, isTrue);
      expect(sim.bossDefeated, isTrue);
      expect(sim.zones, isEmpty);
      expect(sim.events.whereType<BossDefeated>(), hasLength(1));
      steps(sim, 0.1);
      expect(sim.isStageCleared, isTrue);
    });
  });

  group('boss attacks', () {
    test('lightning strikes the warned column only', () {
      final sim = bossSim(Bosses.of(BossId.stormEngine));
      sim.setCannonX(100);
      sim.boss!.timers[BossAttack.zap] = 0.001;
      sim.step(Physics.fixedStep);
      final zaps = sim.telegraphs.where((t) => t.kind == TelegraphKind.zap);
      expect(zaps, isNotEmpty);
      expect(zaps.first.x, closeTo(100, 1));
      expect(sim.hull, PlayerSpec.baseHull);
      // Standing still under the column gets struck.
      steps(sim, BossSpec.zapTelegraph + 0.05);
      expect(sim.hull, PlayerSpec.baseHull - 1);
      expect(sim.events.whereType<ZapStrike>().where((z) => z.hit), isNotEmpty);
    });

    test('stepping out of a lightning column avoids it', () {
      final sim = bossSim(Bosses.of(BossId.stormEngine));
      sim.setCannonX(100);
      sim.boss!.timers[BossAttack.zap] = 0.001;
      sim.step(Physics.fixedStep);
      final targets = sim.telegraphs.map((t) => t.x).toList();
      // Move far from every column before the strike.
      final safe = [60.0, 180.0, 300.0].firstWhere(
        (x) => targets.every(
          (t) =>
              (x - t).abs() >
              BossSpec.zapHalfWidth + CannonSpec.bodyHalfWidth + 2,
        ),
      );
      sim.setCannonX(safe);
      steps(sim, BossSpec.zapTelegraph + 0.05);
      expect(sim.hull, PlayerSpec.baseHull);
    });

    test('lava warns first, then hurts once while you stand in it', () {
      final sim = bossSim(Bosses.of(BossId.moltenTitan));
      sim.setCannonX(180);
      sim.boss!.timers[BossAttack.lava] = 0.001;
      sim.step(Physics.fixedStep);
      expect(sim.zones, hasLength(1));
      final z = sim.zones.first;
      expect(z.armed, isFalse);
      expect(sim.hull, PlayerSpec.baseHull);
      steps(sim, BossSpec.lavaTelegraph + 0.1);
      expect(sim.hull, PlayerSpec.baseHull - 1);
      // Invulnerability passes but the same pool never hurts twice.
      steps(sim, PlayerSpec.hurtInvulnerability + 0.2);
      expect(sim.hull, PlayerSpec.baseHull - 1);
      steps(sim, BossSpec.lavaDuration);
      expect(sim.zones, isEmpty, reason: 'pools burn out');
    });

    test('freezing ground slows the cannon instead of hurting it', () {
      final sim = bossSim(Bosses.of(BossId.frostGuardian));
      sim.setCannonX(180);
      sim.boss!.timers[BossAttack.freeze] = 0.001;
      sim.step(Physics.fixedStep);
      steps(sim, BossSpec.freezeTelegraph + 0.05);
      expect(sim.cannonSlowed, isTrue);
      expect(sim.hull, PlayerSpec.baseHull);
      final x = sim.cannonX;
      sim.moveCannonBy(50);
      expect(sim.cannonX - x, closeTo(50 * BossSpec.freezeMoveScale, 1e-9));
      steps(sim, BossSpec.freezeSlowTime + 0.1);
      expect(sim.cannonSlowed, isFalse);
    });

    test('weaving shots stay within their amplitude', () {
      final sim = bossSim(Bosses.of(BossId.gravityCore));
      sim.setCannonX(40);
      sim.boss!.timers[BossAttack.curve] = 0.001;
      sim.step(Physics.fixedStep);
      expect(sim.shots, hasLength(3));
      final start = {for (final s in sim.shots) s: s.x};
      for (var i = 0; i < 120 * 3; i++) {
        sim.step(Physics.fixedStep);
        for (final s in sim.shots) {
          final drift = s.vx * sim.elapsed;
          expect(
            (s.x - start[s]!).abs(),
            lessThanOrEqualTo(BossSpec.curveAmplitude * 2 + drift.abs() + 1),
          );
        }
      }
    });

    test('gravity pull turns minions but never speeds them up', () {
      final sim = bossSim(Bosses.of(BossId.gravityCore));
      final b = sim.boss!..x = 180;
      final left = Ball(
        id: 1,
        tier: 1,
        maxHp: 9,
        x: 40,
        y: 300,
        vx: -70,
        vy: 0,
      );
      final right = Ball(
        id: 2,
        tier: 1,
        maxHp: 9,
        x: 320,
        y: 300,
        vx: 50,
        vy: 0,
      );
      sim.balls.addAll([left, right]);
      b
        ..phase = 2
        ..armPhase();
      b.timers.updateAll((_, _) => 999);
      b.timers[BossAttack.pull] = 0.001;
      sim.step(Physics.fixedStep);
      expect(sim.events.whereType<BossPulled>(), hasLength(1));
      expect(left.vx, closeTo(70, 1e-9));
      expect(right.vx, closeTo(-50, 1e-9));
    });

    test('the void rift: tiny damage while shut, big while open', () {
      final sim = bossSim(Bosses.of(BossId.voidDevourer));
      final b = sim.boss!;
      expect(b.hasWeakWindows, isTrue);
      b.weak = WeakState.closed;
      var before = b.core;
      hitCore(sim, 100);
      expect(before - b.core, closeTo(100 * BossSpec.weakClosedExposure, 1e-6));
      b.weak = WeakState.open;
      before = b.core;
      hitCore(sim, 100);
      expect(before - b.core, closeTo(100 * BossSpec.weakOpenExposure, 1e-6));
    });

    test('the rift cycles: warning, open, closed', () {
      final sim = bossSim(Bosses.of(BossId.voidDevourer));
      final b = sim.boss!..weakTimer = 0.001;
      sim.step(Physics.fixedStep);
      expect(b.weak, WeakState.warning);
      steps(sim, BossSpec.weakWarning / sim.ballTimeScale + 0.05);
      expect(b.weak, WeakState.open);
      expect(
        sim.events.whereType<WeakPointChanged>().where((e) => e.open),
        hasLength(1),
      );
      steps(sim, BossSpec.weakOpen / sim.ballTimeScale + 0.05);
      expect(b.weak, WeakState.closed);
    });

    test('hydra heads: their element hurts double, others half', () {
      final def = Bosses.of(BossId.prismHydra);
      final sim = GameSimulation(
        loadout: quiet,
        seed: 3,
        arenaHeight: arena,
        plan: BossOnlyPlan(def),
      );
      final b = sim.boss!
        ..transition = 0
        ..y = sim.boss!.homeY;
      b.timers.updateAll((_, _) => 999);
      for (var i = 0; i < def.plates.length; i++) {
        final weak = def.plates[i].weakness!;
        final other = weak == Element.fire ? Element.ice : Element.fire;
        var before = b.plates[i];
        sim.bullets.add(
          Bullet(
            b.plateX(i),
            b.plateY(i) + b.plateRadius(i) + 2,
            10,
            element: weak,
          ),
        );
        sim.step(Physics.fixedStep);
        expect(before - b.plates[i], closeTo(20, 1e-6), reason: '$weak');
        before = b.plates[i];
        sim.bullets.add(
          Bullet(
            b.plateX(i),
            b.plateY(i) + b.plateRadius(i) + 2,
            10,
            element: other,
          ),
        );
        sim.step(Physics.fixedStep);
        // Fire's splash may add a little; the direct hit is halved.
        expect(before - b.plates[i], greaterThanOrEqualTo(5 - 1e-6));
        expect(before - b.plates[i], lessThan(10));
      }
    });

    test('a broken hydra head grows back when the next phase starts', () {
      final sim = bossSim(Bosses.of(BossId.prismHydra));
      final b = sim.boss!;
      b.plates[0] = 0;
      b.plates[1] = 0;
      b.plates[2] = 0;
      b.core = b.coreMax * 0.52;
      hitCore(sim, b.coreMax * 0.05);
      expect(b.phase, 2);
      expect(b.platesLeft, 1);
      expect(sim.events.whereType<BossHeadRegrown>(), hasLength(1));
    });

    test('the iron behemoth opens up one armour section at a time', () {
      final def = Bosses.of(BossId.ironBehemoth);
      expect(def.plates, hasLength(4));
      final sim = bossSim(def);
      final b = sim.boss!;
      for (var broken = 0; broken <= 4; broken++) {
        for (var i = 0; i < 4; i++) {
          b.plates[i] = i < broken ? 0 : b.plateMax;
        }
        expect(b.exposure, def.exposure[broken]);
      }
      for (var i = 1; i < def.exposure.length; i++) {
        expect(def.exposure[i], greaterThan(def.exposure[i - 1]));
      }
    });
  });

  group('boss fights', () {
    test('every boss level can be won by a reasonable player', () {
      final strong = Upgrades.loadoutFor({
        UpgradeType.fireRate: 12,
        UpgradeType.bulletPower: 14,
        UpgradeType.cannonLevel: 5,
        UpgradeType.elementPower: 4,
      }, elements: Element.values.toSet());
      for (var level = 10; level <= 100; level += 10) {
        var won = false;
        // Up to 8 tries; each plays a little differently, like a person.
        for (var attempt = 0; attempt < 8 && !won; attempt++) {
          final sim = GameSimulation(
            loadout: strong,
            seed: SeededRandom.hashString('boomforge-stage-$level') + attempt,
            arenaHeight: 760,
            plan: StagePlan(level),
          );
          final player = AutoPlayer(
            maxSpeed: 520 - 30.0 * (attempt % 4),
            lookAhead: 0.9 + 0.1 * (attempt % 2),
          );
          var maxObjects = 0;
          while (!sim.isFinished && sim.elapsed < 400) {
            player.act(sim);
            sim.step(Physics.fixedStep);
            sim.drainEvents();
            final objects =
                sim.balls.length +
                sim.shots.length +
                sim.telegraphs.length +
                sim.zones.length;
            if (objects > maxObjects) maxObjects = objects;
          }
          expect(maxObjects, lessThan(40), reason: 'level $level');
          won = sim.isStageCleared && sim.bossDefeated;
        }
        // ignore: avoid_print
        if (!won) print('boss of level $level not won');
        expect(won, isTrue, reason: 'boss of level $level');
      }
    });
  });
}
