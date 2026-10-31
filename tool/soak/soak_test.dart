// Long-session soak test: an auto-player plays every stage with many seeds
// plus long endless runs, and every fixed step is checked for states that
// would make the game "stop working" after a while (NaN positions, enemies
// outside the arena or stuck entering, waves that never end, unbounded
// lists). Run:
//   flutter test tool/soak/soak_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

/// Moves the cannon under the lowest enemy, like a player chasing targets.
void autoPlay(GameSimulation sim) {
  Ball? target;
  for (final b in sim.balls) {
    if (target == null || b.y > target.y) target = b;
  }
  final goal = target?.x ?? sim.width / 2;
  final dx = (goal - sim.cannonX).clamp(-6.0, 6.0);
  sim.moveCannonBy(dx);
}

class Soak {
  Soak(this.label, this.sim);
  final String label;
  final GameSimulation sim;
  final List<String> problems = [];
  final Map<int, double> _entering = {};
  double _lastProgressAt = 0;
  int _lastScore = -1;
  int _maxBalls = 0;
  int _maxBullets = 0;
  int _maxPickups = 0;

  void _problem(String msg) {
    if (problems.length < 5) {
      problems.add(
        '$label t=${sim.elapsed.toStringAsFixed(1)} wave '
        '${sim.wave} phase ${sim.phase}: $msg',
      );
    }
  }

  String _ballInfo(Ball b) =>
      '#${b.id} ${b.kind.name} t${b.tier} hp${b.hp} armor${b.armor} '
      'x${b.x.toStringAsFixed(1)} y${b.y.toStringAsFixed(1)} '
      'vx${b.vx.toStringAsFixed(1)} vy${b.vy.toStringAsFixed(1)} '
      'entering ${b.entering} frozen ${b.frozen.toStringAsFixed(2)}';

  void check() {
    final s = sim;
    for (final b in s.balls) {
      if (!b.x.isFinite || !b.y.isFinite || !b.vx.isFinite || !b.vy.isFinite) {
        _problem('non-finite ball ${_ballInfo(b)}');
      }
      final r = b.radius;
      if (b.x < -3 * r || b.x > s.width + 3 * r || b.y > s.floorY + 2) {
        _problem('ball outside arena ${_ballInfo(b)}');
      }
      if (b.entering) {
        final t = (_entering[b.id] ?? 0) + Physics.fixedStep;
        _entering[b.id] = t;
        if (t > 8 && t < 8 + Physics.fixedStep * 1.5) {
          _problem('ball entering for 8s ${_ballInfo(b)}');
        }
      } else {
        _entering.remove(b.id);
      }
    }
    if (!s.cannonX.isFinite) _problem('cannon x not finite');
    _maxBalls = _maxBalls > s.balls.length ? _maxBalls : s.balls.length;
    _maxBullets = _maxBullets > s.bullets.length
        ? _maxBullets
        : s.bullets.length;
    _maxPickups = _maxPickups > s.pickups.length
        ? _maxPickups
        : s.pickups.length;
    if (s.bullets.length > 500) _problem('bullets ${s.bullets.length}');
    if (s.balls.length > 60) _problem('balls ${s.balls.length}');
    if (s.pickups.length > 120) _problem('pickups ${s.pickups.length}');
    if (s.events.length > 2000) _problem('events not drained');

    // Progress: score must move while the wave is being played.
    if (s.score != _lastScore || s.phase != RunPhase.playing) {
      _lastScore = s.score;
      _lastProgressAt = s.elapsed;
    } else if (s.elapsed - _lastProgressAt > 30) {
      _problem(
        'no progress for 30s; balls: '
        '${s.balls.map(_ballInfo).join(' | ')}; pending '
        '${s.pendingSpawns.length}; hazards ${s.hazards.length}; boss '
        '${s.boss == null ? '-' : 'dead ${s.boss!.dead}'}',
      );
      _lastProgressAt = s.elapsed;
    }
  }

  /// Plays up to [seconds] of simulated time.
  void run(double seconds, {bool invulnerable = true}) {
    final steps = (seconds / Physics.fixedStep).round();
    for (var i = 0; i < steps && !sim.isFinished; i++) {
      if (invulnerable) sim.invulnerableTimer = 1;
      autoPlay(sim);
      sim.step(Physics.fixedStep);
      sim.drainEvents();
      check();
    }
  }

  String get stats =>
      '$label: ${sim.elapsed.toStringAsFixed(0)}s wave ${sim.wave} '
      'finished ${sim.isFinished} | max balls $_maxBalls bullets '
      '$_maxBullets pickups $_maxPickups';
}

void main() {
  final strong = Upgrades.dailyChallengeLoadout;

  test('every level with several seeds finishes without stalls', () {
    final all = <String>[];
    final maxed = Upgrades.loadoutFor({
      UpgradeType.fireRate: 15,
      UpgradeType.bulletPower: 20,
      UpgradeType.cannonLevel: 5,
      UpgradeType.elementPower: 5,
    }, elements: Element.values.toSet());
    for (var stage = 1; stage <= StageSpec.levelCount; stage++) {
      // Early levels with the mid loadout, the rest with a maxed cannon so
      // the soak covers every level in reasonable time. Generated levels get
      // one seed each: there are nine times as many of them.
      final loadout = stage <= 10 ? strong : maxed;
      final seeds = stage <= StageSpec.authoredLevels ? 3 : 1;
      for (var seed = 1; seed <= seeds; seed++) {
        for (final element in [
          Element.values[seed % 4],
          Element.values[(seed + 2) % 4],
        ]) {
          final sim = GameSimulation(
            loadout: loadout,
            seed: seed * 31 + stage,
            arenaHeight: 780,
            plan: StagePlan(stage),
          )..setElement(element);
          final soak = Soak('stage $stage seed $seed ${element.name}', sim)
            ..run(900);
          all.addAll(soak.problems);
          if (!sim.isFinished) {
            all.add('${soak.stats} did not finish in 900s');
          }
        }
      }
    }
    for (final p in all.take(40)) {
      // ignore: avoid_print
      print(p);
    }
    expect(all, isEmpty);
  });

  test('long endless sessions stay healthy', () {
    final all = <String>[];
    for (final height in [Physics.minArenaHeight, 780.0, 900.0]) {
      for (var seed = 1; seed <= 4; seed++) {
        final sim = GameSimulation(
          loadout: strong,
          seed: seed,
          arenaHeight: height,
        )..setElement(Element.values[seed % Element.values.length]);
        final soak = Soak('endless h$height seed $seed', sim)..run(1800);
        // ignore: avoid_print
        print(soak.stats);
        all.addAll(soak.problems);
      }
    }
    for (final p in all.take(40)) {
      // ignore: avoid_print
      print(p);
    }
    expect(all, isEmpty);
  });
}
