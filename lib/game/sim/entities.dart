import 'dart:math' as math;

import '../../config/balance.dart';

/// The four power-ups the player can carry and activate.
enum PowerUpType { bomb, slowMotion, shield, powerShot }

/// Projectile element. Kinetic is the default weapon; the others unlock as
/// the campaign progresses.
enum Element { kinetic, fire, ice, electric }

/// What dealt damage. Anything other than a direct bullet counts towards a
/// chain combo.
enum DamageSource { bullet, splash, arc, blast, frost, bomb }

/// Stats the cannon brings into a run, derived from upgrades (or the fixed
/// daily-challenge loadout). Kept separate so the simulation never reads
/// save data directly.
class Loadout {
  const Loadout({
    required this.shotsPerSecond,
    required this.damage,
    required this.streams,
    required this.coinMultiplier,
    required this.startingShieldLevel,
    required this.cannonLevel,
    this.elementPower = 1,
    this.hull = PlayerSpec.baseHull,
    this.elements = const {Element.kinetic},
  });

  final double shotsPerSecond;
  final int damage;
  final int streams;
  final double coinMultiplier;
  final int startingShieldLevel;
  final int cannonLevel;

  /// Multiplier on elemental side effects (splash, arcs, chill).
  final double elementPower;
  final int hull;
  final Set<Element> elements;

  /// Loadout used by tests and as the baseline before any upgrades.
  static const base = Loadout(
    shotsPerSecond: UpgradeSpec.fireRateBase,
    damage: 1,
    streams: 1,
    coinMultiplier: 1,
    startingShieldLevel: 0,
    cannonLevel: 1,
  );

  Loadout copyWith({Set<Element>? elements, int? hull}) => Loadout(
    shotsPerSecond: shotsPerSecond,
    damage: damage,
    streams: streams,
    coinMultiplier: coinMultiplier,
    startingShieldLevel: startingShieldLevel,
    cannonLevel: cannonLevel,
    elementPower: elementPower,
    hull: hull ?? this.hull,
    elements: elements ?? this.elements,
  );
}

enum EnemyKind { shard, geode, skyray, treasure }

/// Elemental affinity: the crystal resists its own element and is weak to
/// one counter element.
abstract final class Affinity {
  /// The element that deals bonus damage to a crystal of [affinity].
  static Element weakness(Element affinity) => switch (affinity) {
    Element.fire => Element.ice,
    Element.ice => Element.fire,
    Element.electric => Element.kinetic,
    Element.kinetic => Element.kinetic,
  };

  static const double resist = 0.5;
  static const double weak = 1.6;

  static double multiplier(Element? affinity, Element attack) {
    if (affinity == null || affinity == Element.kinetic) return 1;
    if (attack == affinity) return resist;
    if (attack == weakness(affinity)) return weak;
    return 1;
  }
}

/// A crystal creature. Shards and geodes bounce; skyrays glide.
/// (Named Ball for continuity with the original bouncing-ball rules.)
class Ball {
  Ball({
    required this.id,
    required this.tier,
    required this.maxHp,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.entering = false,
    this.kind = EnemyKind.shard,
    this.armor = 0,
    this.affinity,
  }) : hp = maxHp.toDouble(),
       maxArmor = armor;

  final int id;
  final int tier;
  final int maxHp;
  final EnemyKind kind;

  /// Elemental affinity, if any (see [Affinity]).
  final Element? affinity;
  double hp;
  double armor;
  final double maxArmor;
  double x;
  double y;
  double vx;
  double vy;

  /// True while the ball is still dropping in from above the arena; the
  /// ceiling is ignored until it is fully inside.
  bool entering;

  /// Set exactly once when durability hits zero; guards splitting/rewards.
  bool dead = false;

  // Elemental status.
  double chill = 0;
  int frostStacks = 0;
  double frozen = 0;

  // Skyray flight.
  double flyY = 0;
  double flyPhase = 0;
  double dropTimer = 0;

  /// Cosmetic timers (seconds remaining).
  double hitFlash = 0;
  double squash = 0;

  bool get armored => armor > 0;

  /// Skyrays and treasure crystals glide instead of bouncing.
  bool get isFlyer => kind == EnemyKind.skyray || kind == EnemyKind.treasure;
  bool get isTreasure => kind == EnemyKind.treasure;
  bool get isFrozen => frozen > 0;

  /// Number shown on the creature (shell while armoured, then core).
  int get displayHp => (armored ? armor : hp).ceil();

  double get radius => switch (kind) {
    EnemyKind.skyray => EnemySpec.skyrayRadius,
    EnemyKind.treasure => EnemySpec.treasureRadius,
    _ => BallSpec.radius[tier],
  };

  /// Time scale applied to this creature's movement.
  double get moveScale {
    if (isFrozen) return 0;
    return chill > 0 ? ElementSpec.chillSlow : 1;
  }
}

class Bullet {
  Bullet(
    this.x,
    this.y,
    this.damage, {
    this.powered = false,
    this.element = Element.kinetic,
  });

  double x;
  double y;
  final double damage;
  final bool powered;
  final Element element;
  bool dead = false;
}

enum PickupKind { coin, powerUp }

class Pickup {
  Pickup({
    required this.kind,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    this.value = 0,
    this.powerUp,
  });

  final PickupKind kind;
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final int value;
  final PowerUpType? powerUp;
  bool grounded = false;
  bool collected = false;
}

/// A warning marker shown before an enemy enters the arena.
class PendingSpawn {
  PendingSpawn({
    required this.x,
    required this.tier,
    required this.hp,
    required this.direction,
    required this.timer,
    this.kind = EnemyKind.shard,
    this.armor = 0,
    this.affinity,
    this.speedFactor = 1,
  });

  final double x;
  final int tier;
  final int hp;
  final int direction;
  final EnemyKind kind;
  final double armor;
  final Element? affinity;
  final double speedFactor;
  double timer;
}

enum HazardKind { blaze, frost, storm }

/// Volatile environmental crystal. Breaking it triggers an elemental
/// detonation that can break other hazards: a chain reaction.
class Hazard {
  Hazard({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.maxHp,
  }) : hp = maxHp;

  final int id;
  final HazardKind kind;
  final double x;
  final double y;
  final double maxHp;
  double hp;
  bool dead = false;
  double hitFlash = 0;

  /// Visual bob phase.
  double get bobSeed => id * 1.7;
  double get radius => HazardSpec.radius;
}

/// A crystal shard falling towards the cannon. One bullet destroys it.
class EnemyShot {
  EnemyShot(this.x, this.y, this.vx, this.vy, {this.weave = 0});
  double x;
  double y;
  double vx;
  double vy;

  /// Sideways swing amplitude in world units (0 = straight).
  final double weave;
  double weavePhase = 0;
  bool dead = false;
  double get radius => EnemySpec.shotRadius;
}

enum ZoneKind { lava, freeze }

/// A boss floor attack: a warning outline, then an active area.
class FloorZone {
  FloorZone({
    required this.kind,
    required this.x,
    required this.halfWidth,
    required this.warning,
    required this.active,
  }) : warningTotal = warning;

  final ZoneKind kind;
  final double x;
  final double halfWidth;
  final double warningTotal;

  /// Seconds of warning left; the zone is armed when this reaches 0.
  double warning;

  /// Seconds the zone stays active after arming.
  double active;

  /// A zone can affect the cannon at most once.
  bool spent = false;

  bool get armed => warning <= 0;
  bool get done => armed && active <= 0;
  double get warnProgress => 1 - (warning / warningTotal).clamp(0.0, 1.0);
}

/// A queued detonation, processed after a short delay so chains read as a
/// sequence instead of a single flash.
class Blast {
  Blast({
    required this.kind,
    required this.x,
    required this.y,
    required this.damage,
    required this.delay,
    required this.depth,
  });

  final HazardKind kind;
  final double x;
  final double y;
  final double damage;
  double delay;
  final int depth;
}

enum TelegraphKind { rain, slam, zap }

/// A vertical warning column where something will fall, slam or strike.
class Telegraph {
  Telegraph(
    this.x,
    this.timer,
    this.total, {
    bool slam = false,
    TelegraphKind? kind,
    this.width = 12,
  }) : kind = kind ?? (slam ? TelegraphKind.slam : TelegraphKind.rain);
  final double x;
  double timer;
  final double total;
  final TelegraphKind kind;

  /// Half width of the warned column.
  final double width;
  bool get slam => kind == TelegraphKind.slam;
  double get progress => 1 - (timer / total).clamp(0.0, 1.0);
}

enum RunPhase { playing, intermission, stageCleared, gameOver }

/// Events emitted by the simulation each step. The Flame layer turns these
/// into particles, sounds and haptics; the rules never depend on them.
sealed class GameEvent {
  const GameEvent();
}

class ShotFired extends GameEvent {
  const ShotFired(this.element);
  final Element element;
}

class BallHit extends GameEvent {
  const BallHit(this.x, this.y, this.tier, {this.armored = false});
  final double x;
  final double y;
  final int tier;
  final bool armored;
}

class BallDestroyed extends GameEvent {
  const BallDestroyed(
    this.x,
    this.y,
    this.tier, {
    required this.split,
    this.kind = EnemyKind.shard,
  });
  final double x;
  final double y;
  final int tier;
  final bool split;
  final EnemyKind kind;
}

class ArmorBroken extends GameEvent {
  const ArmorBroken(this.x, this.y, this.radius);
  final double x;
  final double y;
  final double radius;
}

class BallBounced extends GameEvent {
  const BallBounced(this.x, this.tier);
  final double x;
  final int tier;
}

class SplashHit extends GameEvent {
  const SplashHit(this.x, this.y, this.radius);
  final double x;
  final double y;
  final double radius;
}

class ArcZap extends GameEvent {
  const ArcZap(this.points);

  /// Polyline from the source through each target hit.
  final List<math.Point<double>> points;
}

class EnemyFrozen extends GameEvent {
  const EnemyFrozen(this.x, this.y);
  final double x;
  final double y;
}

class HazardHit extends GameEvent {
  const HazardHit(this.x, this.y, this.kind);
  final double x;
  final double y;
  final HazardKind kind;
}

class HazardDetonated extends GameEvent {
  const HazardDetonated(this.kind, this.x, this.y, this.radius, this.depth);
  final HazardKind kind;
  final double x;
  final double y;
  final double radius;
  final int depth;
}

class ChainProgress extends GameEvent {
  const ChainProgress(this.count);
  final int count;
}

class ChainEnded extends GameEvent {
  const ChainEnded(this.count, this.bonusCoins);
  final int count;
  final int bonusCoins;
}

class ShotDropped extends GameEvent {
  const ShotDropped(this.x, this.y);
  final double x;
  final double y;
}

class CoinCollected extends GameEvent {
  const CoinCollected(this.x, this.y, this.value);
  final double x;
  final double y;
  final int value;
}

class PowerUpCollected extends GameEvent {
  const PowerUpCollected(this.type);
  final PowerUpType type;
}

class PowerUpActivated extends GameEvent {
  const PowerUpActivated(this.type, this.x, this.y);
  final PowerUpType type;
  final double x;
  final double y;
}

class ShieldBroken extends GameEvent {
  const ShieldBroken(this.x, this.y);
  final double x;
  final double y;
}

class PlayerHurt extends GameEvent {
  const PlayerHurt(this.x, this.y, this.hullLeft);
  final double x;
  final double y;
  final int hullLeft;
}

class PlayerDestroyed extends GameEvent {
  const PlayerDestroyed(this.x, this.y);
  final double x;
  final double y;
}

class WaveStarted extends GameEvent {
  const WaveStarted(this.wave);
  final int wave;
}

class WaveCleared extends GameEvent {
  const WaveCleared(this.wave);
  final int wave;
}

class BossHit extends GameEvent {
  const BossHit(this.x, this.y, {required this.plate});
  final double x;
  final double y;
  final bool plate;
}

class BossPlateBroken extends GameEvent {
  const BossPlateBroken(this.x, this.y);
  final double x;
  final double y;
}

class BossPhaseChanged extends GameEvent {
  const BossPhaseChanged(this.phase);
  final int phase;
}

/// A bullet bounced off a boss that cannot be hurt right now (entrance or
/// phase change).
class BossThrew extends GameEvent {
  const BossThrew(this.x, this.y);
  final double x;
  final double y;
}

class BossShielded extends GameEvent {
  const BossShielded(this.x, this.y);
  final double x;
  final double y;
}

/// A lightning column struck at [x] (it hurt the cannon if [hit]).
class ZapStrike extends GameEvent {
  const ZapStrike(this.x, this.halfWidth, {required this.hit});
  final double x;
  final double halfWidth;
  final bool hit;
}

/// A floor zone armed (lava starts burning / frost bursts).
class ZoneArmed extends GameEvent {
  const ZoneArmed(this.kind, this.x, this.halfWidth);
  final ZoneKind kind;
  final double x;
  final double halfWidth;
}

/// The cannon was caught in a freezing zone and moves slowly for a while.
class CannonChilled extends GameEvent {
  const CannonChilled(this.x, this.y);
  final double x;
  final double y;
}

/// The boss pulled its balls towards itself.
class BossPulled extends GameEvent {
  const BossPulled(this.x, this.y);
  final double x;
  final double y;
}

/// A treasure crystal left the arena without being popped.
class TreasureEscaped extends GameEvent {
  const TreasureEscaped(this.x, this.y);
  final double x;
  final double y;
}

class BossDefeated extends GameEvent {
  const BossDefeated(this.x, this.y);
  final double x;
  final double y;
}

class StageCleared extends GameEvent {
  const StageCleared();
}
