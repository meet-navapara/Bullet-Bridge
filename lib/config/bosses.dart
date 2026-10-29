/// The ten campaign bosses as data. One shared boss engine
/// (lib/game/sim/boss.dart + GameSimulation) runs all of them; each differs
/// in silhouette, armour layout, phases, attacks and special rules.
library;

import 'dart:ui';

import '../game/sim/entities.dart';

enum BossId {
  crystalColossus,
  stormEngine,
  moltenTitan,
  frostGuardian,
  voidDevourer,
  ironBehemoth,
  prismHydra,
  gravityCore,
  chaosArchitect,
  worldbreaker,
}

/// Attacks the boss engine knows. Each is telegraphed before it can hurt.
enum BossAttack {
  /// Three falling shard columns, one aimed at the cannon.
  rain,

  /// The boss aims, dives to the floor and rises again.
  slam,

  /// Spawns two small crystals.
  minions,

  /// Five shards fanned out from the boss (or from each living head).
  fan,

  /// Lightning columns that strike instantly after their warning.
  zap,

  /// Floor pools that burn for a few seconds.
  lava,

  /// Floor zones that slow the cannon when they trigger.
  freeze,

  /// Shards that weave sideways within a fixed amplitude.
  curve,

  /// Minions are pulled towards the boss (direction only, never speed).
  pull,
}

/// Silhouette used by the renderer.
enum BossShape {
  colossus,
  engine,
  titan,
  guardian,
  devourer,
  behemoth,
  hydra,
  gravity,
  architect,
  worldbreaker,
}

/// An armour plate (or Hydra head) relative to the boss centre.
class PlateDef {
  const PlateDef(this.dx, this.dy, {this.radius = 32, this.weakness});
  final double dx;
  final double dy;
  final double radius;

  /// Heads: this element deals double damage, all others half.
  final Element? weakness;
}

class PhaseDef {
  const PhaseDef({
    required this.attacks,
    this.moveSpeed = 55,
    this.tempo = 1.0,
    this.weakWindows = false,
  });

  final Set<BossAttack> attacks;
  final double moveSpeed;

  /// Attack interval multiplier (lower = more frequent).
  final double tempo;

  /// The core is nearly immune except in telegraphed open windows.
  final bool weakWindows;
}

class BossReward {
  const BossReward({required this.coins, this.skinId});
  final int coins;

  /// Reward-only cannon skin, if any.
  final String? skinId;
}

class BossDef {
  const BossDef({
    required this.id,
    required this.name,
    required this.tip,
    required this.shape,
    required this.colors,
    required this.coreRadius,
    required this.plates,
    required this.exposure,
    required this.coreHpFactor,
    required this.plateHpFactor,
    required this.phases,
    required this.reward,
    this.minionKind = EnemyKind.shard,
    this.minionAffinity = false,
    this.regrowHeads = false,
    this.headsFire = false,
  });

  final BossId id;
  final String name;

  /// One-line strategy hint shown on the level card.
  final String tip;
  final BossShape shape;

  /// Body colour per phase (the last entry repeats for later phases).
  final List<Color> colors;
  final double coreRadius;
  final List<PlateDef> plates;

  /// Core damage multiplier indexed by the number of broken plates.
  final List<double> exposure;

  /// Durability as multiples of the level's durability scale.
  final double coreHpFactor;
  final double plateHpFactor;
  final List<PhaseDef> phases;
  final BossReward reward;
  final EnemyKind minionKind;

  /// Minions carry a random elemental affinity.
  final bool minionAffinity;

  /// When a new phase starts, one broken plate grows back at 60%.
  final bool regrowHeads;

  /// Fan attacks come from every living plate instead of the core.
  final bool headsFire;

  Color colorFor(int phase) => colors[(phase - 1).clamp(0, colors.length - 1)];

  /// Horizontal clearance so plates never leave the arena.
  double get margin {
    var m = coreRadius;
    for (final p in plates) {
      final edge = p.dx.abs() + p.radius;
      if (edge > m) m = edge;
    }
    return m + 4;
  }
}

abstract final class Bosses {
  static const List<BossDef> all = [
    BossDef(
      id: BossId.crystalColossus,
      name: 'Crystal Colossus',
      tip: 'Break both rock plates, then crack the core. Dodge the slam!',
      shape: BossShape.colossus,
      colors: [Color(0xFF8C5CFF), Color(0xFFE04DD0), Color(0xFFFF4B5C)],
      coreRadius: 62,
      plates: [PlateDef(-80, -6), PlateDef(80, -6)],
      exposure: [0.25, 0.6, 1.0],
      coreHpFactor: 34,
      plateHpFactor: 8,
      phases: [
        PhaseDef(attacks: {BossAttack.rain}, moveSpeed: 50, tempo: 1.1),
        PhaseDef(
          attacks: {BossAttack.rain, BossAttack.minions, BossAttack.slam},
          moveSpeed: 65,
        ),
        PhaseDef(
          attacks: {
            BossAttack.rain,
            BossAttack.minions,
            BossAttack.slam,
            BossAttack.fan,
          },
          moveSpeed: 80,
          tempo: 0.9,
        ),
      ],
      reward: BossReward(coins: 250),
    ),
    BossDef(
      id: BossId.stormEngine,
      name: 'Storm Engine',
      tip: 'Step out of the glowing columns before the lightning strikes.',
      shape: BossShape.engine,
      colors: [Color(0xFF3DA0FF), Color(0xFF7B6CFF), Color(0xFFFFC23A)],
      coreRadius: 58,
      plates: [PlateDef(-78, 8, radius: 28), PlateDef(78, 8, radius: 28)],
      exposure: [0.3, 0.65, 1.0],
      coreHpFactor: 36,
      plateHpFactor: 7,
      phases: [
        PhaseDef(attacks: {BossAttack.zap}, moveSpeed: 55),
        PhaseDef(
          attacks: {BossAttack.zap, BossAttack.fan, BossAttack.minions},
          moveSpeed: 70,
        ),
        PhaseDef(
          attacks: {BossAttack.zap, BossAttack.fan, BossAttack.rain},
          moveSpeed: 85,
          tempo: 0.85,
        ),
      ],
      reward: BossReward(coins: 400, skinId: 'storm'),
    ),
    BossDef(
      id: BossId.moltenTitan,
      name: 'Molten Titan',
      tip: 'Lava pools burn for a few seconds. Fire melts its rock plates.',
      shape: BossShape.titan,
      colors: [Color(0xFFFF7A2B), Color(0xFFFF4B2B), Color(0xFFFFD23F)],
      coreRadius: 66,
      plates: [PlateDef(-84, 10), PlateDef(84, 10)],
      exposure: [0.3, 0.65, 1.0],
      coreHpFactor: 38,
      plateHpFactor: 9,
      phases: [
        PhaseDef(
          attacks: {BossAttack.lava, BossAttack.rain},
          moveSpeed: 40,
          tempo: 1.1,
        ),
        PhaseDef(
          attacks: {BossAttack.lava, BossAttack.slam, BossAttack.rain},
          moveSpeed: 50,
        ),
      ],
      reward: BossReward(coins: 600),
    ),
    BossDef(
      id: BossId.frostGuardian,
      name: 'Frost Guardian',
      tip: 'Frozen ground slows your cannon. Keep moving between zones.',
      shape: BossShape.guardian,
      colors: [Color(0xFF7FE6FF), Color(0xFF5CB8FF), Color(0xFFB8F4FF)],
      coreRadius: 58,
      plates: [
        PlateDef(-82, -4, radius: 28),
        PlateDef(0, 70, radius: 26),
        PlateDef(82, -4, radius: 28),
      ],
      exposure: [0.25, 0.5, 0.75, 1.0],
      coreHpFactor: 38,
      plateHpFactor: 6,
      phases: [
        PhaseDef(attacks: {BossAttack.freeze, BossAttack.rain}, moveSpeed: 50),
        PhaseDef(
          attacks: {BossAttack.freeze, BossAttack.fan, BossAttack.minions},
          moveSpeed: 60,
        ),
        PhaseDef(
          attacks: {BossAttack.freeze, BossAttack.fan, BossAttack.rain},
          moveSpeed: 70,
          tempo: 0.85,
        ),
      ],
      reward: BossReward(coins: 800, skinId: 'glacier'),
    ),
    BossDef(
      id: BossId.voidDevourer,
      name: 'Void Devourer',
      tip: 'It only takes real damage while its rift glows open. Wait for it!',
      shape: BossShape.devourer,
      colors: [Color(0xFF6A3FD0), Color(0xFF9B3FD0), Color(0xFFD03F9B)],
      coreRadius: 64,
      plates: [],
      exposure: [1.0],
      coreHpFactor: 30,
      plateHpFactor: 0,
      phases: [
        PhaseDef(
          attacks: {BossAttack.curve, BossAttack.rain},
          moveSpeed: 45,
          weakWindows: true,
        ),
        PhaseDef(
          attacks: {BossAttack.curve, BossAttack.minions, BossAttack.zap},
          moveSpeed: 60,
          weakWindows: true,
        ),
      ],
      reward: BossReward(coins: 1000),
    ),
    BossDef(
      id: BossId.ironBehemoth,
      name: 'Iron Behemoth',
      tip: 'Four armour sections guard the core. Strip them one by one.',
      shape: BossShape.behemoth,
      colors: [Color(0xFF8A96AE), Color(0xFFB07A5A), Color(0xFFE05A3A)],
      coreRadius: 60,
      plates: [
        PlateDef(-80, -30, radius: 28),
        PlateDef(80, -30, radius: 28),
        PlateDef(-62, 44, radius: 26),
        PlateDef(62, 44, radius: 26),
      ],
      exposure: [0.12, 0.3, 0.5, 0.75, 1.0],
      coreHpFactor: 32,
      plateHpFactor: 6,
      minionKind: EnemyKind.geode,
      phases: [
        PhaseDef(attacks: {BossAttack.rain, BossAttack.slam}, moveSpeed: 40),
        PhaseDef(
          attacks: {BossAttack.slam, BossAttack.fan, BossAttack.minions},
          moveSpeed: 50,
        ),
        PhaseDef(
          attacks: {
            BossAttack.slam,
            BossAttack.fan,
            BossAttack.minions,
            BossAttack.rain,
          },
          moveSpeed: 60,
          tempo: 0.9,
        ),
      ],
      reward: BossReward(coins: 1300, skinId: 'forge'),
    ),
    BossDef(
      id: BossId.prismHydra,
      name: 'Prism Hydra',
      tip: 'Each head is weak to one element: match its colour.',
      shape: BossShape.hydra,
      colors: [Color(0xFF3DDC97), Color(0xFF2BB5C9), Color(0xFFE95CFF)],
      coreRadius: 54,
      plates: [
        // Heads beside and below the body, so bullets from below can
        // reach each one without hitting the core first.
        PlateDef(-88, -54, radius: 30, weakness: Element.fire),
        PlateDef(0, 84, radius: 30, weakness: Element.ice),
        PlateDef(88, -54, radius: 30, weakness: Element.electric),
      ],
      exposure: [0.1, 0.35, 0.7, 1.0],
      coreHpFactor: 30,
      plateHpFactor: 8,
      regrowHeads: true,
      headsFire: true,
      minionAffinity: true,
      phases: [
        PhaseDef(attacks: {BossAttack.fan, BossAttack.rain}, moveSpeed: 45),
        PhaseDef(
          attacks: {BossAttack.fan, BossAttack.minions, BossAttack.zap},
          moveSpeed: 55,
          tempo: 0.95,
        ),
      ],
      reward: BossReward(coins: 1600),
    ),
    BossDef(
      id: BossId.gravityCore,
      name: 'Gravity Core',
      tip: 'Its shards weave and it drags crystals towards itself.',
      shape: BossShape.gravity,
      colors: [Color(0xFF4D6BFF), Color(0xFF8A4DFF), Color(0xFFFF4DA6)],
      coreRadius: 60,
      plates: [PlateDef(-84, 0, radius: 28), PlateDef(84, 0, radius: 28)],
      exposure: [0.4, 0.7, 1.0],
      coreHpFactor: 36,
      plateHpFactor: 7,
      phases: [
        PhaseDef(attacks: {BossAttack.curve, BossAttack.rain}, moveSpeed: 50),
        PhaseDef(
          attacks: {BossAttack.curve, BossAttack.minions, BossAttack.pull},
          moveSpeed: 60,
        ),
        PhaseDef(
          attacks: {
            BossAttack.curve,
            BossAttack.minions,
            BossAttack.pull,
            BossAttack.zap,
          },
          moveSpeed: 70,
          tempo: 0.9,
        ),
      ],
      reward: BossReward(coins: 2000, skinId: 'gravity'),
    ),
    BossDef(
      id: BossId.chaosArchitect,
      name: 'Chaos Architect',
      tip: 'Every phase rebuilds its attacks from earlier bosses.',
      shape: BossShape.architect,
      colors: [Color(0xFFFF5CA8), Color(0xFFFF9F2B), Color(0xFF2BE0FF)],
      coreRadius: 58,
      plates: [PlateDef(-82, 12, radius: 30), PlateDef(82, 12, radius: 30)],
      exposure: [0.3, 0.65, 1.0],
      coreHpFactor: 32,
      plateHpFactor: 8,
      phases: [
        PhaseDef(attacks: {BossAttack.rain, BossAttack.zap}, moveSpeed: 55),
        PhaseDef(
          attacks: {BossAttack.lava, BossAttack.minions, BossAttack.curve},
          moveSpeed: 60,
        ),
        PhaseDef(
          attacks: {BossAttack.freeze, BossAttack.fan, BossAttack.slam},
          moveSpeed: 70,
          tempo: 1.0,
        ),
      ],
      reward: BossReward(coins: 2500),
    ),
    BossDef(
      id: BossId.worldbreaker,
      name: 'Worldbreaker',
      tip: 'Four phases. Break the crust, then strike the rift when it opens.',
      shape: BossShape.worldbreaker,
      colors: [
        Color(0xFFFF6A3D),
        Color(0xFFFF3D6A),
        Color(0xFF9B3DFF),
        Color(0xFFFFE04D),
      ],
      coreRadius: 70,
      plates: [
        PlateDef(-92, -24, radius: 28),
        PlateDef(92, -24, radius: 28),
        PlateDef(-60, 58, radius: 26),
        PlateDef(60, 58, radius: 26),
      ],
      exposure: [0.15, 0.35, 0.55, 0.8, 1.0],
      coreHpFactor: 32,
      plateHpFactor: 7,
      phases: [
        PhaseDef(attacks: {BossAttack.rain, BossAttack.slam}, moveSpeed: 45),
        PhaseDef(
          attacks: {BossAttack.zap, BossAttack.lava, BossAttack.minions},
          moveSpeed: 55,
          tempo: 1.1,
        ),
        PhaseDef(
          attacks: {BossAttack.curve, BossAttack.fan, BossAttack.rain},
          moveSpeed: 60,
          weakWindows: true,
        ),
        PhaseDef(
          attacks: {
            BossAttack.freeze,
            BossAttack.zap,
            BossAttack.fan,
            BossAttack.slam,
          },
          moveSpeed: 70,
          tempo: 1.0,
          weakWindows: true,
        ),
      ],
      reward: BossReward(coins: 4000, skinId: 'worldbreaker'),
    ),
  ];

  static BossDef of(BossId id) => all[id.index];

  /// Boss of a chapter (1-based).
  static BossDef forChapter(int chapter) => all[(chapter - 1) % all.length];
}
