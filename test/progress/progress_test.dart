import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_blast/config/balance.dart';
import 'package:orbit_blast/config/bosses.dart';
import 'package:orbit_blast/economy/catalog.dart';
import 'package:orbit_blast/economy/upgrades.dart';
import 'package:orbit_blast/game/sim/entities.dart';
import 'package:orbit_blast/progress/achievements.dart';
import 'package:orbit_blast/progress/daily.dart';
import 'package:orbit_blast/progress/player_progress.dart';
import 'package:orbit_blast/progress/save_data.dart';
import 'package:orbit_blast/progress/save_repository.dart';

class Harness {
  Harness({SaveData? data, DateTime? now}) : store = InMemoryStore() {
    repo = SaveRepository(store);
    clock = now ?? DateTime(2026, 10, 27, 12);
    progress = PlayerProgress(repo, data ?? SaveData(), clock: () => clock);
  }

  final InMemoryStore store;
  late final SaveRepository repo;
  late final PlayerProgress progress;
  late DateTime clock;

  Future<SaveData> reload() async => (await repo.load()).data;
}

RunResult run(
  String id, {
  int score = 100,
  int coins = 10,
  int wave = 3,
  int balls = 20,
  String? challengeDate,
}) => RunResult(
  runId: id,
  score: score,
  wave: wave,
  wavesCleared: wave - 1,
  coins: coins,
  ballsDestroyed: balls,
  powerUpsUsed: 1,
  challengeDate: challengeDate,
);

void main() {
  group('upgrade definitions', () {
    test('costs grow and stop at max level', () {
      final fire = Upgrades.byType(UpgradeType.fireRate);
      expect(fire.costToUpgrade(1), UpgradeSpec.fireRateBaseCost);
      expect(fire.costToUpgrade(2)!, greaterThan(fire.costToUpgrade(1)!));
      expect(fire.costToUpgrade(fire.maxLevel), isNull);
      for (final def in Upgrades.all) {
        for (var l = def.minLevel; l < def.maxLevel; l++) {
          expect(def.costToUpgrade(l)! % 10, 0, reason: 'prices are rounded');
        }
      }
    });

    test('loadout reflects upgrade effects', () {
      final base = Upgrades.loadoutFor(SaveData.defaultUpgrades());
      expect(base.shotsPerSecond, UpgradeSpec.fireRateBase);
      expect(base.damage, 1);
      expect(base.streams, 1);
      expect(base.coinMultiplier, 1);

      final upgraded = Upgrades.loadoutFor({
        UpgradeType.fireRate: 3,
        UpgradeType.bulletPower: 5,
        UpgradeType.cannonLevel: 3,
        UpgradeType.coinBonus: 2,
        UpgradeType.startingShield: 1,
      });
      expect(upgraded.damage, 5);
      expect(upgraded.streams, 2);
      expect(upgraded.coinMultiplier, closeTo(1.2, 1e-9));
      expect(upgraded.shotsPerSecond, greaterThan(base.shotsPerSecond));
      expect(Upgrades.streams(5), 3);
    });
  });

  group('purchases', () {
    test('successful purchase deducts coins and persists', () async {
      final h = Harness(data: SaveData(coins: 1000));
      final cost = Upgrades.byType(UpgradeType.fireRate).costToUpgrade(1)!;
      expect(
        await h.progress.purchaseUpgrade(UpgradeType.fireRate, 1),
        PurchaseResult.success,
      );
      expect(h.progress.data.coins, 1000 - cost);
      expect(h.progress.data.level(UpgradeType.fireRate), 2);
      final saved = await h.reload();
      expect(saved.coins, 1000 - cost);
      expect(saved.level(UpgradeType.fireRate), 2);
      expect(saved.stats.upgradesBought, 1);
    });

    test('insufficient funds changes nothing', () async {
      final h = Harness(data: SaveData(coins: 5));
      expect(
        await h.progress.purchaseUpgrade(UpgradeType.fireRate, 1),
        PurchaseResult.insufficientFunds,
      );
      expect(h.progress.data.coins, 5);
      expect(h.progress.data.level(UpgradeType.fireRate), 1);
      expect(h.store.values, isEmpty, reason: 'nothing written');
    });

    test('a double tap buys only one level', () async {
      final h = Harness(data: SaveData(coins: 100000));
      final results = await Future.wait([
        h.progress.purchaseUpgrade(UpgradeType.bulletPower, 1),
        h.progress.purchaseUpgrade(UpgradeType.bulletPower, 1),
      ]);
      expect(
        results,
        containsAll([PurchaseResult.success, PurchaseResult.stale]),
      );
      expect(h.progress.data.level(UpgradeType.bulletPower), 2);
      expect(
        h.progress.data.coins,
        100000 - Upgrades.byType(UpgradeType.bulletPower).costToUpgrade(1)!,
      );
    });

    test('maxed upgrade cannot be bought', () async {
      final def = Upgrades.byType(UpgradeType.startingShield);
      final h = Harness(
        data: SaveData(
          coins: 999999,
          upgrades: {
            ...SaveData.defaultUpgrades(),
            UpgradeType.startingShield: def.maxLevel,
          },
        ),
      );
      expect(
        await h.progress.purchaseUpgrade(
          UpgradeType.startingShield,
          def.maxLevel,
        ),
        PurchaseResult.maxed,
      );
      expect(h.progress.data.coins, 999999);
    });

    test('failed save keeps the previous state', () async {
      final h = Harness(data: SaveData(coins: 1000));
      h.store.failWrites = true;
      expect(
        await h.progress.purchaseUpgrade(UpgradeType.fireRate, 1),
        PurchaseResult.saveFailed,
      );
      expect(h.progress.data.coins, 1000);
      expect(h.progress.data.level(UpgradeType.fireRate), 1);
    });

    test('skins: buy, own, select; cannot buy twice or go negative', () async {
      final h = Harness(data: SaveData(coins: 600));
      expect(
        await h.progress.buySkin('nebula'),
        PurchaseResult.insufficientFunds,
      );
      expect(await h.progress.buySkin('ember'), PurchaseResult.success);
      expect(h.progress.data.coins, 100);
      expect(h.progress.data.selectedSkin, 'ember');
      expect(await h.progress.buySkin('ember'), PurchaseResult.stale);
      expect(h.progress.data.coins, 100);
      expect(await h.progress.selectSkin(Catalog.defaultSkinId), isTrue);
      expect(
        await h.progress.selectSkin('solar'),
        isFalse,
        reason: 'not owned',
      );
      expect(await h.progress.buyTheme('nope'), PurchaseResult.invalid);
    });
  });

  group('run commits', () {
    test('a run is committed exactly once', () async {
      final h = Harness();
      final first = await h.progress.commitRun(run('a', score: 500, coins: 40));
      expect(first.accepted, isTrue);
      expect(first.newBestScore, isTrue);
      final again = await h.progress.commitRun(run('a', score: 500, coins: 40));
      expect(again.accepted, isFalse);
      final d = h.progress.data;
      expect(d.coins, 40);
      expect(d.bestScore, 500);
      expect(d.stats.gamesPlayed, 1);
      expect(d.stats.ballsDestroyed, 20);
      // Also rejected after a restart (reloaded from storage).
      final reloaded = Harness();
      final p2 = PlayerProgress(h.repo, await h.reload());
      expect((await p2.commitRun(run('a'))).accepted, isFalse);
      expect(reloaded.progress.data.coins, 0);
    });

    test('best score and wave only increase', () async {
      final h = Harness();
      await h.progress.commitRun(run('1', score: 900, wave: 8));
      final r = await h.progress.commitRun(run('2', score: 300, wave: 2));
      expect(r.newBestScore, isFalse);
      expect(h.progress.data.bestScore, 900);
      expect(h.progress.data.bestWave, 8);
    });

    test('daily challenge reward is paid once per day', () async {
      final h = Harness();
      final c = h.progress.todaysChallenge;
      final enough = switch (c.goal) {
        ChallengeGoalType.reachWave => run(
          'c1',
          wave: c.target,
          challengeDate: c.date,
          coins: 0,
        ),
        ChallengeGoalType.destroyBalls => run(
          'c1',
          balls: c.target,
          challengeDate: c.date,
          coins: 0,
        ),
        ChallengeGoalType.score => run(
          'c1',
          score: c.target,
          challengeDate: c.date,
          coins: 0,
        ),
      };
      final r1 = await h.progress.commitRun(enough);
      expect(r1.challengeReward, DailySpec.challengeReward);
      expect(h.progress.data.coins, DailySpec.challengeReward);
      final second = RunResult(
        runId: 'c2',
        score: enough.score,
        wave: enough.wave,
        wavesCleared: 0,
        coins: 0,
        ballsDestroyed: enough.ballsDestroyed,
        powerUpsUsed: 0,
        challengeDate: c.date,
      );
      final r2 = await h.progress.commitRun(second);
      expect(r2.challengeReward, 0);
      expect(h.progress.data.coins, DailySpec.challengeReward);
      expect(
        c.bestToday(h.progress.data.daily),
        greaterThanOrEqualTo(c.target),
      );
    });

    test('bonus power-ups are handed out once', () async {
      final h = Harness(
        data: SaveData(daily: DailyState(bonusPowerUpsPending: 1)),
      );
      final first = await h.progress.takeBonusPowerUps();
      expect(first[PowerUpType.bomb], 1);
      expect(await h.progress.takeBonusPowerUps(), isEmpty);
    });
  });

  group('achievements', () {
    test('claimable once when complete', () async {
      final h = Harness(
        data: SaveData(stats: LifetimeStats(ballsDestroyed: 120)),
      );
      expect(await h.progress.claimAchievement('destroy_500'), isNull);
      expect(await h.progress.claimAchievement('destroy_100'), 50);
      expect(await h.progress.claimAchievement('destroy_100'), isNull);
      expect(h.progress.data.coins, 50);
      expect(
        Achievements.byId('destroy_100')!.isClaimed(h.progress.data),
        isTrue,
      );
    });

    test('progress comes from real stats after a run', () async {
      final h = Harness();
      await h.progress.commitRun(run('x', balls: 100));
      expect(
        Achievements.claimableCount(h.progress.data),
        greaterThanOrEqualTo(1),
      );
      expect(
        Achievements.byId('destroy_100')!.canClaim(h.progress.data),
        isTrue,
      );
    });
  });

  group('daily reward', () {
    test(
      'streak advances on consecutive days and resets after a gap',
      () async {
        final h = Harness(now: DateTime(2026, 1, 1, 9));
        expect(await h.progress.claimDailyReward(), DailySpec.rewardCoins[0]);
        expect(await h.progress.claimDailyReward(), isNull, reason: 'same day');
        h.clock = DateTime(2026, 1, 2, 23, 59);
        expect(await h.progress.claimDailyReward(), DailySpec.rewardCoins[1]);
        h.clock = DateTime(2026, 1, 4, 8);
        expect(
          await h.progress.claimDailyReward(),
          DailySpec.rewardCoins[0],
          reason: 'missed a day',
        );
        expect(h.progress.data.daily.streakDay, 1);
      },
    );

    test('day 7 wraps to day 1 and day 5 grants power-ups', () {
      final d = SaveData();
      var t = DateTime(2026, 3, 1, 10);
      final days = <int>[];
      for (var i = 0; i < 8; i++) {
        DailyRewards.claim(d, t);
        days.add(d.daily.streakDay);
        t = t.add(const Duration(days: 1));
      }
      expect(days, [1, 2, 3, 4, 5, 6, 7, 1]);
      expect(d.daily.bonusPowerUpsPending, DailySpec.day5BonusPowerUps);
    });

    test('moving the clock backwards cannot farm rewards', () {
      final d = SaveData();
      DailyRewards.claim(d, DateTime(2026, 5, 10, 12));
      final status = DailyRewards.status(d.daily, DateTime(2026, 5, 9, 12));
      expect(status.availability, DailyRewardAvailability.clockRolledBack);
      expect(DailyRewards.claim(d, DateTime(2026, 5, 9, 12)), isNull);
    });

    test('reset progress does not re-open today\'s reward', () async {
      final h = Harness();
      await h.progress.claimDailyReward();
      await h.progress.resetProgress();
      expect(h.progress.data.coins, 0);
      expect(await h.progress.claimDailyReward(), isNull);
    });

    test('ad coin rewards are limited per day', () async {
      final h = Harness();
      for (var i = 0; i < AdSpec.rewardedCoinsPerDay; i++) {
        expect(await h.progress.grantAdCoins(), AdSpec.rewardedCoins);
      }
      expect(await h.progress.grantAdCoins(), isNull);
      expect(h.progress.canWatchAdForCoins, isFalse);
      h.clock = h.clock.add(const Duration(days: 1));
      expect(h.progress.canWatchAdForCoins, isTrue);
    });
  });

  group('daily challenge', () {
    test('is deterministic per date', () {
      final a = DailyChallenge.forDate(DateTime(2026, 10, 27, 1));
      final b = DailyChallenge.forDate(DateTime(2026, 10, 27, 23));
      expect(a.seed, b.seed);
      expect(a.goal, b.goal);
      expect(a.target, b.target);
      final seeds = {
        for (var i = 1; i <= 10; i++)
          DailyChallenge.forDate(DateTime(2026, 1, i)).seed,
      };
      expect(seeds.length, 10);
    });
  });

  group('campaign', () {
    RunResult stageRun(
      String id,
      int stage, {
      bool cleared = true,
      int stars = 3,
    }) => RunResult(
      runId: id,
      score: 500,
      wave: 3,
      wavesCleared: 3,
      coins: 10,
      ballsDestroyed: 30,
      powerUpsUsed: 0,
      stage: stage,
      stageCleared: cleared,
      stars: stars,
      bestChain: 4,
    );

    test(
      'first clear unlocks the next stage and pays a double bonus',
      () async {
        final h = Harness();
        expect(h.progress.nextStage, 1);
        expect(h.progress.isStageUnlocked(2), isFalse);
        final first = await h.progress.commitRun(stageRun('a', 1, stars: 2));
        expect(first.firstClear, isTrue);
        final bonus = StageSpec.clearBonusBase + StageSpec.clearBonusPerStage;
        expect(first.stageBonus, bonus * 2);
        expect(h.progress.data.coins, 10 + bonus * 2);
        expect(h.progress.isStageUnlocked(2), isTrue);
        expect(h.progress.nextStage, 2);
        expect(h.progress.data.stageStars[1], 2);
        expect(
          h.progress.data.bestWave,
          0,
          reason: 'stage waves are not endless waves',
        );
        expect(h.progress.data.bestChain, 4);

        final replay = await h.progress.commitRun(stageRun('b', 1, stars: 3));
        expect(replay.firstClear, isFalse);
        // Replays pay a small share of the bonus (scaled by stars).
        expect(
          replay.stageBonus,
          (bonus * StageSpec.replayBonusFraction * 1.15).round(),
        );
        expect(replay.stageBonus, lessThan(bonus));
        expect(h.progress.data.stageStars[1], 3);
        await h.progress.commitRun(stageRun('c', 1, stars: 1));
        expect(
          h.progress.data.stageStars[1],
          3,
          reason: 'stars never decrease',
        );
      },
    );

    test('only the next locked level advances progress', () async {
      final h = Harness();
      final skip = await h.progress.commitRun(stageRun('s', 5));
      expect(skip.firstClear, isFalse);
      expect(skip.stageBonus, 0, reason: 'level 5 was still locked');
      expect(h.progress.data.highestStageCleared, 0);
      expect(h.progress.isStageUnlocked(5), isFalse);
      await h.progress.commitRun(stageRun('1', 1));
      expect(h.progress.isStageUnlocked(2), isTrue);
      expect(h.progress.isStageUnlocked(3), isFalse);
    });

    test('a boss win pays the chapter reward exactly once', () async {
      final h = Harness(data: SaveData(highestStageCleared: 19));
      final win = await h.progress.commitRun(stageRun('b1', 20));
      expect(win.chapterCompleted, 2);
      expect(win.bossReward, Bosses.of(BossId.stormEngine).reward.coins);
      expect(win.rewardSkin, 'storm');
      expect(h.progress.data.ownedSkins, contains('storm'));
      expect(h.progress.data.chapterRewards, {2});
      final coins = h.progress.data.coins;
      final again = await h.progress.commitRun(stageRun('b2', 20));
      expect(again.bossReward, 0);
      expect(again.chapterCompleted, isNull);
      expect(
        h.progress.data.coins - coins,
        again.stageBonus + 10,
        reason: 'a replay pays only the run coins and the replay bonus',
      );
      // Committing the same run id twice changes nothing.
      final dup = await h.progress.commitRun(stageRun('b2', 20));
      expect(dup.accepted, isFalse);
    });

    test('boss reward skins cannot be bought', () async {
      final h = Harness(data: SaveData(coins: 999999));
      expect(await h.progress.buySkin('worldbreaker'), PurchaseResult.invalid);
      expect(h.progress.data.ownedSkins, isNot(contains('worldbreaker')));
    });

    test('level bests are tracked per level', () async {
      final h = Harness();
      final r = await h.progress.commitRun(stageRun('x', 1, cleared: false));
      expect(r.newLevelBest, isTrue);
      expect(h.progress.data.levelBest[1], 500);
    });

    test('the campaign ends at level 100', () async {
      final h = Harness(data: SaveData(highestStageCleared: 99));
      expect(h.progress.nextStage, 100);
      await h.progress.commitRun(stageRun('w', 100));
      expect(h.progress.campaignComplete, isTrue);
      expect(h.progress.nextStage, 100);
    });

    test('failed stages give no bonus and unlock nothing', () async {
      final h = Harness();
      final r = await h.progress.commitRun(stageRun('f', 1, cleared: false));
      expect(r.stageBonus, 0);
      expect(h.progress.data.highestStageCleared, 0);
      expect(h.progress.data.coins, 10, reason: 'collected coins are kept');
    });

    test('elements unlock as stages are cleared', () async {
      final h = Harness();
      expect(h.progress.unlockedElements, {Element.kinetic});
      await h.progress.commitRun(stageRun('1', 1));
      final r = await h.progress.commitRun(stageRun('2', 2));
      expect(r.unlocked, Element.fire);
      expect(
        h.progress.loadout.elements,
        containsAll([Element.kinetic, Element.fire]),
      );
      expect(
        Upgrades.elementsUnlocked(StageSpec.levelCount),
        Element.values.toSet(),
      );
    });

    test('reset clears campaign progress', () async {
      final h = Harness(
        data: SaveData(
          highestStageCleared: 5,
          stageStars: {1: 3},
          bestChain: 9,
        ),
      );
      await h.progress.resetProgress();
      expect(h.progress.data.highestStageCleared, 0);
      expect(h.progress.data.stageStars, isEmpty);
      expect(h.progress.data.bestChain, 0);
    });

    test(
      'schema 1 saves migrate to the current schema with defaults',
      () async {
        final store = InMemoryStore()
          ..values[SaveRepository.primaryKey] = jsonEncode({
            'schemaVersion': 1,
            'coins': 42,
            'bestWave': 7,
          });
        final repo = SaveRepository(store);
        final loaded = await repo.load();
        expect(loaded.data.coins, 42);
        expect(loaded.data.highestStageCleared, 0);
        expect(loaded.data.stageStars, isEmpty);
        await repo.save(loaded.data);
        expect(
          jsonDecode(store.values[SaveRepository.primaryKey]!)['schemaVersion'],
          SaveData.schemaVersion,
        );
      },
    );

    test(
      'schema 2 saves keep all progress when moving to 100 levels',
      () async {
        final v2 = {
          'schemaVersion': 2,
          'coins': 1234,
          'highestStageCleared': 10,
          'stageStars': {'1': 3, '10': 2},
          'upgrades': {'fireRate': 6, 'bulletPower': 5, 'cannonLevel': 3},
          'ownedSkins': ['cobalt', 'ember'],
          'selectedSkin': 'ember',
          'bestChain': 7,
        };
        final store = InMemoryStore()
          ..values[SaveRepository.primaryKey] = jsonEncode(v2);
        final repo = SaveRepository(store);
        final d = (await repo.load()).data;
        expect(d.coins, 1234);
        expect(d.highestStageCleared, 10);
        expect(d.stageStars, {1: 3, 10: 2});
        expect(d.level(UpgradeType.fireRate), 6);
        expect(d.selectedSkin, 'ember');
        // They beat the old stage 10 boss: chapter 1's reward is not paid
        // twice, and level 11 (chapter 2) is open.
        expect(d.chapterRewards, {1});
        expect(d.levelBest, isEmpty);
        final p = PlayerProgress(repo, d);
        expect(p.nextStage, 11);
        final replay = await p.commitRun(
          const RunResult(
            runId: 'old-boss',
            score: 10,
            wave: 2,
            wavesCleared: 2,
            coins: 0,
            ballsDestroyed: 1,
            powerUpsUsed: 0,
            stage: 10,
            stageCleared: true,
            stars: 3,
          ),
        );
        expect(replay.bossReward, 0);
        // Migration is idempotent: a migrated document stays as it is.
        final again = SaveRepository.migrate(
          SaveRepository.migrate(Map<String, Object?>.of(v2)),
        );
        expect(again['chapterRewards'], [1]);
        expect(again['schemaVersion'], SaveData.schemaVersion);
      },
    );

    test('schema 2 saves below level 10 get no chapter reward marked', () {
      final m = SaveRepository.migrate({
        'schemaVersion': 2,
        'highestStageCleared': 4,
      });
      expect(m['chapterRewards'], isNull);
      expect(SaveData.fromJson(m).chapterRewards, isEmpty);
    });

    test(
      'stage stars survive a save round trip and bad values are clamped',
      () {
        final d = SaveData.fromJson({
          'stageStars': {'1': 3, '2': 9, 'x': 2, '-1': 1},
        });
        expect(d.stageStars, {1: 3, 2: 3});
        expect(SaveData.fromJson(d.toJson()).stageStars, {1: 3, 2: 3});
        expect(d.totalStars, 6);
      },
    );
  });

  group('save repository', () {
    test('round trip preserves data', () async {
      final store = InMemoryStore();
      final repo = SaveRepository(store);
      final data = SaveData(coins: 77, bestScore: 1234, tutorialDone: true)
        ..ownedSkins.add('ember')
        ..selectedSkin = 'ember'
        ..upgrades[UpgradeType.coinBonus] = 3
        ..settings.music = false
        ..settings.sfxVolume = 0.25
        ..claimedAchievements.add('wave_10');
      expect(await repo.save(data), isTrue);
      final loaded = await repo.load();
      expect(loaded.source, LoadSource.primary);
      expect(jsonEncode(loaded.data.toJson()), jsonEncode(data.toJson()));
    });

    test('missing save gives safe defaults', () async {
      final loaded = await SaveRepository(InMemoryStore()).load();
      expect(loaded.source, LoadSource.fresh);
      expect(loaded.corruptionDetected, isFalse);
      expect(loaded.data.coins, 0);
      expect(loaded.data.selectedSkin, Catalog.defaultSkinId);
      expect(loaded.data.level(UpgradeType.fireRate), 1);
    });

    test('corrupted primary falls back to the backup', () async {
      final store = InMemoryStore();
      final repo = SaveRepository(store);
      await repo.save(SaveData(coins: 10));
      await repo.save(SaveData(coins: 20)); // backup now holds coins: 10
      store.values[SaveRepository.primaryKey] = '{not json';
      final loaded = await repo.load();
      expect(loaded.source, LoadSource.backup);
      expect(loaded.corruptionDetected, isTrue);
      expect(loaded.data.coins, 10);
    });

    test('both copies corrupted gives a fresh save and reports it', () async {
      final store = InMemoryStore()
        ..values[SaveRepository.primaryKey] = '[]'
        ..values[SaveRepository.backupKey] = 'garbage';
      final loaded = await SaveRepository(store).load();
      expect(loaded.source, LoadSource.fresh);
      expect(loaded.corruptionDetected, isTrue);
    });

    test('malformed values are sanitised', () {
      final data = SaveData.fromJson({
        'schemaVersion': 1,
        'coins': -50,
        'bestScore': 'lots',
        'upgrades': {'fireRate': 999, 'bulletPower': -3, 'unknown': 4},
        'ownedSkins': ['ember', 'hacked_skin', 7],
        'selectedSkin': 'solar',
        'settings': {'musicVolume': 7, 'sfx': 'yes'},
        'daily': {'lastRewardDate': 'yesterday', 'streakDay': 99},
      });
      expect(data.coins, 0);
      expect(data.bestScore, 0);
      expect(data.level(UpgradeType.fireRate), UpgradeSpec.fireRateMax);
      expect(data.level(UpgradeType.bulletPower), 1);
      expect(data.ownedSkins, {'cobalt', 'ember'});
      expect(
        data.selectedSkin,
        Catalog.defaultSkinId,
        reason: 'solar is not owned',
      );
      expect(data.settings.musicVolume, 1.0);
      expect(data.settings.sfx, isTrue);
      expect(data.daily.lastRewardDate, isNull);
      expect(data.daily.streakDay, 7);
    });

    test('migrates schema 0 documents', () async {
      final store = InMemoryStore()
        ..values[SaveRepository.primaryKey] = jsonEncode({
          'coins': 300,
          'music': false,
          'vibration': false,
        });
      final loaded = await SaveRepository(store).load();
      expect(loaded.source, LoadSource.primary);
      expect(loaded.data.coins, 300);
      expect(loaded.data.settings.music, isFalse);
      expect(loaded.data.settings.vibration, isFalse);
      expect(loaded.data.settings.sfx, isTrue);
    });

    test('settings persist through PlayerProgress', () async {
      final h = Harness();
      await h.progress.updateSettings((s) => s.reducedMotion = true);
      expect((await h.reload()).settings.reducedMotion, isTrue);
    });
  });
}
