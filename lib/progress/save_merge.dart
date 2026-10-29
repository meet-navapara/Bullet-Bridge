import 'dart:math' as math;

import '../economy/catalog.dart';
import '../economy/upgrades.dart';
import 'save_data.dart';

/// Combines two saves of the same player (this device and the cloud).
///
/// Earned progress is never lost: levels, stars, bests, upgrades, unlocks
/// and claimed rewards are merged by maximum or union. Values that go up
/// and down (coins, daily streak, selected cosmetics) cannot be merged
/// safely, so they come from the save that changed most recently. Taking
/// coins from one side only means coins can never be duplicated by playing
/// on two devices. Settings always stay as they are on this device.
abstract final class SaveMerge {
  static SaveData merge(SaveData local, SaveData remote) {
    final newer = remote.updatedAtMs > local.updatedAtMs ? remote : local;

    final upgrades = {
      for (final def in Upgrades.all)
        def.type: math.max(local.level(def.type), remote.level(def.type)),
    };
    final ownedSkins = {...local.ownedSkins, ...remote.ownedSkins};
    final ownedThemes = {...local.ownedThemes, ...remote.ownedThemes};

    Map<int, int> maxMap(Map<int, int> a, Map<int, int> b) => {
      for (final k in {...a.keys, ...b.keys}) k: math.max(a[k] ?? 0, b[k] ?? 0),
    };

    // Keep the most recent run ids of both sides so a run cannot be
    // committed twice after a merge.
    final runs = [...newer.committedRuns];
    for (final id in (identical(newer, local) ? remote : local).committedRuns) {
      if (!runs.contains(id)) runs.add(id);
    }
    final keptRuns = runs.length > SaveData.committedRunHistory
        ? runs.sublist(runs.length - SaveData.committedRunHistory)
        : runs;

    final merged = SaveData(
      coins: newer.coins,
      bestScore: math.max(local.bestScore, remote.bestScore),
      bestWave: math.max(local.bestWave, remote.bestWave),
      upgrades: upgrades,
      ownedSkins: ownedSkins,
      selectedSkin: ownedSkins.contains(newer.selectedSkin)
          ? newer.selectedSkin
          : Catalog.defaultSkinId,
      ownedThemes: ownedThemes,
      selectedTheme: ownedThemes.contains(newer.selectedTheme)
          ? newer.selectedTheme
          : Catalog.defaultThemeId,
      settings: GameSettings.fromJson(local.settings.toJson()),
      tutorialDone: local.tutorialDone || remote.tutorialDone,
      stats: LifetimeStats(
        ballsDestroyed: math.max(
          local.stats.ballsDestroyed,
          remote.stats.ballsDestroyed,
        ),
        coinsEarned: math.max(
          local.stats.coinsEarned,
          remote.stats.coinsEarned,
        ),
        gamesPlayed: math.max(
          local.stats.gamesPlayed,
          remote.stats.gamesPlayed,
        ),
        upgradesBought: math.max(
          local.stats.upgradesBought,
          remote.stats.upgradesBought,
        ),
        powerUpsUsed: math.max(
          local.stats.powerUpsUsed,
          remote.stats.powerUpsUsed,
        ),
        wavesCleared: math.max(
          local.stats.wavesCleared,
          remote.stats.wavesCleared,
        ),
      ),
      claimedAchievements: {
        ...local.claimedAchievements,
        ...remote.claimedAchievements,
      },
      daily: DailyState.fromJson(newer.daily.toJson()),
      committedRuns: keptRuns.toSet(),
      gamesSinceInterstitial: newer.gamesSinceInterstitial,
      highestStageCleared: math.max(
        local.highestStageCleared,
        remote.highestStageCleared,
      ),
      stageStars: maxMap(local.stageStars, remote.stageStars),
      bestChain: math.max(local.bestChain, remote.bestChain),
      levelBest: maxMap(local.levelBest, remote.levelBest),
      chapterRewards: {...local.chapterRewards, ...remote.chapterRewards},
      updatedAtMs: math.max(local.updatedAtMs, remote.updatedAtMs),
    );
    // Round-trip through JSON so the result passes the same validation as a
    // loaded save (clamping, unknown ids).
    return SaveData.fromJson(merged.toJson());
  }
}
