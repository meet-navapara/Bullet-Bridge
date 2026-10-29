// Prints the durability budget per wave and how long a cannon needs to
// clear it at several upgrade states. Used for docs/GAME_BALANCING.md.
//   flutter test tool/balance/balance_report_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/sim/seeded_random.dart';
import 'package:orbit_blast/game/sim/wave_director.dart';

void main() {
  test('balance report', () {
    final loadouts = {
      'base': Upgrades.loadoutFor({}),
      'mid (FR6 BP4 C3)': Upgrades.loadoutFor({
        UpgradeType.fireRate: 6,
        UpgradeType.bulletPower: 4,
        UpgradeType.cannonLevel: 3,
      }),
      'late (FR12 BP12 C5)': Upgrades.loadoutFor({
        UpgradeType.fireRate: 12,
        UpgradeType.bulletPower: 12,
        UpgradeType.cannonLevel: 5,
      }),
    };
    final rows = StringBuffer('| Wave | Balls | Max tier | Total hits |');
    for (final name in loadouts.keys) {
      rows.write(' $name (s) |');
    }
    rows.writeln();
    for (final wave in [1, 2, 3, 5, 8, 10, 15, 20, 25, 30]) {
      final spawns = WaveDirector.buildWave(wave, SeededRandom(wave));
      final hits = spawns.fold<int>(
        0,
        (sum, s) => sum + WaveDirector.totalDurability(s.tier, s.hp),
      );
      rows.write(
        '| $wave | ${spawns.length} | ${WaveSpec.maxTierFor(wave)} | $hits |',
      );
      for (final l in loadouts.values) {
        final dps = l.shotsPerSecond * l.damage * l.streams;
        rows.write(' ${(hits / dps).toStringAsFixed(1)} |');
      }
      rows.writeln();
    }
    for (final e in loadouts.entries) {
      final l = e.value;
      // ignore: avoid_print
      print(
        '${e.key}: ${l.shotsPerSecond.toStringAsFixed(1)} shots/s x ${l.damage} dmg x ${l.streams} = ${(l.shotsPerSecond * l.damage * l.streams).toStringAsFixed(1)} DPS',
      );
    }
    // ignore: avoid_print
    print(rows);
    var total = 0;
    for (final def in Upgrades.all) {
      var sum = 0;
      for (var lv = def.minLevel; lv < def.maxLevel; lv++) {
        sum += def.costToUpgrade(lv)!;
      }
      total += sum;
      // ignore: avoid_print
      print(
        '${def.title}: first ${def.costToUpgrade(def.minLevel)}, all levels $sum',
      );
    }
    // ignore: avoid_print
    print('All upgrades maxed: $total');
  });
}
