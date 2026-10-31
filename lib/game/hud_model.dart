import 'package:flutter/foundation.dart';

import '../config/balance.dart';
import 'sim/entities.dart';
import 'sim/game_simulation.dart';

/// Snapshot of what the Flutter HUD shows. Updated by the game once per
/// frame but only notifies listeners when a visible value changed, so the
/// widget tree is not rebuilt every frame.
class HudModel extends ChangeNotifier {
  int score = 0;
  int coins = 0;
  int wave = 1;
  int? waveCount;
  int remaining = 0;
  int hull = PlayerSpec.baseHull;
  int maxHull = PlayerSpec.baseHull;
  bool shieldActive = false;
  Element element = Element.kinetic;
  Set<Element> elements = const {Element.kinetic};

  /// Boss core fraction (null when no boss is alive) and phase.
  double? bossFraction;
  int bossPhase = 1;
  int bossPhases = 3;
  int bossBallsLeft = 0;
  String bossName = '';

  /// The boss's weak point is open (Void Devourer, Worldbreaker).

  /// The cannon is frosted and steers slowly.
  bool cannonSlowed = false;

  final Map<PowerUpType, int> inventory = {
    for (final t in PowerUpType.values) t: 0,
  };

  /// Remaining fraction (1..0) of timed effects, quantised to 2%.
  final Map<PowerUpType, double> activeFraction = {
    for (final t in PowerUpType.values) t: 0,
  };
  final Map<PowerUpType, bool> available = {
    for (final t in PowerUpType.values) t: false,
  };

  void sync(GameSimulation sim) {
    var changed = false;
    void set<T>(T current, T next, void Function(T) assign) {
      if (current != next) {
        assign(next);
        changed = true;
      }
    }

    set(score, sim.score, (v) => score = v);
    set(coins, sim.coins, (v) => coins = v);
    set(wave, sim.wave, (v) => wave = v);
    set(waveCount, sim.plan.waveCount, (v) => waveCount = v);
    set(remaining, sim.remainingInWave, (v) => remaining = v);
    set(hull, sim.hull, (v) => hull = v);
    set(maxHull, sim.loadout.hull, (v) => maxHull = v);
    set(shieldActive, sim.shieldActive, (v) => shieldActive = v);
    set(element, sim.element, (v) => element = v);
    if (!setEquals(elements, sim.loadout.elements)) {
      elements = sim.loadout.elements;
      changed = true;
    }
    final b = sim.boss;
    final alive = b != null && !b.dead;
    final fraction = alive ? _quantise(b.coreFraction) : null;
    set(bossFraction, fraction, (v) => bossFraction = v);
    set(bossPhase, alive ? b.phase : 1, (v) => bossPhase = v);
    set(bossBallsLeft, alive ? b.unitsLeft : 0, (v) => bossBallsLeft = v);
    if (b != null) {
      set(bossPhases, b.phaseCount, (v) => bossPhases = v);
      set(bossName, b.def.name, (v) => bossName = v);
    }
    set(cannonSlowed, sim.cannonSlowed, (v) => cannonSlowed = v);
    for (final type in PowerUpType.values) {
      set(
        inventory[type],
        sim.inventory[type] ?? 0,
        (v) => inventory[type] = v!,
      );
      set(available[type], sim.canActivate(type), (v) => available[type] = v!);
      final f = _quantise(_fraction(sim, type));
      set(activeFraction[type], f, (v) => activeFraction[type] = v!);
    }
    if (changed) notifyListeners();
  }

  static double _fraction(GameSimulation sim, PowerUpType type) {
    final (remaining, total) = switch (type) {
      PowerUpType.bomb => (0.0, 1.0),
      PowerUpType.slowMotion => (sim.slowTimer, PowerUpSpec.slowMotionDuration),
      PowerUpType.shield =>
        sim.shieldTimer.isInfinite
            ? (1.0, 1.0)
            : (sim.shieldTimer, PowerUpSpec.shieldDuration),
      PowerUpType.powerShot => (
        sim.powerShotTimer,
        PowerUpSpec.powerShotDuration,
      ),
    };
    return (remaining / total).clamp(0.0, 1.0);
  }

  static double _quantise(double v) => (v * 50).ceil() / 50;
}
