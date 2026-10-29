import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../progress/achievements.dart';
import '../../progress/save_data.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  final Set<String> _claiming = {};

  Future<void> _claim(Achievement a) async {
    if (_claiming.contains(a.id)) return;
    setState(() => _claiming.add(a.id));
    final services = AppScope.of(context);
    final reward = await services.progress.claimAchievement(a.id);
    if (!mounted) return;
    setState(() => _claiming.remove(a.id));
    if (reward != null) {
      services.audio.play(Sfx.coin);
      services.haptics.trigger(Haptic.medium);
      showToast(context, '+$reward coins!', color: const Color(0xFF1E7A3E));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ScreenShell(
      title: 'Missions',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final data = progress.data;
          // Claimable first, then in progress, then finished.
          final list = [...Achievements.all]
            ..sort((a, b) => _rank(a, data).compareTo(_rank(b, data)));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Gaps.lg,
              Gaps.sm,
              Gaps.lg,
              Gaps.xl,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gaps.md),
            itemBuilder: (context, i) {
              final a = list[i];
              final progressValue = a.progress(data);
              final claimed = a.isClaimed(data);
              final canClaim = a.canClaim(data);
              return GamePanel(
                padding: const EdgeInsets.all(Gaps.md),
                highlight: canClaim ? Palette.yellow : null,
                child: Row(
                  children: [
                    Icon(
                      claimed
                          ? Icons.verified_rounded
                          : Icons.emoji_events_rounded,
                      color: claimed ? Palette.green : Palette.yellow,
                      size: 36,
                    ),
                    const SizedBox(width: Gaps.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: TextStyles.body),
                          const SizedBox(height: 6),
                          ProgressBar(value: progressValue / a.target),
                          const SizedBox(height: 3),
                          Text(
                            '${formatInt(progressValue)} / ${formatInt(a.target)}',
                            style: TextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gaps.md),
                    SizedBox(
                      width: 86,
                      child: claimed
                          ? Text(
                              'Done',
                              textAlign: TextAlign.center,
                              style: TextStyles.number.copyWith(
                                color: Palette.green,
                              ),
                            )
                          : canClaim
                          ? GameButton(
                              label: '${a.reward}',
                              tone: ButtonTone.yellow,
                              height: 42,
                              fontSize: 17,
                              icon: const CoinIcon(size: 18),
                              onPressed: _claiming.contains(a.id)
                                  ? null
                                  : () => _claim(a),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CoinIcon(size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  '${a.reward}',
                                  style: TextStyles.number.copyWith(
                                    fontSize: 17,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static int _rank(Achievement a, SaveData data) {
    if (a.canClaim(data)) return 0;
    if (!a.isClaimed(data)) return 1;
    return 2;
  }
}
