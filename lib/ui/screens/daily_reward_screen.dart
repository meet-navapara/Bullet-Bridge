import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../game/sim/entities.dart';
import '../../progress/daily.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

class DailyRewardScreen extends StatefulWidget {
  const DailyRewardScreen({super.key});

  @override
  State<DailyRewardScreen> createState() => _DailyRewardScreenState();
}

class _DailyRewardScreenState extends State<DailyRewardScreen> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final services = AppScope.of(context);
    final coins = await services.progress.claimDailyReward();
    if (!mounted) return;
    setState(() => _claiming = false);
    if (coins != null) {
      services.audio.play(Sfx.coin);
      services.audio.play(Sfx.upgrade);
      services.haptics.trigger(Haptic.medium);
      showToast(
        context,
        '+${formatInt(coins)} coins!',
        color: const Color(0xFF1E7A3E),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ScreenShell(
      title: 'Daily Reward',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final status = progress.dailyRewardStatus;
          final claimedDay = progress.data.daily.streakDay;
          return ListView(
            padding: const EdgeInsets.all(Gaps.lg),
            children: [
              GamePanel(
                child: Column(
                  children: [
                    Text('Come back every day!', style: TextStyles.heading),
                    const SizedBox(height: 4),
                    Text(
                      'Claim once per day. Missing a day restarts the streak at Day 1.',
                      style: TextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Gaps.lg),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Gaps.sm,
                      runSpacing: Gaps.sm,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          _DayTile(
                            day: day,
                            coins: DailyRewards.coinsForDay(day),
                            state: _tileState(day, status, claimedDay),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gaps.xl),
                    switch (status.availability) {
                      DailyRewardAvailability.available => GameButton(
                        label: 'Claim Day ${status.nextDay}',
                        tone: ButtonTone.green,
                        onPressed: _claiming ? null : _claim,
                      ),
                      DailyRewardAvailability.claimedToday => Text(
                        'Claimed today. Come back tomorrow!',
                        style: TextStyles.body.copyWith(color: Palette.green),
                        textAlign: TextAlign.center,
                      ),
                      DailyRewardAvailability.clockRolledBack => Text(
                        'Your device clock looks earlier than your last claim. '
                        'The reward unlocks once the date catches up.',
                        style: TextStyles.body.copyWith(color: Palette.coral),
                        textAlign: TextAlign.center,
                      ),
                    },
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  _TileState _tileState(int day, DailyRewardStatus status, int claimedDay) {
    if (status.availability == DailyRewardAvailability.available) {
      if (day < status.nextDay) return _TileState.claimed;
      if (day == status.nextDay) return _TileState.ready;
      return _TileState.locked;
    }
    return day <= claimedDay ? _TileState.claimed : _TileState.locked;
  }
}

enum _TileState { claimed, ready, locked }

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.coins, required this.state});
  final int day;
  final int coins;
  final _TileState state;

  @override
  Widget build(BuildContext context) {
    final ready = state == _TileState.ready;
    final Widget icon = switch (day) {
      4 => const Icon(
        Icons.inventory_2_rounded,
        color: Palette.orange,
        size: 34,
      ),
      5 => const PowerUpIcon(type: PowerUpType.powerShot, size: 36),
      _ => const CoinIcon(size: 32),
    };
    return Semantics(
      label:
          'Day $day, $coins coins${day == 5 ? ' plus power-ups' : ''}, ${state.name}',
      child: Container(
        width: 78,
        height: 108,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: ready ? const Color(0xFF3A3410) : Palette.panelInset,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: ready ? Palette.yellow : Palette.panelBorder,
            width: ready ? 2.5 : 1.5,
          ),
          boxShadow: ready
              ? [
                  BoxShadow(
                    color: Palette.yellow.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              'Day $day',
              style: TextStyles.caption.copyWith(color: Colors.white),
            ),
            Expanded(
              child: Center(
                child: Opacity(
                  opacity: state == _TileState.claimed ? 0.45 : 1,
                  child: icon,
                ),
              ),
            ),
            if (state == _TileState.claimed)
              const Icon(
                Icons.check_circle_rounded,
                color: Palette.green,
                size: 20,
              )
            else if (state == _TileState.locked)
              Text(
                formatInt(coins),
                style: TextStyles.number.copyWith(
                  fontSize: 15,
                  color: Palette.textMuted,
                ),
              )
            else
              Text(
                formatInt(coins),
                style: TextStyles.number.copyWith(
                  fontSize: 16,
                  color: Palette.yellow,
                ),
              ),
            if (day == 5)
              Text(
                '+ power-ups',
                style: TextStyles.caption.copyWith(fontSize: 8.5),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
