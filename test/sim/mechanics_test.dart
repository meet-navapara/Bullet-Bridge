import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/seeded_random.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

const double arena = 800;

final allElements = Loadout.base.copyWith(elements: Element.values.toSet());

/// A loadout that fires rarely so tests control every hit.
const quiet = Loadout(
  shotsPerSecond: 0.01,
  damage: 1,
  streams: 1,
  coinMultiplier: 1,
  startingShieldLevel: 0,
  cannonLevel: 1,
  elements: {Element.kinetic, Element.fire, Element.ice, Element.electric},
);

GameSimulation makeSim({Loadout loadout = quiet, RunPlan? plan}) {
  final sim = GameSimulation(
    loadout: loadout,
    seed: 7,
    arenaHeight: arena,
    plan: plan ?? const EndlessPlan(),
  )..debugClearSpawnQueue();
  sim.drainEvents();
  if (plan == null) {
    // A frozen crystal parked in the top-left corner keeps the wave open
    // (an empty arena would count as cleared) without interfering.
    sim.balls.add(
      Ball(id: 1, tier: 0, maxHp: 1 << 30, x: 14, y: 14, vx: 0, vy: 0)
        ..frozen = 1e9,
    );
  }
  return sim;
}

Ball addBall(
  GameSimulation sim, {
  int tier = 0,
  int hp = 50,
  double x = 200,
  double y = 300,
  EnemyKind kind = EnemyKind.shard,
  double armor = 0,
}) {
  final b = Ball(
    id: 900 + sim.balls.length,
    tier: tier,
    maxHp: hp,
    x: x,
    y: y,
    vx: 0,
    vy: 0,
    kind: kind,
    armor: armor,
  );
  sim.balls.add(b);
  return b;
}

Hazard addHazard(
  GameSimulation sim,
  HazardKind kind,
  double x,
  double y, {
  double hp = 1,
}) {
  final hz = Hazard(
    id: 500 + sim.hazards.length,
    kind: kind,
    x: x,
    y: y,
    maxHp: hp,
  );
  sim.hazards.add(hz);
  return hz;
}

/// Fires one bullet straight up at x from just below y.
void shoot(
  GameSimulation sim,
  double x,
  double y, {
  Element element = Element.kinetic,
  double damage = 1,
}) {
  sim.bullets.add(Bullet(x, y, damage, element: element));
  sim.step(Physics.fixedStep);
}

void steps(GameSimulation sim, double seconds) {
  for (var i = 0; i < (seconds * 120).round(); i++) {
    sim.step(Physics.fixedStep);
  }
}

void main() {
  group('elements', () {
    test('locked elements cannot be selected', () {
      final sim = GameSimulation(
        loadout: Loadout.base,
        seed: 1,
        arenaHeight: arena,
      );
      expect(sim.setElement(Element.fire), isFalse);
      expect(sim.element, Element.kinetic);
      final unlocked = GameSimulation(
        loadout: allElements,
        seed: 1,
        arenaHeight: arena,
      );
      expect(unlocked.setElement(Element.ice), isTrue);
      expect(unlocked.element, Element.ice);
    });

    test('fire splashes neighbours but kinetic does not', () {
      for (final (element, expectHit) in [
        (Element.fire, true),
        (Element.kinetic, false),
      ]) {
        final sim = makeSim();
        final target = addBall(sim, x: 200, y: 300);
        final neighbour = addBall(sim, x: 225, y: 300);
        shoot(sim, 200, 300 + target.radius + 2, element: element, damage: 10);
        expect(neighbour.hp < 50, expectHit, reason: element.name);
      }
    });

    test('ice chills, then freezes after enough hits; frozen enemies stop', () {
      final sim = makeSim();
      final b = addBall(sim, hp: 1000, x: 200, y: 300)..vx = 80;
      shoot(sim, b.x, b.y + b.radius + 2, element: Element.ice);
      expect(b.chill, greaterThan(0));
      expect(b.isFrozen, isFalse);
      for (var i = 1; i < ElementSpec.freezeStacks; i++) {
        shoot(sim, b.x, b.y + b.radius + 2, element: Element.ice);
      }
      expect(b.isFrozen, isTrue);
      final x = b.x;
      final y = b.y;
      steps(sim, 0.5);
      expect(b.x, x);
      expect(b.y, y);
      steps(sim, ElementSpec.freezeDuration);
      expect(b.isFrozen, isFalse);
    });

    test('frozen enemies take shatter bonus from fire', () {
      final sim = makeSim();
      final b = addBall(sim, hp: 100)..frozen = 5;
      sim.damageBall(b, 10, element: Element.fire);
      expect(b.hp, closeTo(100 - 10 * ElementSpec.shatterBonus, 1e-9));
    });

    test('electric arcs to the nearest targets within range only', () {
      final sim = makeSim();
      final target = addBall(sim, x: 100, y: 300);
      final near = addBall(sim, x: 160, y: 300);
      final far = addBall(sim, x: 380, y: 300);
      shoot(
        sim,
        100,
        300 + target.radius + 2,
        element: Element.electric,
        damage: 10,
      );
      expect(near.hp, lessThan(50));
      expect(far.hp, 50);
      expect(sim.events.whereType<ArcZap>(), isNotEmpty);
    });
  });

  group('geodes', () {
    test('armour absorbs damage first; fire breaks it twice as fast', () {
      final sim = makeSim();
      final g = addBall(sim, tier: 2, hp: 20, kind: EnemyKind.geode, armor: 10);
      sim.damageBall(g, 4);
      expect(g.armor, 6);
      expect(g.hp, 20);
      sim.damageBall(g, 3, element: Element.fire);
      expect(g.armor, 0);
      expect(sim.events.whereType<ArmorBroken>(), hasLength(1));
      sim.damageBall(g, 5);
      expect(g.hp, 15);
      expect(g.displayHp, 15);
    });
  });

  group('hazards and chain reactions', () {
    test('breaking one blaze crystal detonates its neighbour in sequence', () {
      final sim = makeSim();
      final a = addHazard(sim, HazardKind.blaze, 100, 300);
      addHazard(sim, HazardKind.blaze, 180, 300);
      shoot(sim, 100, 300 + a.radius + 2);
      final first = sim.events.whereType<HazardDetonated>().toList();
      expect(first, hasLength(1));
      expect(first.single.depth, 1);
      sim.drainEvents();
      steps(sim, HazardSpec.chainDelay + 0.02);
      final second = sim.drainEvents().whereType<HazardDetonated>().toList();
      expect(second, hasLength(1));
      expect(second.single.depth, 2);
      expect(sim.hazards, isEmpty);
      expect(sim.chainCount, greaterThanOrEqualTo(2));
    });

    test('blasts destroy nearby crystals and a big chain pays a bonus', () {
      final sim = makeSim();
      final hz = addHazard(sim, HazardKind.blaze, 200, 300);
      for (var i = 0; i < 4; i++) {
        addBall(sim, hp: 1, x: 140.0 + i * 40, y: 400);
      }
      shoot(sim, 200, 300 + hz.radius + 2);
      expect(sim.ballsDestroyed, 4);
      expect(sim.chainCount, 5); // detonation + 4 kills
      final coins = sim.coins;
      steps(sim, ChainSpec.window + 0.1);
      final ended = sim.drainEvents().whereType<ChainEnded>().toList();
      expect(ended, hasLength(1));
      expect(ended.single.count, 5);
      expect(sim.coins, greaterThanOrEqualTo(coins + 5));
      expect(sim.bestChain, 5);
    });

    test('frost crystals freeze enemies in range', () {
      final sim = makeSim();
      final hz = addHazard(sim, HazardKind.frost, 200, 300);
      final near = addBall(sim, hp: 1000, x: 250, y: 320);
      final far = addBall(sim, hp: 1000, x: 390, y: 600);
      shoot(sim, 200, 300 + hz.radius + 2);
      expect(near.isFrozen, isTrue);
      expect(far.isFrozen, isFalse);
    });

    test('storm crystals arc to several targets', () {
      final sim = makeSim();
      final hz = addHazard(sim, HazardKind.storm, 200, 300);
      final targets = [
        for (var i = 0; i < 7; i++)
          addBall(sim, hp: 1000, x: 60.0 + i * 45, y: 380),
      ];
      shoot(sim, 200, 300 + hz.radius + 2);
      final damaged = targets.where((b) => b.hp < 1000).length;
      expect(damaged, HazardSpec.stormTargets);
    });

    test('hazards block bullets', () {
      final sim = makeSim();
      final hz = addHazard(sim, HazardKind.blaze, 200, 300, hp: 100);
      final behind = addBall(sim, hp: 50, x: 200, y: 200);
      shoot(sim, 200, 300 + hz.radius + 2, damage: 5);
      expect(hz.hp, 95);
      expect(behind.hp, 50);
    });
  });

  group('skyrays and enemy shots', () {
    test(
      'skyrays drop shards that damage the hull, and bullets destroy shards',
      () {
        final sim = makeSim();
        final ray =
            addBall(
                sim,
                tier: 1,
                hp: 50,
                kind: EnemyKind.skyray,
                x: sim.cannonX,
                y: 150,
              )
              ..flyY = 150
              ..vx = 0
              ..dropTimer = 0.001;
        sim.step(Physics.fixedStep);
        expect(sim.shots, hasLength(1));
        expect(ray.y, lessThan(200));
        sim.shots.single
          ..x = sim.cannonX
          ..y = sim.floorY - 30
          ..vx = 0;
        sim.step(Physics.fixedStep);
        expect(sim.hull, PlayerSpec.baseHull - 1);
        expect(sim.events.whereType<PlayerHurt>(), hasLength(1));

        sim.shots.add(EnemyShot(100, 300, 0, 0));
        shoot(sim, 100, 312);
        expect(sim.shots, isEmpty);
      },
    );
  });

  group('hull', () {
    test('three hits end the run, with invulnerability between hits', () {
      final sim = makeSim();
      for (var hit = 1; hit <= PlayerSpec.baseHull; hit++) {
        sim.invulnerableTimer = 0;
        sim.shots.add(EnemyShot(sim.cannonX, sim.floorY - 30, 0, 0));
        sim.step(Physics.fixedStep);
        if (hit < PlayerSpec.baseHull) {
          expect(sim.isOver, isFalse);
          expect(sim.invulnerableTimer, greaterThan(0));
          // A second hit during invulnerability is ignored.
          sim.shots.add(EnemyShot(sim.cannonX, sim.floorY - 30, 0, 0));
          sim.step(Physics.fixedStep);
          expect(sim.hull, PlayerSpec.baseHull - hit);
        }
      }
      expect(sim.isOver, isTrue);
      expect(sim.stars, 1);
    });
  });

  group('stages', () {
    test('a stage ends after its last wave with stars for a clean run', () {
      final plan = StagePlan(1);
      final sim = GameSimulation(
        loadout: quiet,
        seed: 3,
        arenaHeight: arena,
        plan: plan,
      );
      var guard = 0;
      while (!sim.isFinished && guard++ < 120 * 120) {
        sim.invulnerableTimer = 1;
        for (final b in List<Ball>.of(sim.balls)) {
          b.armor = 0;
          sim.damageBall(b, b.hp);
        }
        for (final hz in List<Hazard>.of(sim.hazards)) {
          sim.hazards.remove(hz);
        }
        sim.step(Physics.fixedStep);
      }
      expect(sim.isStageCleared, isTrue);
      expect(sim.wavesCleared, plan.waveCount);
      expect(sim.stars, 3);
      // A cleared stage ignores further updates.
      final score = sim.score;
      sim.update(1);
      expect(sim.score, score);
    });

    test('chapter 1 introduces one feature per level', () {
      Features at(int level) => Features.forLevel(Campaign.level(level));
      expect(at(1).hazardKinds, isEmpty);
      expect(at(2).hazardKinds, [HazardKind.blaze]);
      expect(at(3).geodes, isTrue);
      expect(at(4).skyrays, isFalse);
      expect(at(5).skyrays, isTrue);
      expect(at(6).hazardKinds, hasLength(3));
    });

    test('stage waves are identical every attempt', () {
      List<String> describe() {
        final plan = StagePlan(6)
            .wave(2, SeededRandom(SeededRandom.hashString('s')));
        return [
          for (final s in plan.spawns) '${s.kind.name}/${s.tier}/${s.hp}',
          for (final h in plan.hazards)
            '${h.kind.name}@${h.xFrac.toStringAsFixed(3)}',
        ];
      }

      expect(describe(), describe());
    });

    test('every tenth level ends with its chapter boss', () {
      final ten = StagePlan(10);
      expect(ten.wave(ten.waveCount, SeededRandom(1)).isBoss, isTrue);
      expect(ten.wave(1, SeededRandom(1)).isBoss, isFalse);
      final nine = StagePlan(9);
      expect(nine.wave(nine.waveCount, SeededRandom(1)).isBoss, isFalse);
      expect(
        StagePlan(50).wave(2, SeededRandom(1)).boss?.name,
        'Void Devourer',
      );
    });
  });
}
