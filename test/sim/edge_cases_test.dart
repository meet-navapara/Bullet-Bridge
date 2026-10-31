import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/bosses.dart';
import 'package:orbit_blast/game/sim/boss.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

const double arena = 800;

void stepFor(GameSimulation sim, double seconds) {
  for (var t = 0.0; t < seconds && !sim.isFinished; t += Physics.fixedStep) {
    sim.step(Physics.fixedStep);
    sim.drainEvents();
  }
}

void main() {
  test('revive after dying as the last wave empties does not add a wave', () {
    final sim = GameSimulation(
      loadout: Loadout.base,
      seed: 1,
      arenaHeight: arena,
      plan: StagePlan(1),
    )..debugClearSpawnQueue();
    final waves = sim.plan.waveCount!;
    sim.wave = waves;
    sim.hull = 1;
    // The final enemy dies this step...
    final last = Ball(id: 1, tier: 0, maxHp: 1, x: 300, y: 300, vx: 0, vy: 0);
    sim.balls.add(last);
    sim.damageBall(last, 1);
    // ...and a falling shard reaches the cannon in the same step.
    sim.shots.add(EnemyShot(sim.cannonX, sim.floorY - 30, 0, 0));
    sim.step(Physics.fixedStep);
    expect(sim.isOver, isTrue);

    expect(sim.revive(), isTrue);
    stepFor(sim, 5);
    expect(sim.wave, waves, reason: 'no extra wave');
    expect(sim.isStageCleared, isTrue);
  });

  test('revive between waves still counts the cleared wave', () {
    final sim = GameSimulation(
      loadout: Loadout.base,
      seed: 1,
      arenaHeight: arena,
    )..debugClearSpawnQueue();
    sim.hull = 1;
    final last = Ball(id: 1, tier: 0, maxHp: 1, x: 300, y: 300, vx: 0, vy: 0);
    sim.balls.add(last);
    sim.damageBall(last, 1);
    sim.shots.add(EnemyShot(sim.cannonX, sim.floorY - 30, 0, 0));
    sim.step(Physics.fixedStep);
    expect(sim.isOver, isTrue);
    sim.revive();
    stepFor(sim, 1);
    expect(sim.wavesCleared, 1);
  });

  test('boss does not hang at the floor through a phase transition', () {
    final sim = GameSimulation(
      loadout: Loadout.base,
      seed: 1,
      arenaHeight: arena,
    )..debugClearSpawnQueue();
    final boss =
        Boss(
            def: Bosses.of(BossId.crystalColossus),
            balls: List.filled(30, 0),
            throwInterval: 2,
            homeY: 200,
            x: 60,
          )
          ..unitsLeft = 21
          ..slam = SlamState.diving;
    boss.y = sim.floorY - boss.coreRadius;
    sim.boss = boss;
    sim.invulnerableTimer = 100; // keep the cannon out of the way
    sim.cannonX = 300;
    // A ball destroyed that crosses the 2/3 threshold mid-slam.
    final ball = Ball(id: 1, tier: 0, maxHp: 1, x: 200, y: 200, vx: 0, vy: 0);
    sim.balls.add(ball);
    sim.damageBall(ball, 5);
    sim.step(Physics.fixedStep);
    expect(boss.phase, 2);
    final floorY = boss.y;
    stepFor(sim, BossSpec.phaseTransition * 0.9);
    expect(boss.y, lessThan(floorY - 50), reason: 'still parked on the floor');
  });
}
