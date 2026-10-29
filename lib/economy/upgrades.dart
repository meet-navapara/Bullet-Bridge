import 'dart:math' as math;

import '../config/balance.dart';
import '../game/sim/entities.dart';

enum UpgradeType {
  fireRate,
  bulletPower,
  cannonLevel,
  coinBonus,
  startingShield,
  elementPower,
}

/// Static description of one upgrade track: limits, cost curve and the
/// gameplay value at each level.
class UpgradeDef {
  const UpgradeDef({
    required this.type,
    required this.title,
    required this.description,
    required this.minLevel,
    required this.maxLevel,
    required this.baseCost,
    required this.costGrowth,
  });

  final UpgradeType type;
  final String title;
  final String description;
  final int minLevel;
  final int maxLevel;
  final int baseCost;
  final double costGrowth;

  String get id => type.name;

  bool isMaxed(int level) => level >= maxLevel;

  /// e.g. "2x shot +8%" (+8% fire rate): even cannon levels add fire rate, so the
  /// label must change at every level.
  static String _cannonLabel(int level) {
    final streams = Upgrades.streams(level);
    final bonus = (level ~/ 2 * UpgradeSpec.cannonEvenLevelFireBonus * 100)
        .round();
    final rate = bonus > 0 ? ' +$bonus%' : '';
    return '${streams}x shot$rate';
  }

  /// Price of buying the level after [level]; null when maxed.
  int? costToUpgrade(int level) {
    if (isMaxed(level)) return null;
    final steps = math.max(0, level - minLevel);
    final raw = baseCost * math.pow(costGrowth, steps);
    return (raw / 10).round() * 10;
  }

  /// Human readable value for the HUD/upgrade cards.
  String valueLabel(int level) => switch (type) {
    UpgradeType.fireRate =>
      '${Upgrades.shotsPerSecond(level).toStringAsFixed(1)}/s',
    UpgradeType.bulletPower => '${Upgrades.damage(level)} dmg',
    UpgradeType.cannonLevel => _cannonLabel(level),
    UpgradeType.coinBonus => '+${(Upgrades.coinBonus(level) * 100).round()}%',
    UpgradeType.startingShield =>
      level == 0 ? 'None' : '$level shield${level > 1 ? 's' : ''}',
    UpgradeType.elementPower =>
      '+${(level * UpgradeSpec.elementPowerPerLevel * 100).round()}% effect',
  };
}

abstract final class Upgrades {
  static const List<UpgradeDef> all = [
    UpgradeDef(
      type: UpgradeType.fireRate,
      title: 'Fire Rate',
      description: 'Shoot faster.',
      minLevel: 1,
      maxLevel: UpgradeSpec.fireRateMax,
      baseCost: UpgradeSpec.fireRateBaseCost,
      costGrowth: UpgradeSpec.fireRateCostGrowth,
    ),
    UpgradeDef(
      type: UpgradeType.bulletPower,
      title: 'Bullet Power',
      description: 'Each bullet removes more durability.',
      minLevel: 1,
      maxLevel: UpgradeSpec.bulletPowerMax,
      baseCost: UpgradeSpec.bulletPowerBaseCost,
      costGrowth: UpgradeSpec.bulletPowerCostGrowth,
    ),
    UpgradeDef(
      type: UpgradeType.cannonLevel,
      title: 'Cannon Level',
      description: 'Bigger cannon. Extra bullet streams at Lv 3 and 5.',
      minLevel: 1,
      maxLevel: UpgradeSpec.cannonLevelMax,
      baseCost: UpgradeSpec.cannonLevelBaseCost,
      costGrowth: UpgradeSpec.cannonLevelCostGrowth,
    ),
    UpgradeDef(
      type: UpgradeType.coinBonus,
      title: 'Coin Bonus',
      description: 'Earn more coins from every pickup.',
      minLevel: 0,
      maxLevel: UpgradeSpec.coinBonusMax,
      baseCost: UpgradeSpec.coinBonusBaseCost,
      costGrowth: UpgradeSpec.coinBonusCostGrowth,
    ),
    UpgradeDef(
      type: UpgradeType.startingShield,
      title: 'Starting Shield',
      description: 'Start runs shielded; extra levels add shield power-ups.',
      minLevel: 0,
      maxLevel: UpgradeSpec.startingShieldMax,
      baseCost: UpgradeSpec.startingShieldBaseCost,
      costGrowth: UpgradeSpec.startingShieldCostGrowth,
    ),
    UpgradeDef(
      type: UpgradeType.elementPower,
      title: 'Element Power',
      description:
          'Bigger fire splash, longer chills, stronger arcs and '
          'hazard blasts.',
      minLevel: 0,
      maxLevel: UpgradeSpec.elementPowerMax,
      baseCost: UpgradeSpec.elementPowerBaseCost,
      costGrowth: UpgradeSpec.elementPowerCostGrowth,
    ),
  ];

  /// Elements available after clearing [highestStageCleared] stages.
  static Set<Element> elementsUnlocked(int highestStageCleared) => {
    Element.kinetic,
    if (highestStageCleared >= ElementSpec.fireUnlockStage) Element.fire,
    if (highestStageCleared >= ElementSpec.iceUnlockStage) Element.ice,
    if (highestStageCleared >= ElementSpec.electricUnlockStage)
      Element.electric,
  };

  /// Stage whose clear unlocks [e] (0 = available from the start).
  static int unlockStage(Element e) => switch (e) {
    Element.kinetic => 0,
    Element.fire => ElementSpec.fireUnlockStage,
    Element.ice => ElementSpec.iceUnlockStage,
    Element.electric => ElementSpec.electricUnlockStage,
  };

  static UpgradeDef byType(UpgradeType type) =>
      all.firstWhere((u) => u.type == type);

  static double shotsPerSecond(int fireRateLevel, [int cannonLevel = 1]) {
    final base =
        UpgradeSpec.fireRateBase +
        (fireRateLevel - 1) * UpgradeSpec.fireRatePerLevel;
    final evenBonuses = cannonLevel ~/ 2;
    return base * (1 + evenBonuses * UpgradeSpec.cannonEvenLevelFireBonus);
  }

  static int damage(int bulletPowerLevel) => math.max(1, bulletPowerLevel);

  static int streams(int cannonLevel) =>
      1 +
      UpgradeSpec.cannonExtraStreamLevels.where((l) => cannonLevel >= l).length;

  static double coinBonus(int level) => level * UpgradeSpec.coinBonusPerLevel;

  static Loadout loadoutFor(
    Map<UpgradeType, int> levels, {
    Set<Element> elements = const {Element.kinetic},
  }) {
    int lv(UpgradeType t) => levels[t] ?? byType(t).minLevel;
    final cannon = lv(UpgradeType.cannonLevel);
    return Loadout(
      shotsPerSecond: shotsPerSecond(lv(UpgradeType.fireRate), cannon),
      damage: damage(lv(UpgradeType.bulletPower)),
      streams: streams(cannon),
      coinMultiplier: 1 + coinBonus(lv(UpgradeType.coinBonus)),
      startingShieldLevel: lv(UpgradeType.startingShield),
      cannonLevel: cannon,
      elementPower:
          1 + lv(UpgradeType.elementPower) * UpgradeSpec.elementPowerPerLevel,
      elements: elements,
    );
  }

  /// Fixed loadout for the daily challenge (independent of upgrades), with
  /// every element so the challenge is the same for everyone.
  static Loadout get dailyChallengeLoadout => loadoutFor({
    UpgradeType.fireRate: DailySpec.challengeFireRateLevel,
    UpgradeType.bulletPower: DailySpec.challengeBulletPowerLevel,
    UpgradeType.cannonLevel: DailySpec.challengeCannonLevel,
    UpgradeType.coinBonus: 0,
    UpgradeType.startingShield: 0,
    UpgradeType.elementPower: 0,
  }, elements: Element.values.toSet());
}
