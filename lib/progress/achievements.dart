import 'save_data.dart';

/// A one-time goal tracked from lifetime stats; the reward can be claimed
/// exactly once.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.target,
    required this.reward,
    required this.progressOf,
  });

  final String id;
  final String title;
  final int target;
  final int reward;
  final int Function(SaveData data) progressOf;

  int progress(SaveData data) => progressOf(data).clamp(0, target);
  bool isComplete(SaveData data) => progressOf(data) >= target;
  bool isClaimed(SaveData data) => data.claimedAchievements.contains(id);
  bool canClaim(SaveData data) => isComplete(data) && !isClaimed(data);
}

abstract final class Achievements {
  static final List<Achievement> all = [
    Achievement(
      id: 'first_upgrade',
      title: 'Buy your first upgrade',
      target: 1,
      reward: 50,
      progressOf: (d) => d.stats.upgradesBought,
    ),
    Achievement(
      id: 'destroy_100',
      title: 'Shatter 100 crystals',
      target: 100,
      reward: 50,
      progressOf: (d) => d.stats.ballsDestroyed,
    ),
    Achievement(
      id: 'destroy_500',
      title: 'Shatter 500 crystals',
      target: 500,
      reward: 100,
      progressOf: (d) => d.stats.ballsDestroyed,
    ),
    Achievement(
      id: 'destroy_5000',
      title: 'Shatter 5,000 crystals',
      target: 5000,
      reward: 500,
      progressOf: (d) => d.stats.ballsDestroyed,
    ),
    Achievement(
      id: 'stage_3',
      title: 'Clear level 3',
      target: 3,
      reward: 75,
      progressOf: (d) => d.highestStageCleared,
    ),
    Achievement(
      id: 'boss_colossus',
      title: 'Defeat the Crystal Colossus',
      target: 10,
      reward: 500,
      progressOf: (d) => d.highestStageCleared,
    ),
    Achievement(
      id: 'chapter_5',
      title: 'Defeat the Void Devourer (level 50)',
      target: 50,
      reward: 1500,
      progressOf: (d) => d.highestStageCleared,
    ),
    Achievement(
      id: 'campaign_100',
      title: 'Defeat the Worldbreaker (level 100)',
      target: 100,
      reward: 5000,
      progressOf: (d) => d.highestStageCleared,
    ),
    Achievement(
      id: 'chain_5',
      title: 'Trigger a 5x chain reaction',
      target: 5,
      reward: 100,
      progressOf: (d) => d.bestChain,
    ),
    Achievement(
      id: 'chain_10',
      title: 'Trigger a 10x chain reaction',
      target: 10,
      reward: 250,
      progressOf: (d) => d.bestChain,
    ),
    Achievement(
      id: 'stars_20',
      title: 'Earn 20 stars',
      target: 20,
      reward: 200,
      progressOf: (d) => d.totalStars,
    ),
    Achievement(
      id: 'wave_10',
      title: 'Reach wave 10 in Endless',
      target: 10,
      reward: 100,
      progressOf: (d) => d.bestWave,
    ),
    Achievement(
      id: 'wave_20',
      title: 'Reach wave 20 in Endless',
      target: 20,
      reward: 200,
      progressOf: (d) => d.bestWave,
    ),
    Achievement(
      id: 'score_10000',
      title: 'Score 10,000 in one run',
      target: 10000,
      reward: 150,
      progressOf: (d) => d.bestScore,
    ),
    Achievement(
      id: 'coins_1000',
      title: 'Collect 1,000 coins',
      target: 1000,
      reward: 200,
      progressOf: (d) => d.stats.coinsEarned,
    ),
    Achievement(
      id: 'powerups_25',
      title: 'Use 25 power-ups',
      target: 25,
      reward: 100,
      progressOf: (d) => d.stats.powerUpsUsed,
    ),
    Achievement(
      id: 'games_25',
      title: 'Play 25 runs',
      target: 25,
      reward: 100,
      progressOf: (d) => d.stats.gamesPlayed,
    ),
  ];

  static Achievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  static int claimableCount(SaveData data) =>
      all.where((a) => a.canClaim(data)).length;
}
