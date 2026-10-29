import '../config/balance.dart';
import '../game/sim/seeded_random.dart';
import 'save_data.dart';

/// Local calendar day key, e.g. `2026-10-27`.
String dateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

String previousDateKey(DateTime local) =>
    dateKey(DateTime(local.year, local.month, local.day - 1));

enum DailyRewardAvailability { available, claimedToday, clockRolledBack }

class DailyRewardStatus {
  const DailyRewardStatus(this.availability, this.nextDay);

  final DailyRewardAvailability availability;

  /// Streak day (1..7) that the next claim grants.
  final int nextDay;

  bool get canClaim => availability == DailyRewardAvailability.available;
  int get coins => DailySpec.rewardCoins[nextDay - 1];
}

abstract final class DailyRewards {
  static int coinsForDay(int day) => DailySpec.rewardCoins[day - 1];

  static DailyRewardStatus status(DailyState state, DateTime now) {
    final today = dateKey(now);
    final last = state.lastRewardDate;
    if (last == today) {
      return DailyRewardStatus(
        DailyRewardAvailability.claimedToday,
        state.streakDay.clamp(1, 7),
      );
    }
    // If the device clock moved backwards past the last claim, refuse until
    // real time catches up, so changing the date cannot farm rewards.
    if (last != null &&
        (today.compareTo(last) < 0 ||
            now.millisecondsSinceEpoch < state.lastRewardEpochMs)) {
      return DailyRewardStatus(
        DailyRewardAvailability.clockRolledBack,
        state.streakDay.clamp(1, 7),
      );
    }
    final continues = last != null && last == previousDateKey(now);
    final next = continues ? state.streakDay % 7 + 1 : 1;
    return DailyRewardStatus(DailyRewardAvailability.available, next);
  }

  /// Applies a claim to [data]. Returns coins granted, or null if the claim
  /// is not allowed.
  static int? claim(SaveData data, DateTime now) {
    final s = status(data.daily, now);
    if (!s.canClaim) return null;
    final coins = s.coins;
    data.coins += coins;
    data.daily
      ..lastRewardDate = dateKey(now)
      ..lastRewardEpochMs = now.millisecondsSinceEpoch
      ..streakDay = s.nextDay;
    if (s.nextDay == 5) {
      data.daily.bonusPowerUpsPending += DailySpec.day5BonusPowerUps;
    }
    return coins;
  }
}

enum ChallengeGoalType { reachWave, destroyBalls, score }

/// Today's challenge: a seeded run with a fixed loadout and a single goal.
class DailyChallenge {
  const DailyChallenge({
    required this.date,
    required this.seed,
    required this.goal,
    required this.target,
  });

  final String date;
  final int seed;
  final ChallengeGoalType goal;
  final int target;

  factory DailyChallenge.forDate(DateTime local) {
    final date = dateKey(local);
    final seed = SeededRandom.hashString('orbit-blast-daily-$date');
    final rng = SeededRandom(seed);
    final goal = ChallengeGoalType.values[rng.nextInt(3)];
    final target = switch (goal) {
      ChallengeGoalType.reachWave => 6 + rng.nextInt(4),
      ChallengeGoalType.destroyBalls => 60 + rng.nextInt(9) * 10,
      ChallengeGoalType.score => 2000 + rng.nextInt(7) * 500,
    };
    return DailyChallenge(date: date, seed: seed, goal: goal, target: target);
  }

  String get title => switch (goal) {
    ChallengeGoalType.reachWave => 'Reach wave $target',
    ChallengeGoalType.destroyBalls => 'Shatter $target crystals',
    ChallengeGoalType.score => 'Score $target points',
  };

  int progressFrom({
    required int wave,
    required int ballsDestroyed,
    required int score,
  }) => switch (goal) {
    ChallengeGoalType.reachWave => wave,
    ChallengeGoalType.destroyBalls => ballsDestroyed,
    ChallengeGoalType.score => score,
  };

  int bestToday(DailyState state) =>
      state.challengeDate == date ? state.challengeBest : 0;

  bool rewardClaimed(DailyState state) => state.challengeClaimedDate == date;
}
