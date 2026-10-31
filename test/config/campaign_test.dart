import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/config/level_animation.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/seeded_random.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

LevelDef at(int n) => Campaign.level(n);

void main() {
  group('campaign data', () {
    test('1000 levels in 100 chapters, numbered 1-1000', () {
      expect(Campaign.levels, hasLength(1000));
      expect(Campaign.chapters, hasLength(100));
      for (var n = 1; n <= 1000; n++) {
        expect(at(n).number, n);
        expect(at(n).chapter, (n - 1) ~/ 10 + 1);
        expect(at(n).slot, (n - 1) % 10 + 1);
      }
      expect(Campaign.chapters.map((c) => c.name).toSet(), hasLength(100));
      expect(Campaign.chapters.map((c) => c.theme.id).toSet(), hasLength(100));
    });

    test('bosses are exactly every tenth level, each different', () {
      final bosses = [
        for (final l in Campaign.levels)
          if (l.isBoss) l.number,
      ];
      expect(bosses, [for (var n = 10; n <= 1000; n += 10) n]);
      final names = {for (final n in bosses) at(n).boss!.name};
      expect(names, hasLength(100));
      for (final n in bosses) {
        expect(at(n).category, LevelCategory.boss);
        expect(at(n).boss, at(n).chapterDef.boss);
      }
    });

    test('every level definition is valid', () {
      for (final l in Campaign.levels) {
        final why = 'level ${l.number}';
        expect(l.waves, inInclusiveRange(2, 5), reason: why);
        expect(
          l.patterns.length,
          l.isBoss ? l.waves - 1 : l.waves,
          reason: why,
        );
        expect(l.ballsPerWave, inInclusiveRange(1, 6), reason: why);
        expect(l.maxTier, inInclusiveRange(1, BallSpec.maxTier), reason: why);
        expect(l.durability, greaterThan(0), reason: why);
        expect(l.pace, inInclusiveRange(SpeedSpec.minPace, SpeedSpec.maxPace));
        expect(l.drift, inInclusiveRange(1.0, SpeedSpec.maxDrift));
        expect(l.hazardsPerWave, inInclusiveRange(0, 3), reason: why);
        expect(l.clearBonus, greaterThan(0), reason: why);
        expect(l.hint, isNotEmpty, reason: why);
      }
    });

    test('levels are not copies: patterns, mechanics or numbers differ', () {
      String signature(LevelDef l) =>
          '${l.category}|${l.waves}|${l.patterns}|${l.ballsPerWave}|'
          '${l.maxTier}|${l.bounce}|${l.mechanics.length}|${l.boss?.name}';
      final sigs = Campaign.levels.map(signature).toSet();
      expect(sigs.length, greaterThan(800));
      expect(
        Campaign.levels.expand((l) => l.patterns).toSet(),
        containsAll(SpawnPattern.values),
      );
    });

    test('heavy waves are spaced out on generated levels', () {
      const heavy = {
        SpawnPattern.giants,
        SpawnPattern.armored,
        SpawnPattern.armoredSwarm,
      };
      for (final l in Campaign.levels.skip(StageSpec.authoredLevels)) {
        for (var w = 0; w < l.patterns.length; w++) {
          if (!heavy.contains(l.patterns[w])) continue;
          expect(w, lessThan(3), reason: 'level ${l.number}');
          if (w > 0) {
            expect(heavy, isNot(contains(l.patterns[w - 1])));
          }
        }
      }
    });

    test('no level repeats the combination of an earlier level', () {
      final seen = <String, int>{};
      final repeats = <String>[];
      for (final l in Campaign.levels) {
        final earlier = seen[l.combination];
        if (earlier != null) repeats.add('${l.number} copies $earlier');
        seen[l.combination] ??= l.number;
      }
      expect(repeats, isEmpty);
    });

    test('every level has its own animation', () {
      final keys = Campaign.levels.map((l) => l.animation.key).toSet();
      expect(keys, hasLength(1000));
      expect(
        Campaign.levels.map((l) => l.animation.main).toSet(),
        AmbientKind.values.toSet(),
      );
      for (final l in Campaign.levels) {
        expect(l.animation.accent, isNot(l.animation.main));
      }
      for (var n = 2; n <= 1000; n++) {
        expect(at(n).animation.main, isNot(at(n - 1).animation.main));
      }
    });

    test('the first 100 levels keep their hand-tuned curves', () {
      expect(CampaignSpec.durabilityAt(100), closeTo(580, 1));
      expect(at(100).clearBonus, 515);
      expect(at(100).coinScale, closeTo(2.35, 1e-9));
    });

    test('late levels stay within reach of a maxed cannon', () {
      expect(
        CampaignSpec.durabilityAt(1000),
        closeTo(
          CampaignSpec.durabilityAt(100) * (1 + CampaignSpec.lateHpGrowth),
          1e-6,
        ),
      );
      expect(at(1000).clearBonus, at(100).clearBonus);
      expect(at(1000).coinScale, at(100).coinScale);
    });

    test('mechanics are introduced one at a time, then stay available', () {
      final firsts = Campaign.introducedAt;
      expect(firsts.keys.toSet(), Mechanic.values.toSet());
      // At most one new mechanic per level.
      final perLevel = <int, int>{};
      for (final n in firsts.values) {
        perLevel[n] = (perLevel[n] ?? 0) + 1;
      }
      expect(perLevel.values.every((c) => c == 1), isTrue);
      for (final e in firsts.entries) {
        expect(at(e.value).introduces, e.key);
        expect(at(e.value).has(e.key), isTrue);
        if (e.value > 1) expect(at(e.value - 1).has(e.key), isFalse);
        expect(at(1000).has(e.key), isTrue);
      }
      // New mechanics are taught on calm levels, never on hard ones.
      for (final n in firsts.values) {
        expect(
          at(n).category,
          isNot(
            anyOf(
              LevelCategory.hard,
              LevelCategory.preparation,
              LevelCategory.finalTest,
              LevelCategory.boss,
            ),
          ),
          reason: 'level $n',
        );
      }
    });
  });

  group('difficulty curve', () {
    test('every chapter follows the rhythm, with recovery levels', () {
      for (final c in Campaign.chapters) {
        final cats = [
          for (var l = c.firstLevel; l <= c.lastLevel; l++) at(l).category,
        ];
        expect(cats.first, LevelCategory.intro);
        expect(cats[5], LevelCategory.recovery);
        expect(cats.last, LevelCategory.boss);
      }
    });

    test('recovery levels are easier than the levels around them', () {
      for (final c in Campaign.chapters) {
        final challenge = at(c.firstLevel + 4);
        final recovery = at(c.firstLevel + 5);
        final hard = at(c.firstLevel + 6);
        for (final tougher in [challenge, hard]) {
          expect(
            recovery.durability,
            lessThan(tougher.durability),
            reason: 'level ${recovery.number}',
          );
          // Low-bounce levels run slower to compensate for quicker
          // bounces, so compare their pace before that adjustment.
          final tougherPace = tougher.bounce == BounceProfile.low
              ? tougher.pace + SpeedSpec.lowBouncePaceCut
              : tougher.pace;
          expect(recovery.pace, lessThan(tougherPace));
          expect(
            recovery.ballsPerWave,
            lessThanOrEqualTo(tougher.ballsPerWave),
          );
        }
        // A chapter opener is gentler than the previous chapter's final test.
        if (c.number > 1) {
          final opener = at(c.firstLevel);
          final lastTest = at(c.firstLevel - 2);
          expect(opener.durability, lessThan(lastTest.durability));
          expect(opener.pace, lessThan(lastTest.pace));
        }
      }
    });

    test('difficulty rises overall but not on every level', () {
      var drops = 0;
      for (var n = 2; n <= 1000; n++) {
        if (at(n).durability < at(n - 1).durability) drops++;
      }
      expect(drops, greaterThanOrEqualTo(200), reason: 'needs breathers');
      // Chapter averages still climb over the authored chapters.
      double avg(int first, int last) =>
          [for (var l = first; l <= last; l++) at(l).durability]
              .reduce((a, b) => a + b) /
          (last - first + 1);
      for (var c = 2; c <= 10; c++) {
        expect(
          avg((c - 1) * 10 + 1, c * 10),
          greaterThan(avg((c - 2) * 10 + 1, (c - 1) * 10)),
        );
      }
      // Past that the base curve keeps rising, but slowly enough that one
      // world's mix of levels can outweigh it, so compare the far ends.
      for (var n = 101; n <= 1000; n++) {
        expect(
          CampaignSpec.durabilityAt(n),
          greaterThan(CampaignSpec.durabilityAt(n - 1)),
        );
      }
      expect(avg(901, 1000), greaterThan(avg(101, 200)));
    });

    test('speed starts calm and is capped', () {
      expect(at(1).pace, lessThanOrEqualTo(0.5));
      expect(at(1).drift, 1.0);
      for (final l in Campaign.levels) {
        expect(l.pace, lessThanOrEqualTo(SpeedSpec.maxPace));
        expect(l.drift, lessThanOrEqualTo(SpeedSpec.maxDrift));
      }
      // No sudden jumps between neighbouring levels.
      for (var n = 2; n <= 1000; n++) {
        expect((at(n).pace - at(n - 1).pace).abs(), lessThan(0.1));
      }
    });

    test('waves respect spawn and object limits', () {
      for (final l in Campaign.levels) {
        for (var w = 1; w <= l.waves; w++) {
          final plan = WaveDirector.buildLevelWave(
            l,
            w,
            SeededRandom(
              SeededRandom.hashString('boomforge-stage-${l.number}'),
            ),
          );
          final why = 'level ${l.number} wave $w';
          expect(plan.spawns.length, lessThanOrEqualTo(10), reason: why);
          expect(plan.hazards.length, lessThanOrEqualTo(5), reason: why);
          expect(plan.pace, lessThanOrEqualTo(SpeedSpec.maxPace));
          expect(
            plan.spawns.where((s) => s.tier >= BallSpec.maxTier - 1).length,
            lessThanOrEqualTo(2),
            reason: '$why: too many big crystals',
          );
          for (final s in plan.spawns) {
            expect(s.hp, greaterThan(0));
            expect(s.tier, inInclusiveRange(0, BallSpec.maxTier));
            // Only mechanics the level has unlocked appear.
            if (s.kind == EnemyKind.geode) {
              expect(l.has(Mechanic.geodes), isTrue, reason: why);
            }
            if (s.kind == EnemyKind.skyray) {
              expect(l.has(Mechanic.skyrays), isTrue, reason: why);
            }
            if (s.kind == EnemyKind.treasure) {
              expect(l.has(Mechanic.treasure), isTrue, reason: why);
            }
            if (s.affinity != null) {
              expect(l.affinities, contains(s.affinity), reason: why);
            }
          }
          for (final h in plan.hazards) {
            expect(l.hazardKinds, contains(h.kind), reason: why);
          }
        }
      }
    });
  });

  group('speed system', () {
    GameSimulation simFor(int level) => GameSimulation(
      loadout: Loadout.base,
      seed: 1,
      arenaHeight: 760,
      plan: StagePlan(level),
    );

    test('creatures move at the level pace, far below the old speed', () {
      final one = simFor(1);
      expect(one.pace, at(1).pace);
      expect(one.ballTimeScale, at(1).pace);
      // The old game reached time scale 1.0 by stage 8.
      expect(simFor(8).ballTimeScale, lessThan(0.6));
      expect(simFor(1000).ballTimeScale, lessThanOrEqualTo(SpeedSpec.maxPace));
    });

    test('split children and knock-backs never exceed the drift cap', () {
      final sim = simFor(1000)..debugClearSpawnQueue();
      final big = Ball(id: 1, tier: 4, maxHp: 1, x: 180, y: 300, vx: 0, vy: 0);
      sim.balls.add(big);
      sim.damageBall(big, 10, source: DamageSource.bomb, pushFromX: 170);
      sim.step(Physics.fixedStep);
      expect(sim.balls, isNotEmpty);
      for (final b in sim.balls) {
        expect(b.vx.abs(), lessThanOrEqualTo(SpeedSpec.maxDriftSpeed));
      }
    });

    test('low bounce levels bounce lower and run slower', () {
      final low = Campaign.levels.firstWhere(
        (l) => l.bounce == BounceProfile.low,
      );
      expect(low.pace, lessThan(CampaignSpec.paceAt(low.number)));
      final sim = simFor(low.number);
      final normal = simFor(low.number - 1);
      expect(sim.bounceSpeed(3), lessThan(normal.bounceSpeed(3)));
    });

    test('movement is the same at any frame rate', () {
      GameSimulation run(double frame) {
        final sim = simFor(12);
        for (var t = 0.0; t < 10; t += frame) {
          sim.update(frame);
        }
        return sim;
      }

      final a = run(1 / 30);
      final b = run(1 / 144);
      expect(a.elapsed, closeTo(b.elapsed, 0.05));
      expect(a.balls.length, b.balls.length);
    });
  });
}
