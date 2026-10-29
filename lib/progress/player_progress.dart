import 'package:flutter/foundation.dart';

import '../config/balance.dart';
import '../config/campaign.dart';
import '../economy/catalog.dart';
import '../economy/upgrades.dart';
import '../game/sim/entities.dart';
import 'achievements.dart';
import 'daily.dart';
import 'save_data.dart';
import 'save_merge.dart';
import 'save_repository.dart';

/// Final numbers of one run, committed to the save exactly once.
class RunResult {
  const RunResult({
    required this.runId,
    required this.score,
    required this.wave,
    required this.wavesCleared,
    required this.coins,
    required this.ballsDestroyed,
    required this.powerUpsUsed,
    this.challengeDate,
    this.stage,
    this.stageCleared = false,
    this.stars = 0,
    this.bestChain = 0,
  });

  final String runId;
  final int score;
  final int wave;
  final int wavesCleared;
  final int coins;
  final int ballsDestroyed;
  final int powerUpsUsed;

  /// Set when the run was the daily challenge for that date.
  final String? challengeDate;

  /// Campaign stage played, or null for endless/daily runs.
  final int? stage;
  final bool stageCleared;
  final int stars;
  final int bestChain;
}

class CommitOutcome {
  const CommitOutcome({
    required this.accepted,
    this.newBestScore = false,
    this.challengeReward = 0,
    this.stageBonus = 0,
    this.firstClear = false,
    this.unlocked,
    this.saveFailed = false,
    this.bossReward = 0,
    this.rewardSkin,
    this.chapterCompleted,
    this.newLevelBest = false,
  });

  final bool accepted;

  /// Coins for beating a chapter boss for the first time (0 otherwise).
  final int bossReward;

  /// Reward-only skin granted with [bossReward], if any.
  final String? rewardSkin;

  /// Chapter completed by this first boss win, if any.
  final int? chapterCompleted;
  final bool newLevelBest;

  /// The run was valid but could not be written; committing it again later
  /// may succeed. (A duplicate run is not accepted and not a failure.)
  final bool saveFailed;
  final bool newBestScore;
  final int challengeReward;

  /// Coins for clearing a stage: double on the first clear, a small replay
  /// bonus afterwards, scaled by stars.
  final int stageBonus;
  final bool firstClear;

  /// Element unlocked by this clear, if any.
  final Element? unlocked;
}

enum PurchaseResult {
  success,
  insufficientFunds,
  maxed,
  stale,
  saveFailed,
  invalid,
}

/// Owns the in-memory save and applies every change as a transaction:
/// mutate a copy, persist it, and only then publish it. If persisting fails
/// the previous state is kept, so a failed write never grants or loses
/// coins. Transactions run one at a time.
class PlayerProgress extends ChangeNotifier {
  PlayerProgress(
    this._repository,
    SaveData initial, {
    DateTime Function()? clock,
  }) : _data = initial,
       _clock = clock ?? DateTime.now;

  final SaveRepository _repository;
  final DateTime Function() _clock;
  SaveData _data;
  Future<void> _queue = Future.value();

  SaveData get data => _data;
  DateTime now() => _clock();

  /// Merges a save from another device (cloud sync) into this one with
  /// [SaveMerge.merge], persists the result and publishes it. Queued like
  /// every other change, so it never interleaves with a purchase or a run
  /// commit. Returns false if the merged save could not be written.
  Future<bool> mergeFrom(SaveData other) {
    final completer = _queue.then((_) async {
      final merged = SaveMerge.merge(_data, other);
      final ok = await _repository.save(merged);
      if (!ok) return false;
      _data = merged;
      notifyListeners();
      return true;
    });
    _queue = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  Future<T> _transact<T>(
    T Function(SaveData draft) mutate, {
    required T onSaveFailed,
    bool Function(T result)? shouldPersist,
  }) {
    final completer = _queue.then((_) async {
      final draft = _data.copy();
      final result = mutate(draft);
      if (shouldPersist != null && !shouldPersist(result)) return result;
      draft.updatedAtMs = _clock().millisecondsSinceEpoch;
      final ok = await _repository.save(draft);
      if (!ok) return onSaveFailed;
      _data = draft;
      notifyListeners();
      return result;
    });
    _queue = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  // ---------------------------------------------------------------- Economy

  /// [fromLevel] is the level the UI showed; a second tap that arrives after
  /// the first purchase is rejected as stale instead of buying twice.
  Future<PurchaseResult> purchaseUpgrade(UpgradeType type, int fromLevel) {
    final def = Upgrades.byType(type);
    return _transact(
      (d) {
        final level = d.level(type);
        if (level != fromLevel) return PurchaseResult.stale;
        final cost = def.costToUpgrade(level);
        if (cost == null) return PurchaseResult.maxed;
        if (d.coins < cost) return PurchaseResult.insufficientFunds;
        d.coins -= cost;
        d.upgrades[type] = level + 1;
        d.stats.upgradesBought++;
        return PurchaseResult.success;
      },
      onSaveFailed: PurchaseResult.saveFailed,
      shouldPersist: _isSuccess,
    );
  }

  Future<PurchaseResult> buySkin(String id) => _buyCosmetic(
    id: id,
    // Boss-reward skins are earned, never sold.
    exists: Catalog.isSkin(id) && !Catalog.skin(id).rewardOnly,
    price: Catalog.skin(id).price,
    owned: (d) => d.ownedSkins,
    select: (d) => d.selectedSkin = id,
  );

  Future<PurchaseResult> buyTheme(String id) => _buyCosmetic(
    id: id,
    exists: Catalog.isTheme(id),
    price: Catalog.theme(id).price,
    owned: (d) => d.ownedThemes,
    select: (d) => d.selectedTheme = id,
  );

  Future<PurchaseResult> _buyCosmetic({
    required String id,
    required bool exists,
    required int price,
    required Set<String> Function(SaveData) owned,
    required void Function(SaveData) select,
  }) {
    return _transact(
      (d) {
        if (!exists) return PurchaseResult.invalid;
        if (owned(d).contains(id)) return PurchaseResult.stale;
        if (d.coins < price) return PurchaseResult.insufficientFunds;
        d.coins -= price;
        owned(d).add(id);
        select(d);
        return PurchaseResult.success;
      },
      onSaveFailed: PurchaseResult.saveFailed,
      shouldPersist: _isSuccess,
    );
  }

  Future<bool> selectSkin(String id) => _transact(
    (d) {
      if (!d.ownedSkins.contains(id)) return false;
      d.selectedSkin = id;
      return true;
    },
    onSaveFailed: false,
    shouldPersist: (ok) => ok,
  );

  Future<bool> selectTheme(String id) => _transact(
    (d) {
      if (!d.ownedThemes.contains(id)) return false;
      d.selectedTheme = id;
      return true;
    },
    onSaveFailed: false,
    shouldPersist: (ok) => ok,
  );

  static bool _isSuccess(PurchaseResult r) => r == PurchaseResult.success;

  // ------------------------------------------------------------------- Runs

  Loadout get loadout => Upgrades.loadoutFor(
    _data.upgrades,
    elements: Upgrades.elementsUnlocked(_data.highestStageCleared),
  );

  /// Removes and returns the daily-reward power-ups for the run starting
  /// now. They are consumed even if the run is abandoned, by design.
  Future<Map<PowerUpType, int>> takeBonusPowerUps() => _transact(
    (d) {
      final n = d.daily.bonusPowerUpsPending;
      d.daily.bonusPowerUpsPending = 0;
      return n == 0
          ? const <PowerUpType, int>{}
          : {for (final t in PowerUpType.values) t: n};
    },
    onSaveFailed: const {},
    shouldPersist: (m) => m.isNotEmpty,
  );

  Future<CommitOutcome> commitRun(RunResult r) => _transact((d) {
    if (d.committedRuns.contains(r.runId)) {
      return const CommitOutcome(accepted: false);
    }
    d.committedRuns.add(r.runId);
    while (d.committedRuns.length > SaveData.committedRunHistory) {
      d.committedRuns.remove(d.committedRuns.first);
    }
    final newBest = r.score > d.bestScore;
    d.coins += r.coins;
    if (newBest) d.bestScore = r.score;
    // Waves inside a campaign stage are not comparable with endless waves.
    if (r.stage == null && r.wave > d.bestWave) d.bestWave = r.wave;
    if (r.bestChain > d.bestChain) d.bestChain = r.bestChain;

    var stageBonus = 0;
    var firstClear = false;
    var bossReward = 0;
    var newLevelBest = false;
    String? rewardSkin;
    int? chapterCompleted;
    Element? unlocked;
    final stage = r.stage;
    if (stage != null && stage >= 1 && stage <= StageSpec.levelCount) {
      if (r.score > (d.levelBest[stage] ?? 0)) {
        d.levelBest[stage] = r.score;
        newLevelBest = true;
      }
    }
    if (stage != null &&
        r.stageCleared &&
        stage >= 1 &&
        stage <= StageSpec.levelCount &&
        stage <= d.highestStageCleared + 1) {
      final level = Campaign.level(stage);
      // Only the next locked level advances progress; replays never do.
      firstClear = stage == d.highestStageCleared + 1;
      final before = Upgrades.elementsUnlocked(d.highestStageCleared);
      if (firstClear) d.highestStageCleared = stage;
      final after = Upgrades.elementsUnlocked(d.highestStageCleared);
      unlocked = after.difference(before).firstOrNull;
      final stars = r.stars.clamp(1, 3);
      if (stars > (d.stageStars[stage] ?? 0)) d.stageStars[stage] = stars;
      // Better runs pay more: 1 star x0.85, 2 stars x1.0, 3 stars x1.15.
      final performance = 0.7 + 0.15 * stars;
      final share = firstClear ? 2.0 : StageSpec.replayBonusFraction;
      stageBonus = (level.clearBonus * share * performance).round();
      d.coins += stageBonus;
      final boss = level.boss;
      if (boss != null && !d.chapterRewards.contains(level.chapter)) {
        d.chapterRewards.add(level.chapter);
        chapterCompleted = level.chapter;
        bossReward = boss.reward.coins;
        d.coins += bossReward;
        final skin = boss.reward.skinId;
        if (skin != null && Catalog.isSkin(skin)) {
          d.ownedSkins.add(skin);
          rewardSkin = skin;
        }
      }
    }
    d.stats
      ..gamesPlayed += 1
      ..ballsDestroyed += r.ballsDestroyed
      ..coinsEarned += r.coins
      ..powerUpsUsed += r.powerUpsUsed
      ..wavesCleared += r.wavesCleared;
    d.gamesSinceInterstitial++;

    var challengeReward = 0;
    final date = r.challengeDate;
    if (date != null) {
      final challenge = DailyChallenge.forDate(_parseDate(date));
      final progress = challenge.progressFrom(
        wave: r.wave,
        ballsDestroyed: r.ballsDestroyed,
        score: r.score,
      );
      if (d.daily.challengeDate != date) {
        d.daily
          ..challengeDate = date
          ..challengeBest = 0;
      }
      if (progress > d.daily.challengeBest) d.daily.challengeBest = progress;
      if (progress >= challenge.target &&
          d.daily.challengeClaimedDate != date) {
        d.daily.challengeClaimedDate = date;
        challengeReward = DailySpec.challengeReward;
        d.coins += challengeReward;
      }
    }
    return CommitOutcome(
      accepted: true,
      newBestScore: newBest,
      challengeReward: challengeReward,
      stageBonus: stageBonus,
      firstClear: firstClear,
      unlocked: unlocked,
      bossReward: bossReward,
      rewardSkin: rewardSkin,
      chapterCompleted: chapterCompleted,
      newLevelBest: newLevelBest,
    );
  }, onSaveFailed: const CommitOutcome(accepted: false, saveFailed: true));

  /// Next stage to play: the first uncleared one (capped at the last stage).
  int get nextStage =>
      (_data.highestStageCleared + 1).clamp(1, StageSpec.levelCount);

  bool get campaignComplete =>
      _data.highestStageCleared >= StageSpec.levelCount;

  bool isStageUnlocked(int stage) =>
      stage >= 1 && stage <= _data.highestStageCleared + 1;

  Set<Element> get unlockedElements =>
      Upgrades.elementsUnlocked(_data.highestStageCleared);

  static DateTime _parseDate(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  // ------------------------------------------------------------ Daily/Goals

  DailyRewardStatus get dailyRewardStatus =>
      DailyRewards.status(_data.daily, now());

  DailyChallenge get todaysChallenge => DailyChallenge.forDate(now());

  /// Returns coins granted, or null if not claimable.
  Future<int?> claimDailyReward() {
    final at = now();
    return _transact(
      (d) => DailyRewards.claim(d, at),
      onSaveFailed: null,
      shouldPersist: (c) => c != null,
    );
  }

  Future<int?> claimAchievement(String id) => _transact(
    (d) {
      final a = Achievements.byId(id);
      if (a == null || !a.canClaim(d)) return null;
      d.claimedAchievements.add(id);
      d.coins += a.reward;
      return a.reward;
    },
    onSaveFailed: null,
    shouldPersist: (c) => c != null,
  );

  bool get canWatchAdForCoins {
    final today = dateKey(now());
    return _data.daily.adCoinsDate != today ||
        _data.daily.adCoinsCount < AdSpec.rewardedCoinsPerDay;
  }

  /// Called only from the rewarded-ad "earned reward" callback.
  Future<int?> grantAdCoins() {
    final today = dateKey(now());
    return _transact(
      (d) {
        if (d.daily.adCoinsDate != today) {
          d.daily
            ..adCoinsDate = today
            ..adCoinsCount = 0;
        }
        if (d.daily.adCoinsCount >= AdSpec.rewardedCoinsPerDay) return null;
        d.daily.adCoinsCount++;
        d.coins += AdSpec.rewardedCoins;
        return AdSpec.rewardedCoins;
      },
      onSaveFailed: null,
      shouldPersist: (c) => c != null,
    );
  }

  Future<void> markInterstitialShown() => _transact((d) {
    d.gamesSinceInterstitial = 0;
  }, onSaveFailed: null);

  // --------------------------------------------------------------- Settings

  Future<bool> updateSettings(void Function(GameSettings s) change) =>
      _transact((d) {
        change(d.settings);
        return true;
      }, onSaveFailed: false);

  Future<bool> setTutorialDone(bool done) => _transact((d) {
    d.tutorialDone = done;
    return true;
  }, onSaveFailed: false);

  /// Wipes progress but keeps settings and the tutorial flag.
  Future<bool> resetProgress() => _transact((d) {
    final fresh = SaveData(settings: d.settings, tutorialDone: d.tutorialDone);
    d
      ..coins = fresh.coins
      ..bestScore = 0
      ..bestWave = 0
      ..selectedSkin = fresh.selectedSkin
      ..selectedTheme = fresh.selectedTheme
      ..gamesSinceInterstitial = 0
      ..highestStageCleared = 0
      ..bestChain = 0;
    d.stageStars.clear();
    d.levelBest.clear();
    d.chapterRewards.clear();
    d.upgrades
      ..clear()
      ..addAll(fresh.upgrades);
    d.ownedSkins
      ..clear()
      ..addAll(fresh.ownedSkins);
    d.ownedThemes
      ..clear()
      ..addAll(fresh.ownedThemes);
    d.claimedAchievements.clear();
    d.committedRuns.clear();
    final s = d.stats;
    s
      ..ballsDestroyed = 0
      ..coinsEarned = 0
      ..gamesPlayed = 0
      ..upgradesBought = 0
      ..powerUpsUsed = 0
      ..wavesCleared = 0;
    // The last claim date is kept so a reset cannot re-open today's
    // reward; only the streak restarts.
    d.daily
      ..streakDay = 0
      ..bonusPowerUpsPending = 0
      ..challengeDate = null
      ..challengeBest = 0
      ..challengeClaimedDate = null;
    // Ad-coin limits intentionally survive a reset.
    return true;
  }, onSaveFailed: false);
}
