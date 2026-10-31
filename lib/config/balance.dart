/// Central gameplay and economy tuning.
///
/// Every number that affects difficulty, rewards or prices lives here so the
/// game can be rebalanced without touching rules or UI code. See
/// docs/GAME_BALANCING.md for the reasoning behind these values.
library;

import 'dart:math' as math;

/// Physics and arena constants. All distances are in "world units"; the
/// arena is always [worldWidth] units wide and the renderer scales it to the
/// screen, so gameplay is identical on every phone width.
abstract final class Physics {
  static const double worldWidth = 360;

  /// Simulation runs at a fixed rate regardless of display refresh rate.
  static const double fixedStep = 1 / 120;

  /// Frames longer than this (app hitches, debugger pauses) are clamped so
  /// the simulation never jumps objects through each other.
  static const double maxFrameDelta = 0.1;

  static const double gravity = 900;

  /// Height of the foreground ground band at the bottom of the arena. The
  /// element/power-up bar is drawn on top of it.
  static const double floorHeight = 72;

  /// Arena heights are clamped so extreme aspect ratios stay playable.
  static const double minArenaHeight = 560;
  static const double maxArenaHeight = 900;
}

abstract final class CannonSpec {
  /// Half width of the solid body used for collision.
  static const double bodyHalfWidth = 24;
  static const double bodyHeight = 46;

  /// Barrel tip collision circle.
  static const double barrelRadius = 12;
  static const double barrelTipHeight = 68;

  /// Visual half width, used to clamp the cannon inside the walls.
  static const double visualHalfWidth = 42;

  /// Collision boxes are shrunk slightly so near-misses feel fair.
  static const double hitboxForgiveness = 3;

  /// Horizontal drag sensitivity (world units per world unit of finger drag).
  static const double dragSensitivity = 1.0;

  static const double coinPickupHalfWidth = 36;

  /// The cannon art is drawn at this scale; the hitbox above matches it.
  static const double artScale = 1.25;
}

abstract final class BulletSpec {
  static const double speed = 980;
  static const double radius = 4;
  static const double streamSpacing = 13;
}

/// Ball size tiers: 0 is the smallest (never splits), [maxTier] the largest.
abstract final class BallSpec {
  static const int maxTier = 4;

  /// The smallest crystal is 18% of the arena width, the largest 43%. Each
  /// split shrinks the radius by ~20%, so children stay easy to see and hit.
  static const List<double> radius = [32, 42, 53, 65, 78];

  /// Bounce apex as a fraction of arena height (centre of ball above floor).
  static const List<double> apexFraction = [0.30, 0.37, 0.44, 0.51, 0.57];
  static const List<double> baseSpeedX = [92, 86, 80, 74, 68];

  /// Children receive this fraction of the parent's starting durability.
  static const double childHpRatio = 0.5;

  /// Upward pop given to freshly split children (world units of rise).
  static const double splitPopHeight = 70;

  /// Duration of the hit flash and floor squash cosmetic timers.
  static const double hitFlashTime = 0.07;
  static const double squashTime = 0.16;
}

/// The single source of creature speed. Every moving enemy (bouncing
/// crystals, skyrays, treasure, enemy shots, bosses) runs on a time scale
/// called pace, and horizontal crystal speed is additionally multiplied by
/// drift. Both come from the level (campaign) or the difficulty (endless)
/// and are clamped here, so no combination of systems can exceed them.
/// See docs/LEVEL_BALANCING.md.
abstract final class SpeedSpec {
  /// Pace of level 1: about 55% of the old typical pace (~0.9).
  static const double startPace = 0.5;

  /// Absolute ceiling for pace anywhere in the game.
  static const double maxPace = 0.78;
  static const double minPace = 0.42;

  /// Horizontal multiplier range for crystals.
  static const double maxDrift = 1.2;

  /// Hard cap on a crystal's horizontal speed in world units per second
  /// before pace (spawns, splits, knock-backs and bomb pushes).
  static const double maxDriftSpeed = 115;

  /// Bounce height multipliers for the bounce profiles.
  static const double lowBounce = 0.82;
  static const double highBounce = 1.1;

  /// Pace reduction for low-bounce levels (their bounces are quicker).
  static const double lowBouncePaceCut = 0.05;
}

abstract final class WaveSpec {
  static const double baseHp = 10;
  static const double hpGrowthPerWave = 1.2;
  static const List<double> tierHpFactor = [0.5, 0.75, 1.0, 1.4, 1.9];

  /// Random +/- spread of ball durability.
  static const double hpJitter = 0.18;

  static const int maxBallsPerWave = 6;
  static const int maxAliveBalls = 12;

  /// Warning shown before a ball drops in, so spawns are never a surprise.
  static const double spawnTelegraph = 0.9;
  static const double firstSpawnDelay = 1.2;
  static const double intermission = 2.2;

  static int ballCount(int wave) =>
      math.min(maxBallsPerWave, 1 + (wave + 1) ~/ 3);

  static int maxTierFor(int wave) => math.min(BallSpec.maxTier, 1 + wave ~/ 3);

  /// Endless/daily creature time scale at a difficulty: starts calm and
  /// reaches the [SpeedSpec.maxPace] cap around endless wave 16.
  static double paceAt(double difficulty) =>
      SpeedSpec.startPace +
      (SpeedSpec.maxPace - SpeedSpec.startPace) *
          ((difficulty - 1) / 15).clamp(0.0, 1.0);

  static double spawnGap(int wave) => math.max(1.4, 3.2 - wave * 0.12);

  /// Endless/daily horizontal drift multiplier.
  static double speedMultiplier(int wave) =>
      math.min(SpeedSpec.maxDrift, 1 + (wave - 1) * 0.015);

  static double hpScale(int wave) =>
      baseHp * math.pow(hpGrowthPerWave, wave - 1).toDouble();
}

abstract final class RewardSpec {
  /// Score per point of damage dealt plus a destruction bonus per tier.
  static const int scorePerDamage = 1;
  static const int destroyBonusPerTier = 10;
  static const int waveClearBonusPerWave = 50;

  /// Coins carried by a coin pickup dropped from a destroyed ball.
  static const List<int> coinValue = [1, 1, 2, 3, 4];
  static const double coinDropChance = 0.6;
  static const double coinLifetime = 7;
  static const int maxActiveCoins = 40;

  static const double powerUpDropChance = 0.045;
  static const double powerUpLifetime = 8;
}

abstract final class PowerUpSpec {
  static const double globalCooldown = 1.0;
  static const double slowMotionDuration = 6;
  static const double slowMotionScale = 0.45;
  static const double powerShotDuration = 7;
  static const int powerShotMultiplier = 2;
  static const double shieldDuration = 12;
  static const double bombRadius = 175;

  /// Bomb centre height above the floor.
  static const double bombHeight = 150;
  static const double bombInvulnerability = 0.8;
  static const double shieldBreakInvulnerability = 1.5;
  static const double reviveInvulnerability = 3;

  /// Power-ups every run starts with (shields come from the upgrade).
  static const int startBombs = 1;
  static const int startSlow = 1;
  static const int startPowerShot = 1;
  static const int maxInventory = 9;
}

/// Upgrade definitions: level 1 is the free starting level for stat
/// upgrades; Coin Bonus and Starting Shield start at level 0.
abstract final class UpgradeSpec {
  static const int fireRateMax = 15;
  static const double fireRateBase = 6; // shots per second at level 1
  static const double fireRatePerLevel = 0.6;

  static const int bulletPowerMax = 20;

  static const int cannonLevelMax = 5;

  /// Cannon levels that add an extra parallel bullet stream.
  static const List<int> cannonExtraStreamLevels = [3, 5];

  /// Fire-rate bonus granted by even cannon levels (2 and 4).
  static const double cannonEvenLevelFireBonus = 0.08;

  static const int coinBonusMax = 10;
  static const double coinBonusPerLevel = 0.10;

  static const int startingShieldMax = 3;

  static const int fireRateBaseCost = 60;
  static const int bulletPowerBaseCost = 80;
  static const int cannonLevelBaseCost = 600;
  static const int coinBonusBaseCost = 150;
  static const int startingShieldBaseCost = 300;

  static const double fireRateCostGrowth = 1.3;
  static const double bulletPowerCostGrowth = 1.38;
  static const double cannonLevelCostGrowth = 2.2;
  static const double coinBonusCostGrowth = 1.45;
  static const double startingShieldCostGrowth = 2.5;

  static const int elementPowerMax = 10;
  static const double elementPowerPerLevel = 0.1;
  static const int elementPowerBaseCost = 200;
  static const double elementPowerCostGrowth = 1.5;
}

abstract final class DailySpec {
  /// Daily reward amounts for a 7-day streak (day 4 is a coin chest,
  /// day 5 also grants power-ups for the next run).
  static const List<int> rewardCoins = [100, 200, 300, 500, 400, 600, 1000];
  static const int day5BonusPowerUps = 1;

  static const int challengeReward = 250;

  /// Fixed loadout used by the daily challenge so every player faces the
  /// same difficulty regardless of upgrades.
  static const int challengeFireRateLevel = 5;
  static const int challengeBulletPowerLevel = 4;
  static const int challengeCannonLevel = 2;
}

abstract final class AdSpec {
  static const int rewardedCoins = 100;
  static const int rewardedCoinsPerDay = 3;
  static const int gamesBetweenInterstitials = 3;
  static const Duration minTimeBetweenInterstitials = Duration(minutes: 3);
  static const Duration minRunForInterstitial = Duration(seconds: 30);
}

/// Cannon hull. A run ends when hull points reach zero.
abstract final class PlayerSpec {
  static const int baseHull = 3;
  static const double hurtInvulnerability = 1.4;
  static const int reviveHull = 2;
}

/// Elemental projectiles. Multipliers apply to the loadout's base damage;
/// effect strength additionally scales with the Element Power upgrade.
abstract final class ElementSpec {
  static const double kineticDamage = 1.0;

  static const double fireDamage = 0.8;
  static const double fireSplashRadius = 56;
  static const double fireSplashFraction = 0.5;
  static const double fireVsArmor = 2.0;

  static const double iceDamage = 0.85;
  static const double chillDuration = 1.6;
  static const double chillSlow = 0.45; // speed multiplier while chilled
  static const int freezeStacks = 8;
  static const double freezeDuration = 1.5;

  /// Frozen targets take extra damage from blasts and fire ("shatter").
  static const double shatterBonus = 1.5;

  static const double electricDamage = 0.75;
  static const double arcRadius = 125;
  static const int arcTargets = 2;
  static const double arcFraction = 0.6;

  /// Stage that must be cleared to unlock each element (0 = always).
  static const int fireUnlockStage = 2;
  static const int iceUnlockStage = 4;
  static const int electricUnlockStage = 6;
}

/// Enemy archetypes other than plain shards.
abstract final class EnemySpec {
  /// Geodes carry a rock shell worth this fraction of their durability.
  static const double geodeArmorFraction = 0.7;
  static const double geodeSpeedFactor = 0.75;
  static const int geodeArmorBreakCoins = 2;

  /// Skyrays glide across the upper sky and drop crystal shards.
  static const double skyrayRadius = 38;
  static const double skyraySpeed = 70;
  static const double skyrayBobAmplitude = 14;
  static const double skyrayHpFactor = 1.2;
  static const double skyrayDropInterval = 3.4;
  static const double skyrayDropTelegraph = 0.6;
  static const int skyrayCoins = 3;

  /// Treasure crystals cross the sky once and leave; popping one pays out.
  static const double treasureRadius = 30;
  static const double treasureSpeed = 62;
  static const double treasureHpFactor = 0.9;
  static const int treasureCoins = 5;

  /// Falling enemy shards (from skyrays and the boss).
  static const double shotRadius = 11;
  static const double shotSpeed = 210;
  static const double shotGravity = 260;
}

/// Volatile environmental crystals that detonate when broken.
abstract final class HazardSpec {
  static const double radius = 26;
  static const double hpFactor = 0.45; // of the wave's durability scale
  static const double blazeRadius = 130;
  static const double blazeDamageFactor = 1.4;
  static const double frostRadius = 145;
  static const double frostDamageFactor = 0.3;
  static const double frostFreeze = 2.5;
  static const double stormRange = 170;
  static const int stormTargets = 5;
  static const double stormDamageFactor = 1.0;

  /// Delay between links of a chain, so each detonation is visible.
  static const double chainDelay = 0.12;
}

/// Combo for kills caused by blasts, arcs and splashes.
abstract final class ChainSpec {
  static const double window = 1.2;
  static const int minForBonus = 3;
  static const int scorePerSquare = 25;
}

/// Campaign layout: 100 chapters of 10 levels; every tenth level is a boss.
/// The level data itself lives in lib/config/campaign.dart.
abstract final class StageSpec {
  static const int chapters = 100;
  static const int levelsPerChapter = 10;
  static const int levelCount = chapters * levelsPerChapter;

  /// Chapters 1-10 are written by hand; later ones are generated from them.
  static const int authoredChapters = 10;
  static const int authoredLevels = authoredChapters * levelsPerChapter;
  static const int clearBonusBase = 15;
  static const int clearBonusPerStage = 5;

  /// Clear bonus stops growing with the authored levels: by then upgrades are
  /// near their caps, so bigger payouts would have nothing to buy.
  static int clearBonus(int level) =>
      clearBonusBase + clearBonusPerStage * math.min(level, authoredLevels);

  /// Replaying an already cleared level pays this share of its clear bonus
  /// (the first clear pays double), so replays never repeat the full reward.
  static const double replayBonusFraction = 0.25;

  static bool isBossLevel(int level) => level % levelsPerChapter == 0;
  static int chapterOf(int level) => (level - 1) ~/ levelsPerChapter + 1;
}

/// Curves the campaign levels are built from. Category multipliers and
/// per-level patterns are applied on top in lib/config/campaign.dart.
abstract final class CampaignSpec {
  /// Durability scale: 10 at level 1, ~41 at level 10, ~580 at level 100.
  /// It grows roughly with the damage an upgraded cannon deals at that
  /// point, so it is polynomial, not exponential like Endless.
  static const double hpBase = 10;
  static const double hpSlope = 0.25;
  static const double hpPower = 1.25;

  /// Upgrades are capped, so past the authored levels durability only creeps
  /// up: this much in total between level 100 and the last level. Difficulty
  /// there comes from wave combinations and boss attacks instead.
  static const double lateHpGrowth = 0.15;

  static double durabilityAt(int level) {
    double curve(int l) =>
        hpBase * math.pow(1 + hpSlope * (l - 1), hpPower).toDouble();
    const end = StageSpec.authoredLevels;
    if (level <= end) return curve(level);
    final late = (level - end) / (StageSpec.levelCount - end);
    return curve(end) * (1 + lateHpGrowth * late);
  }

  /// Later waves of a level are this much tougher than the previous one.
  static const double waveHpRamp = 0.1;

  /// Pace rises by this per level before category adjustments and caps.
  static const double paceSlope = 0.003;

  /// Levels past the authored ones stay on level 100's base pace, so category
  /// offsets (recovery levels above all) still make a difference.
  static double paceAt(int level) =>
      SpeedSpec.startPace +
      paceSlope * (math.min(level, StageSpec.authoredLevels) - 1);

  static double driftAt(int level) =>
      1 + (SpeedSpec.maxDrift - 1) * ((level - 1) / 99).clamp(0.0, 1.0);

  /// Coin pickups are worth more in later chapters (×1.0 … ×2.35, the most
  /// from chapter 10 on).
  static double coinScale(int level) =>
      1 +
      0.15 *
          (math.min(StageSpec.chapterOf(level), StageSpec.authoredChapters) -
              1);
}

/// Shared boss tuning. Per-boss data (shape, plates, phases, attacks) is in
/// lib/config/bosses.dart.
abstract final class BossSpec {
  static const double plateRadius = 32;
  static const double hoverFraction = 0.26; // of arena height from top

  /// The boss descends into the arena and cannot be hurt meanwhile.
  static const double entranceTime = 2.0;
  static const double phaseTransition = 1.2;

  /// Minimum time between the starts of two attacks, so attacks never
  /// stack into unavoidable patterns.
  static const double attackGap = 1.2;

  static const double rainInterval = 4.0;
  static const double rainTelegraph = 0.9;
  static const double slamInterval = 9.0;
  static const double slamTelegraph = 1.1;
  static const double slamSpeed = 620;
  static const double spawnInterval = 8.0;
  static const double fanInterval = 3.2;

  /// Lightning columns: warning, then an instant strike.
  static const double zapInterval = 5.0;
  static const double zapTelegraph = 1.15;
  static const double zapHalfWidth = 24;

  /// Lava pools: warning, then the floor burns for a while.
  static const double lavaInterval = 6.5;
  static const double lavaTelegraph = 1.2;
  static const double lavaDuration = 3.2;
  static const double lavaHalfWidth = 44;

  /// Freezing zones slow the cannon instead of hurting it.
  static const double freezeInterval = 7.0;
  static const double freezeTelegraph = 1.2;
  static const double freezeHalfWidth = 62;
  static const double freezeSlowTime = 2.2;
  static const double freezeMoveScale = 0.4;

  /// Weaving shots: bounded sideways swing.
  static const double curveInterval = 4.5;
  static const double curveAmplitude = 60;

  /// Gravity pull: minions turn towards the boss.
  static const double pullInterval = 8.5;

  /// Thrown balls. A boss has a fixed supply and keeps throwing it; every ball
  /// destroyed (split pieces too) takes its share of the boss's health, and
  /// the boss goes down with the last one.
  static const double firstThrowDelay = 0.8;
  static const double throwWindup = 0.35;
  static const double throwRecoilTime = 0.3;

  /// Downward speed a ball leaves the boss with.
  static const double throwVelocity = 60;
  static const double throwAtCannonChance = 0.7;

  /// Balls in the arena at once; further throws wait for room.
  static const int maxThrownAlive = 6;

  /// Each phase throws this much faster than the one before.
  static const double throwPhaseScale = 0.85;

  static const int ballsBase = 10;
  static const int ballsPerChapter = 2;
  static const int ballsMax = 32;

  /// Harder chapters, first the ten written by hand and then slowly.
  static int ballCountFor(int chapter) {
    final authored = chapter < 10 ? chapter : 10;
    final later = chapter > 10 ? (chapter - 10) ~/ 15 : 0;
    return math.min(ballsMax, ballsBase + ballsPerChapter * authored + later);
  }

  /// Largest ball a boss of this chapter throws.
  static int maxThrownTierFor(int chapter) => chapter <= 1 ? 1 : 2;

  /// Seconds between throws in a boss's first phase.
  static double throwIntervalFor(int chapter) =>
      math.max(1.6, 2.6 - 0.1 * math.min(chapter, 10));

  /// A boss's supply as ball tiers in throwing order: small to start with,
  /// the biggest towards the end.
  static List<int> ballPlan(
    int chapter,
    double Function() random, {
    double supplyScale = 1,
  }) {
    final count = (ballCountFor(chapter) * supplyScale).round();
    final top = maxThrownTierFor(chapter);
    return [
      for (var i = 0; i < count; i++)
        (((i / count) + (random() - 0.5) * 0.4) * (top + 1))
            .floor()
            .clamp(0, top)
            .toInt(),
    ];
  }

  static const int defeatCoins = 60;
}
