import 'dart:math' as math;

import '../../config/balance.dart';
import '../../config/bosses.dart';

enum SlamState { none, aiming, diving, rising }

enum WeakState { closed, warning, open }

/// Runtime state of a campaign boss. The rules for every boss live in
/// [GameSimulation]; what differs between bosses is data in [def]: phases,
/// attacks and looks.
///
/// A boss carries a fixed supply of balls ([ballQueue]) and keeps throwing
/// them. Bullets cannot hurt it: every ball destroyed, split pieces included,
/// takes its share of the boss's health, and when the last ball is gone the
/// boss goes down.
class Boss {
  Boss({
    required this.def,
    required List<int> balls,
    required this.throwInterval,
    required this.homeY,
    required this.x,
  }) : ballQueue = List.of(balls),
       unitsTotal = balls.fold(0, (sum, tier) => sum + piecesOf(tier)),
       unitsLeft = balls.fold(0, (sum, tier) => sum + piecesOf(tier)),
       plates = List.filled(def.plates.length, plateMax),
       y = -def.coreRadius * 1.6;

  /// A plate is drawn whole until it breaks.
  static const double plateMax = 1;

  /// Balls destroyed to clear one thrown ball of [tier], as it splits in two
  /// on the way down: tier 2 is itself, two tier 1s and four tier 0s.
  static int piecesOf(int tier) => (1 << (tier + 1)) - 1;

  final BossDef def;
  final double homeY;

  /// Ball tiers still to throw, in order.
  final List<int> ballQueue;

  /// Seconds between throws in the first phase.
  final double throwInterval;

  /// Health, counted in ball pieces.
  final int unitsTotal;
  int unitsLeft;

  /// Armour falls off as health drops; 0 = broken.
  final List<double> plates;
  double x;
  double y;
  double dir = 1;
  int phase = 1;
  bool dead = false;

  /// While > 0 the boss does not attack (entrance and phase changes).
  double transition = 0;

  /// Seconds until each attack of the current phase may fire.
  final Map<BossAttack, double> timers = {};

  /// Seconds until any attack may start (see [BossSpec.attackGap]).
  double attackGap = 0;

  /// Seconds until the next ball is thrown.
  double throwTimer = BossSpec.firstThrowDelay;

  /// Seconds left of the throwing motion, for the renderer.
  double throwRecoil = 0;

  SlamState slam = SlamState.none;
  double slamX = 0;
  double slamTimerLeft = 0;

  /// A slam can cost the player at most one heart.
  bool slamHit = false;

  WeakState weak = WeakState.closed;
  double hitFlash = 0;

  /// Cooldown for the spark shown when a bullet passes through.
  double shieldFx = 0;

  double get coreRadius => def.coreRadius;
  int get phaseCount => def.phases.length;
  PhaseDef get phaseDef => def.phases[phase - 1];
  int get platesLeft => plates.where((p) => p > 0).length;
  bool get hasWeakWindows => phaseDef.weakWindows;

  /// Health left, 0 to 1.
  double get coreFraction => (unitsLeft / unitsTotal).clamp(0.0, 1.0);
  double get speed => phaseDef.moveSpeed;

  /// Seconds between throws now: each phase throws faster than the last.
  double get currentThrowInterval =>
      throwInterval * math.pow(BossSpec.throwPhaseScale, phase - 1);

  /// The throwing motion: -1 fully wound up, 1 at the moment of release,
  /// 0 at rest.
  double get throwPose {
    if (throwRecoil > 0) return throwRecoil / BossSpec.throwRecoilTime;
    if (ballQueue.isEmpty || transition > 0) return 0;
    if (throwTimer >= BossSpec.throwWindup) return 0;
    return -(1 - throwTimer / BossSpec.throwWindup);
  }

  double plateX(int i) => x + def.plates[i].dx;
  double plateY(int i) => y + def.plates[i].dy;
  double plateRadius(int i) => def.plates[i].radius;

  /// Phase implied by remaining health: equal slices per phase.
  int get targetPhase {
    final n = phaseCount;
    return (((1 - coreFraction) * n).floor() + 1).clamp(1, n);
  }

  /// Base interval of an attack in the current phase.
  double interval(BossAttack a) =>
      phaseDef.tempo *
      switch (a) {
        BossAttack.rain => BossSpec.rainInterval,
        BossAttack.slam => BossSpec.slamInterval,
        BossAttack.minions => BossSpec.spawnInterval,
        BossAttack.fan => BossSpec.fanInterval,
        BossAttack.zap => BossSpec.zapInterval,
        BossAttack.lava => BossSpec.lavaInterval,
        BossAttack.freeze => BossSpec.freezeInterval,
        BossAttack.curve => BossSpec.curveInterval,
        BossAttack.pull => BossSpec.pullInterval,
      };

  /// Resets attack timers for the current phase, staggered so the first
  /// attacks of a phase do not all start together.
  void armPhase() {
    timers.clear();
    var k = 0;
    for (final a in phaseDef.attacks) {
      timers[a] = 1.5 + k * 1.3;
      k++;
    }
    if (phaseDef.attacks.contains(BossAttack.slam)) {
      timers[BossAttack.slam] = 3.5;
    }
  }
}
