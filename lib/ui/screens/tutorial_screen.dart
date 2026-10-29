import 'package:flutter/material.dart' hide Element;

import '../../app/app_services.dart';
import '../../economy/catalog.dart';
import '../../game/sim/entities.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import '../widgets/game_button.dart';

class _Page {
  const _Page(this.title, this.text, this.art);
  final String title;
  final String text;
  final Widget Function(BuildContext) art;
}

/// Short, skippable "How to Play" carousel. Completion is persisted.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onFinished});

  /// Called with this screen's context when the player finishes or skips.
  final void Function(BuildContext context) onFinished;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _page = 0;

  late final List<_Page> _pages = [
    _Page(
      'Drag to Move',
      'Swipe left or right anywhere. Your cannon fires on its own.',
      (context) => const _DragArt(),
    ),
    _Page(
      'Break the Crystals',
      'The number is how many hits a crystal can take. Big ones split in two.',
      (_) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CrystalBadge(tier: 4, label: '64', size: 110),
          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 32),
          Column(
            children: [
              CrystalBadge(tier: 3, label: '32', size: 76),
              CrystalBadge(tier: 3, label: '32', size: 76),
            ],
          ),
        ],
      ),
    ),
    _Page(
      'Chain Reactions',
      'Shoot volatile crystals near enemies. Blasts break more crystals, and long chains pay bonus coins!',
      (_) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HazardBadge(kind: HazardKind.blaze, size: 90),
          HazardBadge(kind: HazardKind.frost, size: 90),
          HazardBadge(kind: HazardKind.storm, size: 90),
        ],
      ),
    ),
    _Page(
      'Elements',
      'Unlock Fire, Ice and Shock as you clear levels, then switch any time from the bottom bar.',
      (_) => const Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        children: [
          ElementIcon(element: Element.kinetic, size: 56),
          ElementIcon(element: Element.fire, size: 56),
          ElementIcon(element: Element.ice, size: 56),
          ElementIcon(element: Element.electric, size: 56),
        ],
      ),
    ),
    _Page(
      'Know Your Enemy',
      'Geodes wear rock shells (Fire cracks them fast). Skyrays drop shards from above.',
      (_) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CrystalBadge(tier: 3, label: '40', size: 100, kind: EnemyKind.geode),
          SizedBox(width: 12),
          CrystalBadge(tier: 1, label: '12', size: 100, kind: EnemyKind.skyray),
        ],
      ),
    ),
    _Page(
      'Stay in One Piece',
      'Your cannon has 3 hearts. Use power-ups (bottom right) when things get hairy.',
      (_) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HeartIcon(filled: true, size: 52),
          HeartIcon(filled: true, size: 52),
          HeartIcon(filled: false, size: 52),
          SizedBox(width: 16),
          PowerUpIcon(type: PowerUpType.bomb, size: 56),
          PowerUpIcon(type: PowerUpType.shield, size: 56),
        ],
      ),
    ),
    _Page(
      'Forge Ahead',
      'Collect coins, then upgrade your cannon between runs. Pause any time with the top-right button.',
      (_) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CoinIcon(size: 64),
          SizedBox(width: 16),
          Icon(
            Icons.upgrade_rounded,
            color: Palette.green,
            size: 80,
            shadows: [Shadow(color: Palette.outline, offset: Offset(0, 3))],
          ),
        ],
      ),
    ),
  ];

  Future<void> _finish() async {
    await AppScope.of(context).progress.setTutorialDone(true);
    if (mounted) widget.onFinished(context);
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return ScreenShell(
      title: 'How to Play',
      showCoins: false,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final page = _pages[i];
                return Padding(
                  padding: const EdgeInsets.all(Gaps.xl),
                  child: Column(
                    children: [
                      Expanded(child: Center(child: page.art(context))),
                      GamePanel(
                        child: Column(
                          children: [
                            Text(
                              page.title,
                              style: TextStyles.title,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: Gaps.sm),
                            Text(
                              page.text,
                              style: TextStyles.body.copyWith(
                                color: Palette.textMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _page ? 22 : 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _page
                        ? Palette.yellow
                        : const Color(0x88FFFFFF),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Palette.outline, width: 2),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(Gaps.xl),
            child: Row(
              children: [
                if (!last)
                  TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Skip',
                      style: TextStyles.button.copyWith(fontSize: 18),
                    ),
                  ),
                if (!last) const SizedBox(width: Gaps.md),
                Expanded(
                  child: GameButton(
                    label: last ? 'Let\'s Go!' : 'Next',
                    tone: ButtonTone.blue,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DragArt extends StatefulWidget {
  const _DragArt();

  @override
  State<_DragArt> createState() => _DragArtState();
}

class _DragArtState extends State<_DragArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = Catalog.skin(AppScope.of(context).progress.data.selectedSkin);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dx = (Curves.easeInOut.transform(_c.value) - 0.5) * 140;
        return SizedBox(
          height: 190,
          width: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(
                top: 0,
                child: Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: 56,
                  shadows: [
                    Shadow(color: Palette.outline, offset: Offset(0, 3)),
                  ],
                ),
              ),
              Transform.translate(
                offset: Offset(dx, 10),
                child: CannonPreview(skin: skin, size: 120),
              ),
              Transform.translate(
                offset: Offset(dx + 24, 70),
                child: const Icon(
                  Icons.touch_app_rounded,
                  color: Colors.white,
                  size: 52,
                  shadows: [
                    Shadow(color: Palette.outline, offset: Offset(0, 3)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
