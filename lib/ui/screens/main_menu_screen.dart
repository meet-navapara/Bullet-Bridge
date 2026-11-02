import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/campaign.dart';
import '../../economy/catalog.dart';
import '../../economy/upgrades.dart';
import '../../progress/achievements.dart';
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

/// The hangar: the player's turret hovering over a forge pedestal under the
/// wordmark, the current chapter card with Play, the two extra modes and a
/// dock with the rest of the game.
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
          final chapter = Campaign.level(stage).chapterDef;
          return WorldBackground(
            theme: Catalog.theme(data.selectedTheme),
            groundFraction: 0.17,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 640;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
                    child: Column(
                      children: [
                        const SizedBox(height: Gaps.sm),
                        Row(
                          children: [
                            RoundIconButton(
                              icon: Icons.settings_rounded,
                              tooltip: 'Settings',
                              onPressed: () => _open(const SettingsScreen()),
                            ),
                            const SizedBox(width: Gaps.sm),
                            _HowToPill(
                              onTap: () => _open(
                                TutorialScreen(
                                  onFinished: (ctx) => Navigator.of(ctx).pop(),
                                ),
                              ),
                            ),
                            const SizedBox(width: Gaps.sm),
                            // Narrow phones shrink the chip rather than
                            // crowd the row.
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: CoinBadge(
                                    onAdd: () => _open(const ShopScreen()),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? Gaps.sm : Gaps.lg),
                        GameLogo(size: compact ? 44 : 58),
                        // The turret on its pedestal takes whatever height
                        // is left, so small phones simply get a smaller one.
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) => _Showcase(
                              size: box.maxHeight,
                              child: CannonPreview(
                                skin: skin,
                                level: data.level(UpgradeType.cannonLevel),
                                size: (box.maxHeight * 0.72).clamp(
                                  56.0,
                                  box.maxWidth * 0.66,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _ChapterCard(
                          eyebrow: worldDone
                              ? 'ALL CHAPTERS CLEARED'
                              : 'CHAPTER ${chapter.number} · ${chapter.name}',
                          title: worldDone
                              ? 'CAMPAIGN CLEARED'
                              : 'LEVEL $stage',
                          compact: compact,
                          child: GameButton(
                            label: worldDone ? 'Replay Boss' : 'Play',
                            height: compact ? 50 : 60,
                            icon: Icon(
                              Icons.play_arrow_rounded,
                              color: const Color(0xFF3A1C00),
                              size: compact ? 28 : 34,
                            ),
                            onPressed: _play,
                          ),
                        ),
                        const SizedBox(height: Gaps.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _ModeButton(
                                icon: Icons.all_inclusive_rounded,
                                label: 'Endless',
                                onTap: () => _open(const GameScreen()),
                              ),
                            ),
                            const SizedBox(width: Gaps.sm),
                            Expanded(
                              child: _ModeButton(
                                icon: Icons.bolt_rounded,
                                label: 'Challenge',
                                badge: challengeOpen,
                                onTap: () =>
                                    _open(const DailyChallengeScreen()),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? Gaps.sm : Gaps.md),
                        _Dock(
                          compact: compact,
                          items: [
                            _DockItem(
                              icon: Icons.map_rounded,
                              label: 'Levels',
                              onTap: () => _open(const WorldMapScreen()),
                            ),
                            _DockItem(
                              icon: Icons.keyboard_double_arrow_up_rounded,
                              label: 'Upgrade',
                              onTap: () => _open(const UpgradesScreen()),
                            ),
                            _DockItem(
                              icon: Icons.storefront_rounded,
                              label: 'Shop',
                              onTap: () => _open(const ShopScreen()),
                            ),
                            _DockItem(
                              icon: Icons.redeem_rounded,
                              label: 'Daily',
                              badge: dailyReady ? 0 : null,
                              onTap: () => _open(const DailyRewardScreen()),
                            ),
                            _DockItem(
                              icon: Icons.emoji_events_rounded,
                              label: 'Goals',
                              badge: claimable > 0 ? claimable : null,
                              onTap: () => _open(const MissionsScreen()),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gaps.sm),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The turret floating over a glowing forge ring; it rises into place when
/// the menu opens.
class _Showcase extends StatelessWidget {
  const _Showcase({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ringW = size * 1.15;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: size * 0.06,
          child: CustomPaint(
            size: Size(ringW, ringW * 0.28),
            painter: const _PedestalPainter(),
          ),
        ),
        Positioned(
          bottom: size * 0.13,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * size * 0.12),
                child: child,
              ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PedestalPainter extends CustomPainter {
  const _PedestalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final c = r.center;
    // Light column rising from the ring.
    canvas.drawOval(
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Palette.ember.withValues(alpha: 0.55),
            Palette.ember.withValues(alpha: 0),
          ],
        ).createShader(r),
    );
    final disc = Rect.fromCenter(
      center: c,
      width: size.width * 0.62,
      height: size.height * 0.42,
    );
    canvas.drawOval(
      disc,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A4170), Color(0xFF151A33)],
        ).createShader(disc),
    );
    canvas.drawOval(
      disc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFC24A), Color(0xFFFF7A2B), Color(0xFFFFC24A)],
        ).createShader(disc),
    );
    canvas.drawOval(
      disc.deflate(size.height * 0.07),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x55FFE2B8),
    );
  }

  @override
  bool shouldRepaint(_PedestalPainter oldDelegate) => false;
}

/// The current chapter and level above the Play button.
class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.eyebrow,
    required this.title,
    required this.child,
    required this.compact,
  });
  final String eyebrow;
  final String title;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      wood: true,
      padding: EdgeInsets.fromLTRB(
        Gaps.lg,
        compact ? Gaps.sm : Gaps.md,
        Gaps.lg,
        compact ? Gaps.sm : Gaps.lg,
      ),
      child: Column(
        children: [
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.eyebrow,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyles.title.copyWith(fontSize: compact ? 22 : 28),
          ),
          SizedBox(height: compact ? Gaps.xs : Gaps.sm),
          child,
        ],
      ),
    );
  }
}

/// A secondary game mode pill.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GameButton(
          label: label,
          tone: ButtonTone.navy,
          height: 44,
          fontSize: 15,
          icon: ForgeIcon(icon, size: 22),
          onPressed: onTap,
        ),
        if (badge) const Positioned(right: -2, top: -6, child: NotifyDot()),
      ],
    );
  }
}

class _HowToPill extends StatelessWidget {
  const _HowToPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'How to',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppScope.of(context).analytics.buttonTap('How to');
          onTap();
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xB3121733),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ForgeIcon(Icons.help_outline_rounded, size: 18),
              const SizedBox(width: 6),
              Text('How to', style: TextStyles.number.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass bar holding the main destinations.
class _Dock extends StatelessWidget {
  const _Dock({required this.items, required this.compact});
  final List<_DockItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 62 : 70,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE6262E5A), Color(0xF0111633)],
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: const Color(0x38FFFFFF)),
        boxShadow: Elevation.panel,
      ),
      child: Row(children: [for (final item in items) Expanded(child: item)]),
    );
  }
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Null = no badge, 0 = "!" dot, n = count.
  final int? badge;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          AppScope.of(context).analytics.buttonTap(widget.label);
          widget.onTap();
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _down ? 0.9 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ForgeIcon(widget.icon, size: 28),
                  if (badge != null)
                    Positioned(
                      right: -14,
                      top: -8,
                      child: NotifyDot(count: badge == 0 ? null : badge),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  style: TextStyles.number.copyWith(
                    fontSize: 12,
                    color: Palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
