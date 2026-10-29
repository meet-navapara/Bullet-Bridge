import 'dart:math' as math;

import 'package:flutter/material.dart' hide Element;

import '../../app/app_services.dart';
import '../../config/balance.dart';
import '../../config/campaign.dart';
import '../../game/sim/entities.dart';
import '../../progress/save_data.dart';
import '../../render/hud_art.dart';
import '../theme/palette.dart';
import '../widgets/art.dart';
import '../widgets/common.dart';
import 'game_screen.dart';

/// Campaign map: ten chapters of ten levels along winding paths. Chapters
/// the player has not reached are shown locked; the current chapter opens
/// scrolled into view.
class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({super.key});

  static const double rowHeight = 96;
  static const double headerHeight = 156;
  static const double lockedHeight = 144;
  static const double gap = Gaps.lg;

  /// Horizontal position (-1..1) of each level node along the path.
  static double xFor(int level) => math.sin(level * 1.15) * 0.62;

  /// Element unlocked by clearing [level], if any.
  static Element? unlockAt(int level) {
    for (final e in Element.values) {
      final at = switch (e) {
        Element.fire => ElementSpec.fireUnlockStage,
        Element.ice => ElementSpec.iceUnlockStage,
        Element.electric => ElementSpec.electricUnlockStage,
        Element.kinetic => 0,
      };
      if (e != Element.kinetic && at == level) return e;
    }
    return null;
  }

  static bool chapterOpen(ChapterDef c, SaveData d) =>
      c.firstLevel <= d.highestStageCleared + 1;

  static double chapterExtent(ChapterDef c, SaveData d) => chapterOpen(c, d)
      ? headerHeight + StageSpec.levelsPerChapter * rowHeight + gap
      : lockedHeight + gap;

  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> {
  ScrollController? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scroll != null) return;
    // Open on the chapter of the next level to play.
    final progress = AppScope.of(context).progress;
    final d = progress.data;
    final current = StageSpec.chapterOf(progress.nextStage);
    var offset = 0.0;
    for (final c in Campaign.chapters.take(current - 1)) {
      offset += WorldMapScreen.chapterExtent(c, d);
    }
    _scroll = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ScreenShell(
      title: 'Levels',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final data = progress.data;
          return ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.xl),
            itemCount: Campaign.chapters.length,
            itemBuilder: (context, i) {
              final chapter = Campaign.chapters[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: WorldMapScreen.gap),
                child: WorldMapScreen.chapterOpen(chapter, data)
                    ? _ChapterSection(chapter: chapter)
                    : SizedBox(
                        height: WorldMapScreen.lockedHeight,
                        child: _LockedChapter(chapter: chapter),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChapterSection extends StatelessWidget {
  const _ChapterSection({required this.chapter});
  final ChapterDef chapter;

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    final data = progress.data;
    final stars = [
      for (var l = chapter.firstLevel; l <= chapter.lastLevel; l++)
        data.stageStars[l] ?? 0,
    ].fold(0, (a, b) => a + b);
    const n = StageSpec.levelsPerChapter;
    return Column(
      children: [
        SizedBox(
          height: WorldMapScreen.headerHeight - Gaps.md,
          child: _ChapterBanner(
            chapter: chapter,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: Palette.yellow, size: 24),
                Text('$stars/${n * 3}', style: TextStyles.number),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gaps.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            Offset at(int slot) => Offset(
              w / 2 + WorldMapScreen.xFor(slot) * w / 2 * 0.8,
              (slot - 0.5) * WorldMapScreen.rowHeight,
            );
            return SizedBox(
              height: n * WorldMapScreen.rowHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PathPainter(
                        [for (var s = 1; s <= n; s++) at(s)],
                        (data.highestStageCleared - chapter.firstLevel + 1)
                            .clamp(0, n),
                      ),
                    ),
                  ),
                  for (var s = 1; s <= n; s++)
                    Positioned(
                      left: at(s).dx - 44,
                      top: (s - 1) * WorldMapScreen.rowHeight + 4,
                      width: 88,
                      child: _StageNode(
                        level: Campaign.level(chapter.firstLevel + s - 1),
                        stars: data.stageStars[chapter.firstLevel + s - 1] ?? 0,
                        unlocked: progress.isStageUnlocked(
                          chapter.firstLevel + s - 1,
                        ),
                        current:
                            chapter.firstLevel + s - 1 == progress.nextStage &&
                            !progress.campaignComplete,
                        unlock: WorldMapScreen.unlockAt(
                          chapter.firstLevel + s - 1,
                        ),
                        onTap: () => Navigator.of(context).push(
                          gameRoute<void>(
                            GameScreen(stage: chapter.firstLevel + s - 1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Chapter header: its environment as a backdrop, name, boss and stars.
class _ChapterBanner extends StatelessWidget {
  const _ChapterBanner({
    required this.chapter,
    required this.trailing,
    this.locked = false,
  });
  final ChapterDef chapter;
  final Widget trailing;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Chapter ${chapter.number}, ${chapter.name}'
          '${locked ? ', locked' : ''}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: Palette.outline, width: 3.5),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), offset: Offset(0, 5)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ThemePreview(theme: chapter.theme),
            ColoredBox(
              color: locked ? const Color(0x99101830) : const Color(0x55101830),
            ),
            Padding(
              padding: const EdgeInsets.all(Gaps.md),
              child: Row(
                children: [
                  if (locked) ...[
                    const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: Gaps.md),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHAPTER ${chapter.number} · LEVELS '
                          '${chapter.firstLevel}-${chapter.lastLevel}',
                          style: TextStyles.caption.copyWith(
                            color: Palette.yellow,
                            shadows: TextStyles.outlined,
                          ),
                        ),
                        Text(
                          chapter.name,
                          style: TextStyles.heading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          locked
                              ? 'Beat level ${chapter.firstLevel - 1} to enter.'
                              : 'Boss: ${chapter.boss.name}',
                          style: TextStyles.caption.copyWith(
                            color: Colors.white,
                            shadows: TextStyles.outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedChapter extends StatelessWidget {
  const _LockedChapter({required this.chapter});
  final ChapterDef chapter;

  @override
  Widget build(BuildContext context) => _ChapterBanner(
    chapter: chapter,
    locked: true,
    trailing: const Icon(
      Icons.diamond_rounded,
      color: Color(0xFFFF8A8A),
      size: 30,
    ),
  );
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.points, this.cleared);
  final List<Offset> points;
  final int cleared;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length - 1; i++) {
      final done = i + 1 <= cleared;
      final a = points[i];
      final b = points[i + 1];
      final mid = Offset(
        (a.dx + b.dx) / 2 + (b.dy - a.dy) * 0.3,
        (a.dy + b.dy) / 2,
      );
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = Palette.outline,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = done ? Palette.yellow : const Color(0xFF8C97B8),
      );
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.cleared != cleared || old.points.length != points.length;
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.level,
    required this.stars,
    required this.unlocked,
    required this.current,
    required this.unlock,
    required this.onTap,
  });

  final LevelDef level;
  final int stars;
  final bool unlocked;
  final bool current;
  final Element? unlock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final boss = level.isBoss;
    final recovery =
        level.category == LevelCategory.recovery ||
        level.category == LevelCategory.intro;
    final size = boss ? 74.0 : 62.0;
    final colors = !unlocked
        ? const [Color(0xFF8C97B8), Color(0xFF5A6384)]
        : boss
        ? const [Color(0xFFFF8A8A), Color(0xFFD62B45)]
        : stars > 0
        ? const [Color(0xFF7CF0A0), Color(0xFF22B84E)]
        : recovery
        ? const [Color(0xFF8FE3FF), Color(0xFF2E9CD6)]
        : const [Color(0xFFFFE66B), Color(0xFFFFB81C)];
    final number = level.number;
    return Semantics(
      button: true,
      enabled: unlocked,
      label: unlocked
          ? 'Level $number${boss ? ', boss ${level.boss!.name}' : ''}, '
                '$stars stars'
          : 'Level $number, locked',
      child: GestureDetector(
        onTap: unlocked ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (current)
                  Container(
                    width: size + 16,
                    height: size + 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Palette.yellow.withValues(alpha: 0.8),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: colors,
                    ),
                    border: Border.all(color: Palette.outline, width: 3.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: unlocked
                      ? (boss
                            ? const Icon(
                                Icons.diamond_rounded,
                                color: Colors.white,
                                size: 38,
                                shadows: [
                                  Shadow(
                                    color: Palette.outline,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              )
                            : FittedBox(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    '$number',
                                    style: TextStyles.title.copyWith(
                                      fontSize: 26,
                                    ),
                                  ),
                                ),
                              ))
                      : const Icon(
                          Icons.lock_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
                // Element unlocked by this level (right) and the mechanic
                // it introduces (left); both can appear on one node.
                if (unlock != null)
                  Positioned(
                    right: -18,
                    top: -6,
                    child: _Badge(
                      tooltip: 'Clear to unlock ${HudArt.elementName(unlock!)}',
                      child: ElementIcon(element: unlock!, size: 22),
                    ),
                  ),
                if (level.introduces != null)
                  Positioned(
                    left: -18,
                    top: -6,
                    child: _Badge(
                      tooltip: level.introduces!.intro,
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Palette.yellow,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            // Pill backing so the path never runs through the stars.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xE6203152),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.outline, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: i < stars
                          ? Palette.yellow
                          : const Color(0x55FFFFFF),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.tooltip, required this.child});
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF203152),
        border: Border.all(color: Palette.outline, width: 2.5),
      ),
      alignment: Alignment.center,
      child: child,
    ),
  );
}
