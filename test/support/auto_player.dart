// A scripted player for balance reports and long simulations: it dodges
// telegraphed attacks, falling shards and incoming crystals, chases targets,
// picks sensible elements and uses power-ups in emergencies. It is not a
// perfect player (it reacts with a delay and moves at a finger's speed),
// which is what makes its clear times and hits useful for balancing.
import 'dart:math' as math;

import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/game/sim/boss.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';

class AutoPlayer {
  AutoPlayer({this.maxSpeed = 520, this.lookAhead = 0.9});

  /// Fastest steering speed in world units per second.
  final double maxSpeed;

  /// How far ahead (seconds of real time) crystals are predicted.
  final double lookAhead;

  double _goal = Physics.worldWidth / 2;
  int _tick = 0;

  /// Called once per fixed step before [GameSimulation.step].
  void act(GameSimulation sim) {
    if (sim.isFinished) return;
    if (_tick++ % 4 == 0) {
      _goal = _chooseX(sim);
      _chooseElement(sim);
      _usePowerUps(sim);
    }
    final dx = (_goal - sim.cannonX).clamp(
      -maxSpeed * Physics.fixedStep,
      maxSpeed * Physics.fixedStep,
    );
    sim.moveCannonBy(dx);
  }

  // ------------------------------------------------------------ steering

  double _chooseX(GameSimulation sim) {
    final target = _targetX(sim);
    const margin = CannonSpec.visualHalfWidth;
    var bestX = sim.cannonX;
    var bestCost = double.infinity;
    for (var x = margin; x <= sim.width - margin; x += 10) {
      final cost =
          _danger(sim, x) +
          (target == null ? 0 : (x - target).abs() * 0.15) +
          (x - sim.cannonX).abs() * 0.04;
      if (cost < bestCost) {
        bestCost = cost;
        bestX = x;
      }
    }
    return bestX;
  }

  double _danger(GameSimulation sim, double x) {
    const half = CannonSpec.bodyHalfWidth;
    var d = 0.0;
    // Telegraphed attacks and burning ground are certain hits; a crystal's
    // predicted path is only likely, so these weigh more.
    for (final t in sim.telegraphs) {
      if ((x - t.x).abs() < t.width + half + 8) d += t.slam ? 500 : 400;
    }
    for (final z in sim.zones) {
      if (z.armed && z.kind == ZoneKind.freeze) continue;
      if ((x - z.x).abs() < z.halfWidth + half + 8) {
        d += z.kind == ZoneKind.lava ? 500 : 200;
      }
    }
    final b = sim.boss;
    if (b != null && !b.dead && b.slam != SlamState.none) {
      if ((x - b.slamX).abs() < b.coreRadius + half + 10) d += 140;
    }
    final pace = sim.ballTimeScale;
    for (final s in sim.shots) {
      final dy = sim.floorY - 50 - s.y;
      if (dy < 0) continue;
      // Shards fall with gravity (in game time); convert to real seconds.
      const g = EnemySpec.shotGravity;
      final tGame = (-s.vy + math.sqrt(s.vy * s.vy + 2 * g * dy)) / g;
      final t = tGame / math.max(pace, 0.05);
      if (t > 1.4) continue;
      final px = s.x + s.vx * tGame;
      if ((x - px).abs() < 30 + s.weave.abs()) d += 160 * (1.5 - t);
    }
    for (final ball in sim.balls) {
      if (ball.isFlyer || ball.dead) continue;
      d += _ballThreat(sim, ball, x, pace);
    }
    return d;
  }

  /// Predicts [ball] for [lookAhead] seconds and scores how close it comes
  /// to a cannon standing at [x].
  double _ballThreat(GameSimulation sim, Ball ball, double x, double pace) {
    if (ball.isFrozen) return 0;
    var bx = ball.x;
    var by = ball.y;
    var vx = ball.vx;
    var vy = ball.vy;
    final r = ball.radius;
    const dt = 1 / 30;
    final move = pace * ball.moveScale;
    final top = sim.floorY - CannonSpec.barrelTipHeight;
    for (var t = 0.0; t < lookAhead; t += dt) {
      vy += Physics.gravity * dt * move;
      bx += vx * dt * move;
      by += vy * dt * move;
      if (by + r >= sim.floorY) {
        by = sim.floorY - r;
        vy = -sim.bounceSpeed(ball.tier);
      }
      if (bx - r < 0) {
        bx = r;
        vx = vx.abs();
      } else if (bx + r > sim.width) {
        bx = sim.width - r;
        vx = -vx.abs();
      }
      if (by + r > top && (bx - x).abs() < r + CannonSpec.bodyHalfWidth + 6) {
        return 400 * (1 - t / lookAhead) + 80;
      }
    }
    return 0;
  }

  /// Where the player wants to shoot.
  double? _targetX(GameSimulation sim) {
    final b = sim.boss;
    if (b != null && !b.dead) {
      // Plates/heads first (the matching head if any), then the core; with
      // weak windows, minions while the rift is shut.
      var plate = -1;
      for (var i = 0; i < b.plates.length; i++) {
        if (b.plates[i] <= 0) continue;
        final weak = b.def.plates[i].weakness;
        if (plate < 0 || (weak != null && weak == sim.element)) plate = i;
      }
      if (plate >= 0) return b.plateX(plate);
      if (b.hasWeakWindows && !b.weakOpen) {
        final low = _lowestBall(sim);
        if (low != null) return low.x;
      }
      return b.x;
    }
    return _lowestBall(sim)?.x;
  }

  Ball? _lowestBall(GameSimulation sim) {
    Ball? best;
    for (final ball in sim.balls) {
      if (ball.dead || ball.entering) continue;
      // Treasure is worth chasing; otherwise go for the lowest threat.
      final score = ball.isTreasure ? ball.y + 400 : ball.y;
      final bestScore = best == null
          ? double.negativeInfinity
          : (best.isTreasure ? best.y + 400 : best.y);
      if (score > bestScore) best = ball;
    }
    return best;
  }

  // ------------------------------------------------------------ elements

  void _chooseElement(GameSimulation sim) {
    final have = sim.loadout.elements;
    Element pick = have.contains(Element.fire) ? Element.fire : Element.kinetic;
    final b = sim.boss;
    if (b != null && !b.dead) {
      for (var i = 0; i < b.plates.length; i++) {
        final weak = b.def.plates[i].weakness;
        if (b.plates[i] > 0 && weak != null && have.contains(weak)) {
          pick = weak;
          break;
        }
      }
    } else {
      final target = _lowestBall(sim);
      final a = target?.affinity;
      if (a != null) {
        final counter = Affinity.weakness(a);
        if (have.contains(counter)) {
          pick = counter;
        } else if (pick == a) {
          pick = Element.kinetic;
        }
      } else if (target != null &&
          !target.armored &&
          sim.balls.length >= 5 &&
          have.contains(Element.electric)) {
        pick = Element.electric;
      }
    }
    if (pick != sim.element) sim.setElement(pick);
  }

  // ------------------------------------------------------------ power-ups

  void _usePowerUps(GameSimulation sim) {
    final danger = _danger(sim, sim.cannonX);
    if (sim.hull <= 1 && danger > 100) {
      if (sim.canActivate(PowerUpType.bomb)) {
        sim.activatePowerUp(PowerUpType.bomb);
        return;
      }
      if (sim.canActivate(PowerUpType.shield)) {
        sim.activatePowerUp(PowerUpType.shield);
        return;
      }
    }
    if (sim.balls.length >= 7 && sim.canActivate(PowerUpType.slowMotion)) {
      sim.activatePowerUp(PowerUpType.slowMotion);
    }
    final b = sim.boss;
    if (b != null &&
        !b.dead &&
        b.transition <= 0 &&
        (b.platesLeft == 0 || b.weakOpen) &&
        sim.canActivate(PowerUpType.powerShot)) {
      sim.activatePowerUp(PowerUpType.powerShot);
    }
  }
}
