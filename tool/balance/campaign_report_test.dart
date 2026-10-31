// Plays the whole campaign with the scripted AutoPlayer and a
// realistic economy: the player starts with nothing, buys upgrades only
// with coins earned in play (run coins, clear bonuses, boss rewards), and
// replays the previous level to earn more after a failure. Writes the
// per-level table to build/campaign_report.md for docs/LEVEL_BALANCING.md.
//   flutter test tool/balance/campaign_report_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/campaign.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/game/sim/game_simulation.dart';
import 'package:orbit_blast/game/sim/seeded_random.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';

import '../../test/support/auto_player.dart';

class RunStats {
  RunStats(this.sim);
  final GameSimulation sim;

  /// What hit the cannon, by cause.
  final Map<String, int> causes = {};
  bool get cleared => sim.isStageCleared;
  double get seconds => sim.elapsed;
}

/// Plays [level] to the end (or [limit] simulated seconds).
RunStats play(
  int level,
  Loadout loadout, {
  double limit = 600,
  int attempt = 1,
}) {
  final sim = GameSimulation(
    loadout: loadout,
    seed: SeededRandom.hashString('boomforge-stage-$level') + attempt - 1,
    arenaHeight: 760,
    plan: StagePlan(level),
  );
  // Each retry plays out differently (seed and steering), like a person's.
  final player = AutoPlayer(
    maxSpeed: 520 - 40.0 * ((attempt - 1) % 3),
    lookAhead: 0.9 + 0.1 * ((attempt - 1) % 2),
  );
  final stats = RunStats(sim);
  while (!sim.isFinished && sim.elapsed < limit) {
    player.act(sim);
    final hullBefore = sim.hullLost;
    final shotsNear = sim.shots
        .where((s) => (s.x - sim.cannonX).abs() < 40 && s.y > sim.floorY - 110)
        .length;
    sim.step(Physics.fixedStep);
    final events = sim.drainEvents();
    if (sim.hullLost > hullBefore) {
      final b = sim.boss;
      final cause = events.any((e) => e is ZapStrike && e.hit)
          ? 'zap'
          : sim.balls.any((x) => sim.overlapsCannon(x)) ||
                sim.balls.any(
                  (x) =>
                      (x.x - sim.cannonX).abs() < x.radius + 30 &&
                      x.y > sim.floorY - 120,
                )
          ? 'ball'
          : shotsNear > 0
          ? 'shot'
          : sim.zones.any((z) => z.kind == ZoneKind.lava && z.armed)
          ? 'lava'
          : b != null && !b.dead
          ? 'slam'
          : 'other';
      stats.causes[cause] = (stats.causes[cause] ?? 0) + 1;
    }
  }
  return stats;
}

double dps(Loadout l) => l.shotsPerSecond * l.damage * l.streams;

/// Buys the upgrade with the best damage-per-second gain per coin until
/// nothing affordable is left. Element power and shields are bought as
/// side upgrades when they are cheap relative to the coin balance.
Future<void> shop(PlayerProgress p) async {
  for (var guard = 0; guard < 200; guard++) {
    final d = p.data;
    UpgradeType? best;
    var bestValue = 0.0;
    for (final type in [
      UpgradeType.fireRate,
      UpgradeType.bulletPower,
      UpgradeType.cannonLevel,
    ]) {
      final def = Upgrades.byType(type);
      final cost = def.costToUpgrade(d.level(type));
      if (cost == null || cost > d.coins) continue;
      final next = Map.of(d.upgrades)..[type] = d.level(type) + 1;
      final gain = dps(Upgrades.loadoutFor(next)) - dps(p.loadout);
      if (gain / cost > bestValue) {
        bestValue = gain / cost;
        best = type;
      }
    }
    if (best == null) {
      for (final side in [UpgradeType.elementPower, UpgradeType.coinBonus]) {
        final cost = Upgrades.byType(side).costToUpgrade(d.level(side));
        if (cost != null && cost * 4 < d.coins) best = side;
      }
    }
    if (best == null) return;
    await p.purchaseUpgrade(best, d.level(best));
  }
}

void main() {
  test('campaign playthrough report', () async {
    final progress = PlayerProgress(
      SaveRepository(InMemoryStore()),
      SaveData(tutorialDone: true),
    );
    var runId = 0;
    Future<CommitOutcome> commit(int level, RunStats r) => progress.commitRun(
      RunResult(
        runId: 'r${runId++}',
        score: r.sim.score,
        wave: r.sim.wave,
        wavesCleared: r.sim.wavesCleared,
        coins: r.sim.coins,
        ballsDestroyed: r.sim.ballsDestroyed,
        powerUpsUsed: r.sim.powerUpsUsed,
        stage: level,
        stageCleared: r.cleared,
        stars: r.cleared ? r.sim.stars : 0,
      ),
    );

    final rows = StringBuffer()
      ..writeln(
        '| Lvl | Ch | Category | Waves | Pace | Drift | Bounce | HP scale '
        '| Patterns / boss | Attempts | Clear s | Hits | Coins earned '
        '| DPS |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    var totalCoins = 0;
    var failures = 0;
    for (var n = 1; n <= StageSpec.levelCount; n++) {
      final level = Campaign.level(n);
      await shop(progress);
      var attempts = 0;
      RunStats? run;
      var earned = 0;
      while (true) {
        attempts++;
        run = play(n, progress.loadout, attempt: attempts);
        final before = progress.data.coins;
        await commit(n, run);
        earned += progress.data.coins - before;
        if (run.cleared || attempts >= 8) break;
        // Grind the previous level once and spend the coins.
        if (n > 1) {
          final grind = play(n - 1, progress.loadout);
          final b = progress.data.coins;
          await commit(n - 1, grind);
          earned += progress.data.coins - b;
        }
        await shop(progress);
      }
      if (!run.cleared) failures++;
      totalCoins += earned;
      final what = level.isBoss
          ? '**${level.boss!.name}**'
          : level.patterns.map((p) => p.name).join(', ');
      rows.writeln(
        '| $n | ${level.chapter} | ${level.category.name} | ${level.waves} '
        '| ${level.pace.toStringAsFixed(2)} '
        '| ${level.drift.toStringAsFixed(2)} | ${level.bounce.name} '
        '| ${level.durability.toStringAsFixed(0)} | $what '
        '| $attempts${run.cleared ? '' : ' (not cleared)'} '
        '| ${run.seconds.toStringAsFixed(0)} | ${run.sim.hullLost}'
        '${run.causes.isEmpty ? '' : ' ${run.causes}'} '
        '| $earned | ${dps(progress.loadout).toStringAsFixed(0)} |',
      );
    }
    final d = progress.data;
    final summary =
        'Campaign: cleared ${d.highestStageCleared}/${StageSpec.levelCount}, '
        'failures $failures, '
        'coins earned $totalCoins, final upgrades '
        '${d.upgrades.map((k, v) => MapEntry(k.name, v))}';
    Directory('build').createSync(recursive: true);
    File('build/campaign_report.md').writeAsStringSync('$summary\n\n$rows');
    // ignore: avoid_print
    print(summary);
    expect(failures, 0, reason: 'every level must be clearable');
  }, timeout: const Timeout(Duration(hours: 2)));

  test('speed stays inside the caps on every level', () {
    for (final level in Campaign.levels) {
      for (var w = 1; w <= level.waves; w++) {
        final plan = WaveDirector.buildLevelWave(
          level,
          w,
          SeededRandom(level.number * 31 + w),
        );
        expect(plan.pace, lessThanOrEqualTo(SpeedSpec.maxPace));
        expect(plan.drift, lessThanOrEqualTo(SpeedSpec.maxDrift));
      }
    }
    expect(math.max(0, 1), 1);
  });
}
