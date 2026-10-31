import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../economy/catalog.dart';
import '../../economy/upgrades.dart';
import '../../progress/achievements.dart';
import '../../render/menu_icon_art.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';
import 'daily_challenge_screen.dart';
import 'daily_reward_screen.dart';
import 'game_screen.dart';
import 'missions_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'tutorial_screen.dart';
import 'upgrades_screen.dart';
import 'world_map_screen.dart';

/// The title scene: the illustrated world with the player's cannon parked
/// on the grass, the logo in the sky and the main actions around it.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  bool _shownStorageWarning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    services.audio.startMusic();
    if (services.storageWarning && !_shownStorageWarning) {
      _shownStorageWarning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showToast(
            context,
            'Storage unavailable: progress will not be saved this session.',
            color: Palette.coral,
          );
        }
      });
    }
  }

  void _open(Widget page) => Navigator.of(context).push(gameRoute<void>(page));

  void _play() {
    final progress = AppScope.of(context).progress;
    final stage = progress.nextStage;
    if (!progress.data.tutorialDone) {
      _open(
        TutorialScreen(
          onFinished: (ctx) =>
              Navigator.of(ctx)
                  .pushReplacement(gameRoute<void>(GameScreen(stage: stage))),
        ),
      );
    } else {
      _open(GameScreen(stage: stage));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return Scaffold(
      body: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final data = progress.data;
          final skin = Catalog.skin(data.selectedSkin);
          final dailyReady = progress.dailyRewardStatus.canClaim;
          final challengeOpen = !progress.todaysChallenge.rewardClaimed(
            data.daily,
          );
          final claimable = Achievements.claimableCount(data);
          final worldDone = progress.campaignComplete;
          final stage = progress.nextStage;
          return WorldBackground(
            theme: Catalog.theme(data.selectedTheme),
            groundFraction: _groundFraction,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  final w = constraints.maxWidth;
                  final pad = MediaQuery.paddingOf(context);
                  final compact = h < 640;
                  // Grass line in this SafeArea's coordinates (the world is
                  // painted behind the whole screen, including insets).
                  final groundTop =
                      (h + pad.top + pad.bottom) * (1 - _groundFraction) -
                      pad.top;
                  final cannonSize = (h * 0.26).clamp(100.0, w * 0.5);
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gaps.lg,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: Gaps.sm),
                            Row(
                              children: [
                                RoundIconButton(
                                  icon: Icons.settings_rounded,
                                  tooltip: 'Settings',
                                  onPressed: () =>
                                      _open(const SettingsScreen()),
                                ),
                                const Spacer(),
                                CoinBadge(
                                  onAdd: () => _open(const ShopScreen()),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? Gaps.sm : Gaps.xl),
                            GameLogo(size: compact ? 52 : 70),
                          ],
                        ),
                      ),
                      // The cannon, parked on the grass line.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: groundTop - cannonSize * 0.97,
                        child: Center(
                          child: CannonPreview(
                            skin: skin,
                            level: data.level(UpgradeType.cannonLevel),
                            size: cannonSize,
                          ),
                        ),
                      ),
                      // Side button columns flanking the cannon.
                      for (final left in const [true, false])
                        Positioned(
                          left: left ? Gaps.lg : null,
                          right: left ? null : Gaps.lg,
                          bottom: h - groundTop + Gaps.xs,
                          child: Column(
                            children: left
                                ? [
                                    _SideButton(
                                      icon: MenuIcon.upgrade,
                                      label: 'Upgrade',
                                      tone: ButtonTone.green,
                                      compact: compact,
                                      onTap: () =>
                                          _open(const UpgradesScreen()),
                                    ),
                                    const SizedBox(height: Gaps.sm),
                                    _SideButton(
                                      icon: MenuIcon.shop,
                                      label: 'Shop',
                                      tone: ButtonTone.blue,
                                      compact: compact,
                                      onTap: () => _open(const ShopScreen()),
                                    ),
                                  ]
                                : [
                                    _SideButton(
                                      icon: MenuIcon.daily,
                                      label: 'Daily',
                                      tone: ButtonTone.red,
                                      compact: compact,
                                      badge: dailyReady ? 0 : null,
                                      onTap: () =>
                                          _open(const DailyRewardScreen()),
                                    ),
                                    const SizedBox(height: Gaps.sm),
                                    _SideButton(
                                      icon: MenuIcon.goals,
                                      label: 'Goals',
                                      tone: ButtonTone.purple,
                                      compact: compact,
                                      badge: claimable > 0 ? claimable : null,
                                      onTap: () =>
                                          _open(const MissionsScreen()),
                                    ),
                                  ],
                          ),
                        ),
                      // LEVEL + PLAY on the ground, mode tiles below.
                      Positioned(
                        left: Gaps.lg,
                        right: Gaps.lg,
                        top: groundTop + (compact ? 2 : Gaps.sm),
                        bottom: Gaps.sm,
                        child: Column(
                          children: [
                            Text(
                              worldDone ? 'CAMPAIGN CLEARED' : 'LEVEL $stage',
                              style: TextStyles.title.copyWith(
                                fontSize: compact ? 22 : 28,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 240,
                              child: GameButton(
                                label: worldDone ? 'Replay Boss' : 'Play',
                                height: compact ? 50 : 62,
                                onPressed: _play,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: _GroundTile(
                                    icon: Icons.map_rounded,
                                    label: 'Levels',
                                    onTap: () => _open(const WorldMapScreen()),
                                  ),
                                ),
                                const SizedBox(width: Gaps.sm),
                                Expanded(
                                  child: _GroundTile(
                                    icon: Icons.all_inclusive_rounded,
                                    label: 'Endless',
                                    onTap: () => _open(const GameScreen()),
                                  ),
                                ),
                                const SizedBox(width: Gaps.sm),
                                Expanded(
                                  child: _GroundTile(
                                    icon: Icons.track_changes_rounded,
                                    label: 'Challenge',
                                    badge: challengeOpen,
                                    onTap: () =>
                                        _open(const DailyChallengeScreen()),
                                  ),
                                ),
                                const SizedBox(width: Gaps.sm),
                                Expanded(
                                  child: _GroundTile(
                                    icon: Icons.help_rounded,
                                    label: 'How to',
                                    onTap: () => _open(
                                      TutorialScreen(
                                        onFinished: (ctx) =>
                                            Navigator.of(ctx).pop(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Share of the screen covered by the grass band.
  static const double _groundFraction = 0.3;
}

/// Round chunky icon button with a label, flanking the cannon.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.badge,
    this.compact = false,
  });
  final MenuIcon icon;
  final String label;
  final ButtonTone tone;
  final VoidCallback onTap;

  /// Null = no badge, 0 = "!" dot, n = count.
  final int? badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // The whole button (icon and caption) is one tap target.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppScope.of(context).analytics.buttonTap(label);
        onTap();
      },
      child: SizedBox(
        width: compact ? 64 : 74,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                GameButton(
                  label: '',
                  analyticsName: label,
                  tone: tone,
                  height: compact ? 48 : 58,
                  icon: MenuIconView(icon: icon, size: compact ? 36 : 44),
                  onPressed: onTap,
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyles.number.copyWith(fontSize: 15)),
              ],
            ),
            if (badge != null)
              Positioned(
                right: -4,
                top: -6,
                child: NotifyDot(count: badge == 0 ? null : badge),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact mode tile sitting on the grass.
class _GroundTile extends StatelessWidget {
  const _GroundTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () {
          AppScope.of(context).analytics.buttonTap(label);
          onTap();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xE6203152),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.outline, width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: Palette.yellow,
                    size: 26,
                    shadows: const [
                      Shadow(color: Palette.outline, offset: Offset(0, 2)),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        label,
                        style: TextStyles.number.copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (badge) const Positioned(right: -4, top: -6, child: NotifyDot()),
          ],
        ),
      ),
    );
  }
}
