import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/balance.dart';
import '../../progress/daily.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';
import 'game_screen.dart';

class DailyChallengeScreen extends StatelessWidget {
  const DailyChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ScreenShell(
      title: 'Daily Challenge',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final challenge = progress.todaysChallenge;
          final best = challenge.bestToday(progress.data.daily);
          final claimed = challenge.rewardClaimed(progress.data.daily);
          return ListView(
            padding: const EdgeInsets.all(Gaps.lg),
            children: [
              GamePanel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF3A2410),
                          ),
                          child: const Icon(
                            Icons.track_changes_rounded,
                            color: Palette.orange,
                            size: 44,
                          ),
                        ),
                        const SizedBox(width: Gaps.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Today's Challenge",
                                style: TextStyles.caption,
                              ),
                              Text(challenge.title, style: TextStyles.heading),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Reward: ',
                                    style: TextStyles.caption.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const CoinIcon(size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${DailySpec.challengeReward}',
                                    style: TextStyles.number.copyWith(
                                      fontSize: 16,
                                      color: Palette.yellow,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gaps.lg),
                    ProgressBar(
                      value: best / challenge.target,
                      color: claimed ? Palette.green : Palette.cyan,
                      height: 14,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      claimed
                          ? 'Completed! Reward collected.'
                          : 'Best today: ${formatInt(best)} / ${formatInt(challenge.target)}',
                      style: TextStyles.body.copyWith(
                        color: claimed ? Palette.green : Palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.lg),
              GamePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rules',
                      style: TextStyles.heading.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: Gaps.sm),
                    _rule('Everyone gets the same waves today.'),
                    _rule(
                      'You use a fixed cannon loadout, so upgrades do not matter.',
                    ),
                    _rule(
                      'Retry as often as you like; the reward is paid once per day.',
                    ),
                    _rule('Coins you collect in the run are always kept.'),
                    _rule('A new challenge starts at local midnight.'),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.xl),
              GameButton(
                label: claimed ? 'Play Again' : 'Play Challenge',
                tone: ButtonTone.blue,
                onPressed: () => Navigator.of(context).push(
                  gameRoute<void>(
                    GameScreen(
                      challenge: DailyChallenge.forDate(progress.now()),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rule(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3, right: 8),
          child: Icon(Icons.star_rounded, size: 14, color: Palette.yellow),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyles.caption.copyWith(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
