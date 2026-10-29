import 'dart:math' as math;

import '../../config/balance.dart';
import '../../config/bosses.dart';

enum SlamState { none, aiming, diving, rising }

enum WeakState { closed, warning, open }

/// Runtime state of a campaign boss. The rules for every boss live in
/// [GameSimulation]; what differs between bosses is data in [def]:
/// armour plates (or heads), phases, attacks and special mechanics.
class Boss {
  Boss({
    required this.def,
    required this.coreMax,
    required this.plateMax,
    required this.homeY,
    required this.x,
  }) : core = coreMax,
       plates = List.filled(def.plates.length, plateMax),
       y = -def.coreRadius * 1.6;

  final BossDef def;
  final double coreMax;
  final double plateMax;
  final double homeY;
  double core;

  /// Durability of each plate/head; 0 = broken.
  final List<double> plates;
  double x;
  double y;
  double dir = 1;
  int phase = 1;
  bool dead = false;

  /// While > 0 the boss is invulnerable and does not attack (entrance and
  /// phase changes).
  double transition = 0;

  /// Seconds until each attack of the current phase may fire.
  final Map<BossAttack, double> timers = {};

  /// Seconds until any attack may start (see [BossSpec.attackGap]).
  double attackGap = 0;

  SlamState slam = SlamState.none;
  double slamX = 0;
  double slamTimerLeft = 0;

  /// A slam can cost the player at most one heart.
  bool slamHit = false;

  WeakState weak = WeakState.closed;
  double weakTimer = BossSpec.weakClosed;
  double hitFlash = 0;

  /// Cooldown for the "shielded" spark shown while invulnerable.
  double shieldFx = 0;

  double get coreRadius => def.coreRadius;
  int get phaseCount => def.phases.length;
  PhaseDef get phaseDef => def.phases[phase - 1];
  int get platesLeft => plates.where((p) => p > 0).length;
  int get platesBroken => plates.length - platesLeft;
  bool get hasWeakWindows => phaseDef.weakWindows;
  bool get weakOpen => hasWeakWindows && weak == WeakState.open;

  /// Core damage multiplier from broken plates and the weak-point window.
  double get exposure {
    final base = def.exposure[math.min(platesBroken, def.exposure.length - 1)];
    if (!hasWeakWindows) return base;
    return base *
        (weak == WeakState.open
            ? BossSpec.weakOpenExposure
            : BossSpec.weakClosedExposure);
  }

  double get coreFraction => (core / coreMax).clamp(0.0, 1.0);
  double get speed => phaseDef.moveSpeed;

  double plateX(int i) => x + def.plates[i].dx;
  double plateY(int i) => y + def.plates[i].dy;
  double plateRadius(int i) => def.plates[i].radius;

  /// Phase implied by remaining core durability: equal slices per phase.
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
