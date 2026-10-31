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
import 'mechanics_test.dart' show arena, quiet, steps;

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
  b.throwTimer = 999;
  return sim;
}

/// Destroys one ball of the boss's supply, as a player would.
void smashOne(GameSimulation sim) {
  final b = sim.boss!;
  if (sim.balls.where((x) => !x.dead).isEmpty && b.ballQueue.isNotEmpty) {
    b.throwTimer = 0;
    sim.step(Physics.fixedStep);
  }
  final ball = sim.balls.firstWhere((x) => !x.dead);
  ball.armor = 0;
  sim.damageBall(ball, ball.hp);
  sim.step(Physics.fixedStep);
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

    test('every chapter has its own boss, built on an original', () {
      expect(Bosses.campaign, hasLength(100));
      expect(Bosses.campaign.map((b) => b.name).toSet(), hasLength(100));
      for (var c = 11; c <= 100; c++) {
        final boss = Bosses.forChapter(c);
        final original = Bosses.all[(c - 1) % 10];
        expect(boss.shape, original.shape);
        expect(boss.reward.skinId, isNull, reason: 'skins come from originals');
        for (var p = 0; p < boss.phases.length; p++) {
          expect(
            boss.phases[p].attacks,
            containsAll(original.phases[p].attacks),
          );
          expect(boss.phases[p].attacks.length, lessThanOrEqualTo(4));
        }
      }
    });

    test('every boss definition is consistent and fits the arena', () {
      for (final b in Bosses.campaign) {
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

  group('boss balls', () {
    final colossus = Bosses.of(BossId.crystalColossus);

    test('entrance: starts above the arena, then descends and throws', () {
      final sim = GameSimulation(
        loadout: quiet,
        seed: 1,
        arenaHeight: arena,
        plan: BossOnlyPlan(colossus),
      );
      final b = sim.boss!;
      expect(b.y, lessThan(0));
      expect(b.transition, BossSpec.entranceTime);
      steps(sim, BossSpec.entranceTime - 0.1);
      expect(sim.balls, isEmpty, reason: 'no throwing during the entrance');
      steps(sim, 2);
      expect(b.y, closeTo(b.homeY, 2));
      expect(sim.events.whereType<BossThrew>(), isNotEmpty);
    });

    test('it keeps throwing until its supply is gone', () {
      final sim = bossSim(colossus);
      final b = sim.boss!..throwTimer = 0;
      final supply = b.ballQueue.length;
      expect(supply, greaterThan(5));
      var thrown = 0;
      for (var i = 0; i < 120 * 300 && b.ballQueue.isNotEmpty; i++) {
        sim.invulnerableTimer = 1;
        sim.step(Physics.fixedStep);
        thrown += sim.drainEvents().whereType<BossThrew>().length;
        // Keep room in the arena, so nothing but the supply limits it.
        for (final ball in List<Ball>.of(sim.balls)) {
          ball.armor = 0;
          sim.damageBall(ball, ball.hp);
        }
      }
      expect(thrown, supply);
    });

    test('throws wait while the arena is full', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      for (var i = 0; i < BossSpec.maxThrownAlive; i++) {
        sim.balls.add(
          Ball(
            id: 900 + i,
            tier: 0,
            maxHp: 9,
            x: 60.0 + i,
            y: 300,
            vx: 0,
            vy: 0,
          ),
        );
      }
      final left = b.ballQueue.length;
      b.throwTimer = 0;
      sim.invulnerableTimer = 100;
      steps(sim, 1);
      expect(b.ballQueue.length, left, reason: 'none lost while waiting');
    });

    test('bullets pass through the boss and do not hurt it', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      final health = b.unitsLeft;
      final bullet = Bullet(b.x, b.y + b.coreRadius + 2, 9999);
      sim.bullets.add(bullet);
      sim.step(Physics.fixedStep);
      expect(b.unitsLeft, health);
      expect(bullet.dead, isFalse, reason: 'it flies on');
      expect(sim.events.whereType<BossShielded>(), hasLength(1));
    });

    test('a bomb on the boss does not hurt it, only its balls count', () {
      final sim = bossSim(colossus);
      final b = sim.boss!;
      final health = b.unitsLeft;
      sim.inventory[PowerUpType.bomb] = 1;
      sim.activatePowerUp(PowerUpType.bomb);
      sim.step(Physics.fixedStep);
      expect(b.unitsLeft, health);
    });

    test('every piece destroyed takes health; split pieces count too', () {
      expect(Boss.piecesOf(0), 1);
      expect(Boss.piecesOf(1), 3);
      expect(Boss.piecesOf(3), 15);
      final sim = bossSim(colossus);
      final b = sim.boss!;
      expect(
        b.unitsTotal,
        b.ballQueue.fold<int>(0, (sum, t) => sum + Boss.piecesOf(t)),
      );
      var health = b.unitsLeft;
      for (var i = 0; i < 5; i++) {
        smashOne(sim);
        expect(b.unitsLeft, health - 1);
        health = b.unitsLeft;
      }
      expect(b.coreFraction, closeTo(health / b.unitsTotal, 1e-9));
    });

    test('every boss goes down exactly when its last ball is gone', () {
      for (final def in Bosses.campaign) {
        final sim = bossSim(def);
        final b = sim.boss!;
        final seen = <int>[1];
        var guard = 0;
        while (!b.dead && guard++ < 5000) {
          sim.invulnerableTimer = 100;
          b
            ..transition = 0
            ..y = b.homeY
            ..slam = SlamState.none;
          b.timers.updateAll((_, _) => 999);
          expect(b.dead, isFalse);
          final live = sim.balls.where((x) => !x.dead);
          if (live.isEmpty && b.ballQueue.isEmpty) {
            sim.step(Physics.fixedStep);
            continue;
          }
          smashOne(sim);
          if (b.phase != seen.last) seen.add(b.phase);
        }
        expect(b.dead, isTrue, reason: def.name);
        expect(b.unitsLeft, 0, reason: def.name);
        expect(b.ballQueue, isEmpty, reason: def.name);
        expect(sim.bossDefeated, isTrue, reason: def.name);
        expect(seen, [
          for (var p = 1; p <= def.phases.length; p++) p,
        ], reason: def.name);
      }
    });

    test('armour falls off as health drops', () {
      final sim = bossSim(Bosses.of(BossId.ironBehemoth));
      final b = sim.boss!;
      expect(b.platesLeft, 4);
      var last = b.platesLeft;
      while (b.unitsLeft > 1) {
        b.transition = 0;
        b.y = b.homeY;
        sim.invulnerableTimer = 100;
        b.timers.updateAll((_, _) => 999);
        smashOne(sim);
        expect(b.platesLeft, lessThanOrEqualTo(last));
        last = b.platesLeft;
      }
      expect(b.platesLeft, 0);
      expect(sim.events.whereType<BossPlateBroken>(), hasLength(4));
    });

    test('each phase throws faster, and harder chapters throw more', () {
      final b = bossSim(colossus).boss!;
      final first = b.currentThrowInterval;
      b.phase = 2;
      expect(b.currentThrowInterval, lessThan(first));
      expect(
        BossSpec.throwIntervalFor(10),
        lessThan(BossSpec.throwIntervalFor(1)),
      );
      for (var c = 2; c <= StageSpec.chapters; c++) {
        expect(
          BossSpec.ballCountFor(c),
          greaterThanOrEqualTo(BossSpec.ballCountFor(c - 1)),
        );
        expect(BossSpec.ballCountFor(c), lessThanOrEqualTo(BossSpec.ballsMax));
      }
    });

    test('a supply is the same size for any seed and starts small', () {
      var calls = 0;
      double random() => (calls++ * 0.37) % 1;
      for (final chapter in [1, 5, 10, 50, 100]) {
        final plan = BossSpec.ballPlan(chapter, random);
        expect(plan, hasLength(BossSpec.ballCountFor(chapter)));
        final top = BossSpec.maxThrownTierFor(chapter);
        expect(plan.every((t) => t >= 0 && t <= top), isTrue);
        final half = plan.length ~/ 2;
        final early = plan.take(half).reduce((a, b) => a + b);
        final late = plan.skip(half).reduce((a, b) => a + b);
        expect(late, greaterThan(early), reason: 'chapter $chapter');
      }
    });

    test('defeating the boss clears the stage and every attack', () {
      final sim = bossSim(colossus);
      final b = sim.boss!..ballQueue.clear();
      sim.zones.add(
        FloorZone(
          kind: ZoneKind.lava,
          x: 100,
          halfWidth: 40,
          warning: 1,
          active: 3,
        ),
      );
      sim.step(Physics.fixedStep);
      expect(b.dead, isTrue);
      expect(sim.bossDefeated, isTrue);
      expect(sim.zones, isEmpty);
      expect(sim.events.whereType<BossDefeated>(), hasLength(1));
      steps(sim, 0.1);
      expect(sim.isStageCleared, isTrue);
    });
  });

  group('boss engine', () {
    final colossus = Bosses.of(BossId.crystalColossus);

    test('shard rain is telegraphed before it falls', () {
      final sim = bossSim(colossus);
      sim.boss!.timers[BossAttack.rain] = 0.001;
      sim.step(Physics.fixedStep);
      final columns = sim.telegraphs.length;
      expect(columns, inInclusiveRange(2, 3));
      expect(sim.shots, isEmpty);
      steps(sim, BossSpec.rainTelegraph + 0.02);
      // The cannon keeps firing, and can shoot down the column aimed at it.
      expect(sim.shots.length, inInclusiveRange(columns - 1, columns));
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
      for (final def in Bosses.campaign) {
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
