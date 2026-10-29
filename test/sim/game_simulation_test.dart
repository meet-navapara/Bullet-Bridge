import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';

const double arena = 800;

GameSimulation makeSim({Loadout loadout = Loadout.base, int seed = 1}) {
  final sim = GameSimulation(loadout: loadout, seed: seed, arenaHeight: arena)
    ..debugClearSpawnQueue()
    ..drainEvents();
  return sim;
}

Ball addBall(
  GameSimulation sim, {
  int tier = 0,
  int hp = 5,
  double x = 200,
  double y = 300,
  double vx = 0,
  double vy = 0,
}) {
  final ball = Ball(
    id: sim.balls.length + 100,
    tier: tier,
    maxHp: hp,
    x: x,
    y: y,
    vx: vx,
    vy: vy,
  );
  sim.balls.add(ball);
  return ball;
}

void main() {
  group('damage and destruction', () {
    test('damage reduces durability and adds score per point dealt', () {
      final sim = makeSim();
      final ball = addBall(sim, hp: 5);
      expect(sim.damageBall(ball, 2), isFalse);
      expect(ball.hp, 3);
      expect(sim.score, 2 * RewardSpec.scorePerDamage);
    });

    test('overkill damage only scores the remaining durability', () {
      final sim = makeSim();
      final ball = addBall(sim, hp: 3);
      expect(sim.damageBall(ball, 10), isTrue);
      expect(sim.score, 3 + RewardSpec.destroyBonusPerTier * 1);
    });

    test('smallest balls are destroyed without splitting', () {
      final sim = makeSim();
      final ball = addBall(sim, tier: 0, hp: 1);
      sim.damageBall(ball, 1);
      sim.step(Physics.fixedStep);
      expect(sim.balls, isEmpty);
      expect(sim.ballsDestroyed, 1);
    });

    test('larger balls split into two children of the next tier', () {
      final sim = makeSim();
      final ball = addBall(sim, tier: 2, hp: 64);
      sim.damageBall(ball, 64);
      final destroyed = sim.events.whereType<BallDestroyed>().toList();
      expect(destroyed, hasLength(1));
      expect(destroyed.single.split, isTrue);
      sim.step(Physics.fixedStep);
      expect(sim.balls, hasLength(2));
      for (final child in sim.balls) {
        expect(child.tier, 1);
        expect(child.maxHp, 32);
        expect(child.hp, 32);
        expect(child.vy, lessThan(0), reason: 'children pop upwards');
      }
      expect(sim.balls.first.vx.sign, isNot(sim.balls.last.vx.sign));
    });

    test('a dead ball cannot be destroyed or rewarded twice', () {
      final sim = makeSim();
      final ball = addBall(sim, tier: 1, hp: 1);
      expect(sim.damageBall(ball, 1), isTrue);
      final scoreAfter = sim.score;
      expect(sim.damageBall(ball, 1), isFalse);
      expect(sim.score, scoreAfter);
      expect(sim.ballsDestroyed, 1);
    });

    test('several bullets hitting in the same step destroy a ball once', () {
      final sim = makeSim(
        loadout: const Loadout(
          shotsPerSecond: 1,
          damage: 1,
          streams: 1,
          coinMultiplier: 1,
          startingShieldLevel: 0,
          cannonLevel: 1,
        ),
      );
      final ball = addBall(sim, tier: 1, hp: 1, x: 200, y: 300);
      for (var i = 0; i < 5; i++) {
        sim.bullets.add(Bullet(200, 300 + ball.radius + 2, 1));
      }
      sim.step(Physics.fixedStep);
      expect(sim.ballsDestroyed, 1);
      expect(sim.balls.where((b) => b.tier == 0), hasLength(2));
      // Only one bullet was consumed by the dead ball; children were not hit
      // in the same step because they spawn after collision processing.
      expect(sim.events.whereType<BallDestroyed>(), hasLength(1));
    });
  });

  group('bullets', () {
    test('swept collision prevents tunnelling through small balls', () {
      final sim = makeSim();
      final ball = addBall(sim, tier: 0, hp: 50, x: 100, y: 300);
      sim.bullets
        ..clear()
        ..add(Bullet(100, 300 + ball.radius + 10, 1));
      // One huge step moves the bullet ~49 units, far past the ball.
      final before = ball.hp;
      sim.step(1 / 20);
      expect(ball.hp, lessThan(before));
    });

    test('auto-fire produces bullets at the configured rate', () {
      final sim = makeSim(
        loadout: const Loadout(
          shotsPerSecond: 10,
          damage: 1,
          streams: 1,
          coinMultiplier: 1,
          startingShieldLevel: 0,
          cannonLevel: 1,
        ),
      );
      var shots = 0;
      for (var i = 0; i < 240; i++) {
        sim.step(Physics.fixedStep);
        shots += sim.drainEvents().whereType<ShotFired>().length;
      }
      // 2 s of firing after the 0.25 s opening delay at 10 shots/s.
      expect(shots, inInclusiveRange(17, 19));
    });

    test('multiple streams fire parallel bullets', () {
      final sim = makeSim(
        loadout: const Loadout(
          shotsPerSecond: 1,
          damage: 1,
          streams: 3,
          coinMultiplier: 1,
          startingShieldLevel: 0,
          cannonLevel: 5,
        ),
      );
      for (var i = 0; i < 40; i++) {
        sim.step(Physics.fixedStep);
      }
      final xs = sim.bullets.map((b) => b.x).toSet();
      expect(xs.length, 3);
    });
  });

  group('cannon movement', () {
    test('movement is clamped to the arena', () {
      final sim = makeSim();
      sim.moveCannonBy(-10000);
      expect(sim.cannonX, CannonSpec.visualHalfWidth);
      sim.moveCannonBy(10000);
      expect(sim.cannonX, sim.width - CannonSpec.visualHalfWidth);
      sim.moveCannonBy(double.nan);
      expect(sim.cannonX, sim.width - CannonSpec.visualHalfWidth);
    });
  });

  group('collision and game over', () {
    test('touching a ball ends the run', () {
      final sim = makeSim();
      sim.hull = 1;
      addBall(sim, tier: 2, hp: 10, x: sim.cannonX, y: sim.floorY - 20);
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isTrue);
      expect(sim.events.whereType<PlayerDestroyed>(), hasLength(1));
      // A finished run ignores further updates and input.
      final score = sim.score;
      sim.update(1);
      sim.moveCannonBy(50);
      expect(sim.score, score);
    });

    test('a ball passing overhead does not end the run', () {
      final sim = makeSim();
      addBall(
        sim,
        tier: 1,
        hp: 10,
        x: sim.cannonX,
        y: sim.floorY - CannonSpec.barrelTipHeight - 40,
      );
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isFalse);
    });

    test('shield absorbs exactly one hit', () {
      final sim = makeSim();
      sim.shieldTimer = 5;
      final ball = addBall(
        sim,
        tier: 2,
        hp: 10,
        x: sim.cannonX,
        y: sim.floorY - 20,
      );
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isFalse);
      expect(sim.shieldActive, isFalse);
      expect(sim.invulnerableTimer, greaterThan(0));
      expect(ball.vy, lessThan(0), reason: 'ball is knocked away');
      // After invulnerability ends, the next hit is fatal.
      sim.invulnerableTimer = 0;
      ball
        ..x = sim.cannonX
        ..y = sim.floorY - 20
        ..vy = 0;
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isFalse);
      expect(sim.hull, PlayerSpec.baseHull - 1);
    });

    test('starting shield level grants a shield that lasts until hit', () {
      final sim = makeSim(
        loadout: const Loadout(
          shotsPerSecond: 6,
          damage: 1,
          streams: 1,
          coinMultiplier: 1,
          startingShieldLevel: 2,
          cannonLevel: 1,
        ),
      );
      expect(sim.shieldActive, isTrue);
      expect(sim.inventory[PowerUpType.shield], 1);
      for (var i = 0; i < 120 * 30; i++) {
        sim.step(Physics.fixedStep);
        sim.invulnerableTimer = 10; // ignore wave balls for this test
      }
      expect(sim.shieldActive, isTrue);
    });

    test('revive works once and grants invulnerability', () {
      final sim = makeSim();
      sim.hull = 1;
      addBall(sim, tier: 2, hp: 10, x: sim.cannonX, y: sim.floorY - 20);
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isTrue);
      expect(sim.revive(), isTrue);
      expect(sim.isOver, isFalse);
      expect(sim.invulnerableTimer, PowerUpSpec.reviveInvulnerability);
      sim.invulnerableTimer = 0;
      sim.hull = 1;
      sim.balls.first
        ..x = sim.cannonX
        ..y = sim.floorY - 20;
      sim.step(Physics.fixedStep);
      expect(sim.isOver, isTrue);
      expect(sim.revive(), isFalse);
    });
  });

  group('power-ups', () {
    test('activation consumes inventory and respects cooldown', () {
      final sim = makeSim();
      expect(sim.activatePowerUp(PowerUpType.slowMotion), isTrue);
      expect(sim.inventory[PowerUpType.slowMotion], 0);
      expect(
        sim.ballTimeScale,
        closeTo(
          WaveSpec.paceAt(sim.difficulty) * PowerUpSpec.slowMotionScale,
          1e-9,
        ),
      );
      expect(
        sim.activatePowerUp(PowerUpType.powerShot),
        isFalse,
        reason: 'global cooldown',
      );
      sim.cooldownTimer = 0;
      expect(sim.activatePowerUp(PowerUpType.powerShot), isTrue);
      expect(sim.currentDamage, PowerUpSpec.powerShotMultiplier);
      expect(sim.powerUpsUsed, 2);
    });

    test('cannot activate without inventory or while already active', () {
      final sim = makeSim();
      expect(sim.activatePowerUp(PowerUpType.shield), isFalse);
      sim.inventory[PowerUpType.slowMotion] = 2;
      sim.activatePowerUp(PowerUpType.slowMotion);
      sim.cooldownTimer = 0;
      expect(sim.activatePowerUp(PowerUpType.slowMotion), isFalse);
    });

    test('timed effects expire', () {
      final sim = makeSim();
      sim.activatePowerUp(PowerUpType.powerShot);
      for (
        var i = 0;
        i < ((PowerUpSpec.powerShotDuration + 0.1) * 120).ceil();
        i++
      ) {
        sim.step(Physics.fixedStep);
      }
      expect(sim.powerShotActive, isFalse);
      expect(sim.currentDamage, 1);
    });

    test('bomb destroys balls in range only', () {
      final sim = makeSim();
      final near = addBall(
        sim,
        tier: 0,
        hp: 40,
        x: sim.cannonX,
        y: sim.floorY - PowerUpSpec.bombHeight,
      );
      final far = addBall(
        sim,
        tier: 0,
        hp: 40,
        x: sim.cannonX,
        y: sim.floorY - PowerUpSpec.bombHeight - PowerUpSpec.bombRadius - 60,
      );
      expect(sim.activatePowerUp(PowerUpType.bomb), isTrue);
      expect(near.dead, isTrue);
      expect(far.dead, isFalse);
      expect(sim.invulnerableTimer, greaterThan(0));
    });

    test('power-ups stop when the run ends', () {
      final sim = makeSim();
      sim.hull = 1;
      addBall(sim, tier: 2, hp: 10, x: sim.cannonX, y: sim.floorY - 20);
      sim.step(Physics.fixedStep);
      expect(sim.canActivate(PowerUpType.bomb), isFalse);
      expect(sim.activatePowerUp(PowerUpType.bomb), isFalse);
    });
  });

  group('coins', () {
    test(
      'coins are collected at the cannon with an exact fractional bonus',
      () {
        final sim = makeSim(
          loadout: const Loadout(
            shotsPerSecond: 6,
            damage: 1,
            streams: 1,
            coinMultiplier: 1.5,
            startingShieldLevel: 0,
            cannonLevel: 1,
          ),
        );
        for (var i = 0; i < 2; i++) {
          sim.pickups.add(
            Pickup(
              kind: PickupKind.coin,
              x: sim.cannonX,
              y: sim.floorY - 8,
              vx: 0,
              vy: 0,
              life: 5,
              value: 1,
            ),
          );
        }
        sim.step(Physics.fixedStep);
        expect(sim.coins, 3); // 1.5 + 1.5
        expect(sim.pickups, isEmpty);
      },
    );

    test('coins far from the cannon stay until they expire', () {
      final sim = makeSim();
      addBall(sim, tier: 0, hp: 999, x: 380, y: 100); // keeps the wave open
      sim.pickups.add(
        Pickup(
          kind: PickupKind.coin,
          x: 10,
          y: sim.floorY - 8,
          vx: 0,
          vy: 0,
          life: 0.5,
          value: 1,
        ),
      );
      sim.cannonX = 300;
      sim.step(Physics.fixedStep);
      expect(sim.pickups, hasLength(1));
      for (var i = 0; i < 70; i++) {
        sim.step(Physics.fixedStep);
      }
      expect(sim.pickups, isEmpty);
      expect(sim.coins, 0);
    });

    test('clearing a wave auto-collects remaining coins', () {
      final sim = makeSim();
      sim.pickups.add(
        Pickup(
          kind: PickupKind.coin,
          x: 10,
          y: sim.floorY - 8,
          vx: 0,
          vy: 0,
          life: 5,
          value: 2,
        ),
      );
      sim.cannonX = 300;
      sim.step(Physics.fixedStep);
      expect(sim.phase, RunPhase.intermission);
      expect(sim.coins, 2);
    });
  });

  group('waves and physics', () {
    test('clearing a wave starts the next one after the intermission', () {
      final sim = makeSim();
      sim.step(Physics.fixedStep);
      expect(sim.events.whereType<WaveCleared>(), hasLength(1));
      expect(sim.wavesCleared, 1);
      for (var i = 0; i < (WaveSpec.intermission * 120).ceil() + 2; i++) {
        sim.step(Physics.fixedStep);
      }
      expect(sim.wave, 2);
      expect(sim.phase, RunPhase.playing);
      expect(sim.remainingInWave, WaveSpec.ballCount(2));
    });

    test('balls stay inside the arena during a long simulation', () {
      final sim = GameSimulation(
        loadout: Loadout.base,
        seed: 99,
        arenaHeight: arena,
      );
      final rng = math.Random(5);
      for (var i = 0; i < 120 * 90; i++) {
        sim.invulnerableTimer = 1; // keep the run alive
        if (i % 30 == 0) sim.moveCannonBy(rng.nextDouble() * 200 - 100);
        sim.step(Physics.fixedStep);
        for (final b in sim.balls) {
          if (b.entering) continue;
          expect(
            b.x,
            inInclusiveRange(b.radius - 0.001, sim.width - b.radius + 0.001),
          );
          expect(b.y, lessThanOrEqualTo(sim.floorY - b.radius + 0.001));
          if (!b.entering) expect(b.y, greaterThanOrEqualTo(b.radius - 0.001));
        }
        sim.drainEvents();
      }
      expect(
        sim.wave,
        greaterThan(1),
        reason: 'base cannon clears early waves',
      );
    });

    test('bounce height depends only on tier, not on prior speed', () {
      final sim = makeSim();
      final ball = addBall(
        sim,
        tier: 3,
        hp: 1000,
        x: 80,
        y: sim.floorY - BallSpec.radius[3] - 1,
        vy: 2000,
      );
      sim.cannonX = 350;
      sim.step(Physics.fixedStep);
      expect(ball.vy, closeTo(-sim.bounceSpeed(3), 0.001));
    });

    test('same seed and inputs produce identical runs', () {
      GameSimulation run() {
        final sim = GameSimulation(
          loadout: Loadout.base,
          seed: 1234,
          arenaHeight: arena,
        );
        for (var i = 0; i < 120 * 40; i++) {
          sim.invulnerableTimer = 1;
          if (i % 50 == 0) sim.moveCannonBy(i.isEven ? 37 : -53);
          sim.step(Physics.fixedStep);
          sim.drainEvents();
        }
        return sim;
      }

      final a = run();
      final b = run();
      expect(a.score, b.score);
      expect(a.wave, b.wave);
      expect(a.coins, b.coins);
      expect(
        a.balls.map((x) => x.x).toList(),
        b.balls.map((x) => x.x).toList(),
      );
    });

    test('long frame deltas are clamped', () {
      final sim = makeSim();
      sim.update(10);
      expect(sim.elapsed, lessThanOrEqualTo(Physics.maxFrameDelta + 1e-9));
    });

    test('arena height is clamped to a playable range', () {
      expect(
        GameSimulation(
          loadout: Loadout.base,
          seed: 1,
          arenaHeight: 100,
        ).arenaHeight,
        Physics.minArenaHeight,
      );
      expect(
        GameSimulation(
          loadout: Loadout.base,
          seed: 1,
          arenaHeight: 5000,
        ).arenaHeight,
        Physics.maxArenaHeight,
      );
    });

    test('spawns are telegraphed on the side away from the cannon', () {
      final sim = GameSimulation(
        loadout: Loadout.base,
        seed: 3,
        arenaHeight: arena,
      );
      sim.setCannonX(30);
      for (var i = 0; i < (WaveSpec.firstSpawnDelay * 120).ceil() + 1; i++) {
        sim.step(Physics.fixedStep);
      }
      expect(sim.pendingSpawns, isNotEmpty);
      expect(sim.pendingSpawns.first.x, greaterThan(sim.width / 2));
    });
  });
}
