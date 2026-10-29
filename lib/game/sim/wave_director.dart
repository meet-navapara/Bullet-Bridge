import 'dart:math' as math;

import '../../config/balance.dart';
import '../../config/bosses.dart';
import '../../config/campaign.dart';
import 'entities.dart';
import 'seeded_random.dart';

/// One enemy scheduled to enter during a wave.
class WaveSpawn {
  const WaveSpawn({
    required this.tier,
    required this.hp,
    this.kind = EnemyKind.shard,
    this.armor = 0,
    this.affinity,
    this.speedFactor = 1,
  });
  final int tier;
  final int hp;
  final EnemyKind kind;
  final double armor;
  final Element? affinity;

  /// Multiplier on the crystal's horizontal speed (giants are slower).
  final double speedFactor;
}

/// A volatile crystal placed at a fraction of the arena.
class HazardPlacement {
  const HazardPlacement(this.kind, this.xFrac, this.yFrac);
  final HazardKind kind;
  final double xFrac;
  final double yFrac;
}

class WavePlan {
  const WavePlan({
    required this.spawns,
    required this.hazards,
    required this.difficulty,
    this.boss,
    this.scale,
    this.pace,
    this.drift,
    this.bounce = BounceProfile.normal,
    this.spawnGap,
  });
  final List<WaveSpawn> spawns;
  final List<HazardPlacement> hazards;

  /// Equivalent endless wave number (endless/daily scaling).
  final double difficulty;

  /// Boss fought in this wave, if any.
  final BossDef? boss;

  /// Campaign values; null means "derive from [difficulty]" (endless).
  final double? scale;
  final double? pace;
  final double? drift;
  final BounceProfile bounce;
  final double? spawnGap;

  bool get isBoss => boss != null;
}

/// Which enemy types and hazards are in play at a given difficulty.
class Features {
  const Features({
    this.blaze = false,
    this.geodes = false,
    this.frost = false,
    this.skyrays = false,
    this.storm = false,
  });
  final bool blaze;
  final bool geodes;
  final bool frost;
  final bool skyrays;
  final bool storm;

  /// Endless/daily mode ramps up by wave.
  factory Features.forWave(int wave) => Features(
    blaze: wave >= 2,
    geodes: wave >= 4,
    frost: wave >= 6,
    skyrays: wave >= 7,
    storm: wave >= 8,
  );

  /// Enemy types and hazards unlocked by a campaign level.
  factory Features.forLevel(LevelDef level) => Features(
    blaze: level.has(Mechanic.blaze),
    geodes: level.has(Mechanic.geodes),
    frost: level.has(Mechanic.frost),
    skyrays: level.has(Mechanic.skyrays),
    storm: level.has(Mechanic.storm),
  );

  List<HazardKind> get hazardKinds => [
    if (blaze) HazardKind.blaze,
    if (frost) HazardKind.frost,
    if (storm) HazardKind.storm,
  ];
}

/// Describes a whole run: a finite campaign stage or endless waves.
abstract interface class RunPlan {
  /// Null for endless runs.
  int? get waveCount;
  WavePlan wave(int number, SeededRandom rng);
}

class EndlessPlan implements RunPlan {
  const EndlessPlan();

  @override
  int? get waveCount => null;

  @override
  WavePlan wave(int number, SeededRandom rng) =>
      WaveDirector.buildPlan(number.toDouble(), Features.forWave(number), rng);
}

/// A campaign level (1-100) built from its [LevelDef].
class StagePlan implements RunPlan {
  StagePlan(this.stage) : level = Campaign.level(stage);
  final int stage;
  final LevelDef level;

  bool get isBossStage => level.isBoss;

  @override
  int get waveCount => level.waves;

  @override
  WavePlan wave(int number, SeededRandom rng) =>
      WaveDirector.buildLevelWave(level, number, rng);
}

/// Builds wave contents. Pure function of its inputs and the rng, so
/// seeded runs (stages, daily challenge) are identical for every player.
abstract final class WaveDirector {
  /// Original durability-only wave, kept for the endless balance report.
  static List<WaveSpawn> buildWave(int wave, SeededRandom rng) =>
      buildPlan(wave.toDouble(), const Features(), rng).spawns;

  /// Endless/daily wave at difficulty [d].
  static WavePlan buildPlan(double d, Features f, SeededRandom rng) {
    final w = d.round().clamp(1, 1000);
    final count = WaveSpec.ballCount(w);
    final maxTier = WaveSpec.maxTierFor(w);
    final minTier = math.max(0, maxTier - 2);
    final scale = scaleAt(d);

    final spawns = <WaveSpawn>[];
    var skyrays = 0;
    for (var i = 0; i < count; i++) {
      // The first enemy of every wave is the biggest available shard.
      final tier = i == 0
          ? maxTier
          : minTier + rng.nextInt(maxTier - minTier + 1);
      final jitter = 1 + rng.range(-WaveSpec.hpJitter, WaveSpec.hpJitter);
      final roll = rng.nextDouble();
      if (i > 0 && f.skyrays && skyrays < 2 && roll < 0.2) {
        skyrays++;
        spawns.add(_skyray(scale * jitter));
        continue;
      }
      final hp = _hp(scale * WaveSpec.tierHpFactor[tier] * jitter);
      if (f.geodes && tier >= 2 && roll > 0.65) {
        spawns.add(_geode(tier, hp));
      } else {
        spawns.add(WaveSpawn(tier: tier, hp: hp));
      }
    }
    return WavePlan(
      spawns: spawns,
      hazards: _scatterHazards(f.hazardKinds, _hazardCount(d), rng),
      difficulty: d,
    );
  }

  /// Wave [number] of a campaign [level].
  static WavePlan buildLevelWave(LevelDef level, int number, SeededRandom rng) {
    final scale =
        level.durability * (1 + CampaignSpec.waveHpRamp * (number - 1));
    // Endless-equivalent difficulty, only used for blast damage and skyray
    // drop timing; durability comes from [scale].
    final d = 1 + level.number * 0.25 + (number - 1) * 0.5;
    final boss = level.boss;
    if (boss != null && number == level.waves) {
      return WavePlan(
        spawns: const [],
        hazards: [
          if (level.has(Mechanic.blaze))
            const HazardPlacement(HazardKind.blaze, 0.2, 0.42),
          if (level.has(Mechanic.storm))
            const HazardPlacement(HazardKind.storm, 0.8, 0.42)
          else if (level.has(Mechanic.frost))
            const HazardPlacement(HazardKind.frost, 0.8, 0.42),
        ],
        difficulty: d,
        boss: boss,
        scale: scale,
        pace: level.pace,
        drift: level.drift,
        bounce: level.bounce,
      );
    }
    final pattern = level.patterns[(number - 1) % level.patterns.length];
    final f = Features.forLevel(level);
    // A boss level's warm-up should not cost hull before the fight.
    final warmUp = boss != null;
    final count = math.min(
      WaveSpec.maxBallsPerWave + 2,
      level.ballsPerWave + (number >= 3 ? 1 : 0),
    );
    final spawns = _patternSpawns(
      pattern,
      level,
      f,
      count,
      warmUp ? scale * 0.6 : scale,
      rng,
      maxTier: warmUp ? math.min(level.maxTier, 3) : level.maxTier,
    );
    final hazards = pattern == SpawnPattern.hazardField
        ? _cluster(level, rng)
        : _scatterHazards(level.hazardKinds, level.hazardsPerWave, rng);
    return WavePlan(
      spawns: spawns,
      hazards: hazards,
      difficulty: d,
      scale: scale,
      pace: level.pace,
      drift: level.drift,
      bounce: level.bounce,
      spawnGap: switch (pattern) {
        SpawnPattern.swarm || SpawnPattern.armoredSwarm => 1.0,
        SpawnPattern.giants => 3.6,
        _ => math.max(1.5, 3.0 - level.chapter * 0.1),
      },
    );
  }

  static List<WaveSpawn> _patternSpawns(
    SpawnPattern pattern,
    LevelDef level,
    Features f,
    int count,
    double scale,
    SeededRandom rng, {
    required int maxTier,
  }) {
    final minTier = math.max(0, maxTier - 3);
    double jitter() => 1 + rng.range(-WaveSpec.hpJitter, WaveSpec.hpJitter);
    int hpFor(int tier, [double mult = 1]) =>
        _hp(scale * WaveSpec.tierHpFactor[tier] * jitter() * mult);
    // Fairness: the first crystal is the biggest; at most one more of the
    // two largest sizes per wave, so there is always room to dodge.
    var big = 1;
    int randomTier() {
      final top = big >= 2 ? maxTier - 2 : maxTier - 1;
      final hi = math.max(minTier, top);
      final t = minTier + rng.nextInt(hi - minTier + 1);
      if (t >= maxTier - 1) big++;
      return t;
    }

    Element? affinity() {
      final list = level.affinities;
      return list.isEmpty ? null : list[rng.nextInt(list.length)];
    }

    final out = <WaveSpawn>[];
    switch (pattern) {
      case SpawnPattern.standard:
        var skyrays = 0;
        for (var i = 0; i < count; i++) {
          final tier = i == 0 ? maxTier : randomTier();
          final roll = rng.nextDouble();
          if (i > 0 && f.skyrays && skyrays < 1 && roll < 0.15) {
            skyrays++;
            out.add(_skyray(scale * jitter()));
          } else if (f.geodes && tier >= 2 && roll > 0.7) {
            out.add(_geode(tier, hpFor(tier)));
          } else {
            out.add(WaveSpawn(tier: tier, hp: hpFor(tier)));
          }
        }
      case SpawnPattern.swarm:
        final n = math.min(8, count + 2);
        for (var i = 0; i < n; i++) {
          final tier = math.min(maxTier, rng.nextInt(2));
          out.add(WaveSpawn(tier: tier, hp: hpFor(tier, 0.85)));
        }
      case SpawnPattern.giants:
        final giants = count >= 4 ? 2 : 1;
        final geodeGiants = level.has(Mechanic.geodeGiants);
        for (var i = 0; i < giants; i++) {
          final hp = hpFor(BallSpec.maxTier, 1.5);
          out.add(
            geodeGiants && i == 0
                ? _geode(BallSpec.maxTier, hp, speedFactor: 0.7)
                : WaveSpawn(tier: BallSpec.maxTier, hp: hp, speedFactor: 0.7),
          );
        }
        for (var i = giants; i < math.max(giants + 1, count - 2); i++) {
          out.add(WaveSpawn(tier: 1, hp: hpFor(1)));
        }
      case SpawnPattern.armored:
        for (var i = 0; i < count; i++) {
          final tier = i == 0 ? maxTier : math.max(2, randomTier());
          final shell = !f.geodes ? false : (i.isEven || rng.nextBool());
          out.add(
            shell
                ? _geode(tier, hpFor(tier))
                : WaveSpawn(tier: tier, hp: hpFor(tier)),
          );
        }
      case SpawnPattern.armoredSwarm:
        final n = math.min(6, count + 1);
        for (var i = 0; i < n; i++) {
          out.add(_geode(2, hpFor(2, 0.8)));
        }
      case SpawnPattern.skyraid:
        final rays = !f.skyrays
            ? 0
            : (level.has(Mechanic.skyraySquads) ? 3 : 2);
        for (var i = 0; i < count; i++) {
          final tier = i == 0 ? maxTier : randomTier();
          out.add(WaveSpawn(tier: tier, hp: hpFor(tier)));
          if (i < rays) out.add(_skyray(scale * jitter()));
        }
      case SpawnPattern.hazardField:
        for (var i = 0; i < math.max(1, count - 1); i++) {
          final tier = i == 0 ? maxTier : randomTier();
          out.add(WaveSpawn(tier: tier, hp: hpFor(tier)));
        }
      case SpawnPattern.treasure:
        final gold = level.has(Mechanic.treasure) ? 2 + level.chapter ~/ 4 : 0;
        for (var i = 0; i < math.max(1, count - 1); i++) {
          final tier = i == 0 ? maxTier : randomTier();
          out.add(WaveSpawn(tier: tier, hp: hpFor(tier, 0.8)));
          if (i < gold) {
            out.add(
              WaveSpawn(
                tier: 1,
                hp: _hp(scale * EnemySpec.treasureHpFactor * jitter()),
                kind: EnemyKind.treasure,
              ),
            );
          }
        }
        // Any treasure not yet interleaved still flies past at the end.
        for (var i = math.max(1, count - 1); i < gold; i++) {
          out.add(
            WaveSpawn(
              tier: 1,
              hp: _hp(scale * EnemySpec.treasureHpFactor * jitter()),
              kind: EnemyKind.treasure,
            ),
          );
        }
      case SpawnPattern.elemental:
        final squads = level.has(Mechanic.affinitySquads);
        final elite = level.has(Mechanic.eliteAffinity);
        final n = squads ? count + 1 : count;
        for (var i = 0; i < n; i++) {
          final tier = squads && i > 0
              ? math.min(maxTier, 1 + rng.nextInt(2))
              : (i == 0 ? maxTier : randomTier());
          final a = rng.nextDouble() < 0.7 ? affinity() : null;
          final hp = hpFor(tier);
          if (elite && tier >= 2 && i.isEven && f.geodes) {
            out.add(_geode(tier, hp, affinity: a));
          } else {
            out.add(WaveSpawn(tier: tier, hp: hp, affinity: a));
          }
        }
      case SpawnPattern.mixed:
        var skyrays = 0;
        for (var i = 0; i < count; i++) {
          final tier = i == 0 ? maxTier : randomTier();
          final roll = rng.nextDouble();
          final a = rng.nextDouble() < 0.35 ? affinity() : null;
          if (i > 0 && f.skyrays && skyrays < 2 && roll < 0.2) {
            skyrays++;
            out.add(_skyray(scale * jitter()));
          } else if (f.geodes && tier >= 2 && roll > 0.6) {
            out.add(_geode(tier, hpFor(tier), affinity: a));
          } else {
            out.add(WaveSpawn(tier: tier, hp: hpFor(tier), affinity: a));
          }
        }
    }
    return out;
  }

  static int _hp(double v) => math.max(1, v.round());

  static WaveSpawn _skyray(double scale) => WaveSpawn(
    tier: 1,
    hp: _hp(scale * EnemySpec.skyrayHpFactor),
    kind: EnemyKind.skyray,
  );

  static WaveSpawn _geode(
    int tier,
    int hp, {
    double speedFactor = 1,
    Element? affinity,
  }) => WaveSpawn(
    tier: tier,
    hp: hp,
    kind: EnemyKind.geode,
    armor: (hp * EnemySpec.geodeArmorFraction).roundToDouble(),
    speedFactor: speedFactor,
    affinity: affinity,
  );

  static int _hazardCount(double d) => 1 + (d > 6 ? 1 : 0) + (d > 12 ? 1 : 0);

  static List<HazardPlacement> _scatterHazards(
    List<HazardKind> kinds,
    int n,
    SeededRandom rng,
  ) {
    if (kinds.isEmpty || n <= 0) return const [];
    return [
      for (var i = 0; i < n; i++)
        HazardPlacement(
          kinds[rng.nextInt(kinds.length)],
          // Spread across the width, with a little jitter.
          (0.15 + (i + 0.5) / n * 0.7 + rng.range(-0.06, 0.06)).clamp(
            0.12,
            0.88,
          ),
          rng.range(0.34, 0.52),
        ),
    ];
  }

  /// A row of hazards close enough that one detonation sets off the next.
  static List<HazardPlacement> _cluster(LevelDef level, SeededRandom rng) {
    final kinds = level.hazardKinds;
    if (kinds.isEmpty) return const [];
    final n = level.has(Mechanic.denseClusters) ? 5 : 4;
    final y = rng.range(0.36, 0.48);
    // Spacing (as a fraction of 360 units) below the smallest blast radius.
    const gap = 0.17;
    final start = 0.5 - gap * (n - 1) / 2 + rng.range(-0.04, 0.04);
    return [
      for (var i = 0; i < n; i++)
        HazardPlacement(
          kinds[rng.nextInt(kinds.length)],
          (start + i * gap).clamp(0.1, 0.9),
          y + (i.isEven ? 0 : 0.05),
        ),
    ];
  }

  /// Total hits needed to clear a shard including all of its children.
  static int totalDurability(int tier, int hp) {
    if (tier == 0) return hp;
    final child = math.max(1, (hp * BallSpec.childHpRatio).round());
    return hp + 2 * totalDurability(tier - 1, child);
  }

  /// Endless durability scale at a (possibly fractional) difficulty.
  static double scaleAt(double d) =>
      WaveSpec.baseHp * math.pow(WaveSpec.hpGrowthPerWave, d - 1).toDouble();
}
