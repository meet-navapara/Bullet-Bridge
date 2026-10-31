import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/app_config.dart';
import '../../economy/catalog.dart';
import '../theme/palette.dart';
import 'art.dart';
import 'game_button.dart';

/// Chunky cartoon panel: slate blue (or warm wood) with a thick dark
/// outline, an inner highlight and a hard drop shadow.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gaps.lg),
    this.highlight,
    this.wood = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? highlight;
  final bool wood;

  @override
  Widget build(BuildContext context) {
    final top = wood ? Palette.woodLight : Palette.panelLight;
    final bottom = wood ? Palette.wood : Palette.panel;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        color: Palette.outline,
        boxShadow: [
          const BoxShadow(color: Color(0x55000000), offset: Offset(0, 5)),
          if (highlight != null)
            BoxShadow(color: highlight!.withValues(alpha: 0.6), blurRadius: 14),
        ],
      ),
      padding: EdgeInsets.all(highlight == null ? 3 : 3.5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg - 3),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
          border: Border.all(
            color: highlight ?? Colors.white.withValues(alpha: 0.18),
            width: highlight == null ? 1.5 : 3,
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Dark slanted chip used in HUDs (coins, score).
class HudChip extends StatelessWidget {
  const HudChip({
    super.key,
    required this.icon,
    required this.child,
    this.onAdd,
  });
  final Widget icon;
  final Widget child;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Transform(
              transform: Matrix4.skewX(-0.18),
              child: Container(
                height: 30,
                padding: EdgeInsets.only(
                  left: 22,
                  right: onAdd == null ? 14 : 34,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE6203152),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Palette.outline, width: 2.5),
                ),
                alignment: Alignment.center,
                child: Transform(transform: Matrix4.skewX(0.18), child: child),
              ),
            ),
          ),
          icon,
          if (onAdd != null)
            Positioned(
              right: 0,
              child: GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Palette.green,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Palette.outline, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Coin total chip. Rebuilds only when coins change.
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) => HudChip(
        icon: const CoinIcon(size: 34),
        onAdd: onAdd,
        child: Text(
          formatInt(progress.data.coins),
          style: TextStyles.number.copyWith(fontSize: 18),
        ),
      ),
    );
  }
}

/// The BOOMFORGE logo: tilted, gradient-filled arcade lettering with a
/// thick outline and a ribbon tagline.
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: TextStyles.display,
      fontSize: size,
      height: 1,
      letterSpacing: 1,
    );
    Widget word(String text, List<Color> colors) => Stack(
      children: [
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.2
              ..strokeJoin = StrokeJoin.round
              ..color = Palette.outline,
            shadows: const [
              Shadow(
                color: Color(0x88000000),
                offset: Offset(0, 6),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(rect),
          child: Text(text, style: style.copyWith(color: Colors.white)),
        ),
      ],
    );

    final title = AppConfig.title;
    final split = title.length > 4 ? 4 : title.length;
    return Semantics(
      header: true,
      label: '$title. ${AppConfig.tagline}',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Transform.rotate(
            angle: -0.05,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "BOOM" hot, "FORGE" steel blue.
                    word(title.substring(0, split), const [
                      Color(0xFFFFF59A),
                      Color(0xFFFFB627),
                      Color(0xFFFF5A1F),
                    ]),
                    word(title.substring(split), const [
                      Color(0xFFFFFFFF),
                      Color(0xFF9FD8FF),
                      Color(0xFF2F7BFF),
                    ]),
                  ],
                ),
                const SizedBox(height: 4),
                _Ribbon(
                  text: AppConfig.tagline.toUpperCase(),
                  size: size * 0.24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 1.2,
        vertical: size * 0.25,
      ),
      decoration: BoxDecoration(
        color: Palette.coral,
        borderRadius: BorderRadius.circular(size * 0.4),
        border: Border.all(color: Palette.outline, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), offset: Offset(0, 3)),
        ],
      ),
      child: Text(
        text,
        style: TextStyles.button.copyWith(fontSize: size, letterSpacing: 2),
      ),
    );
  }
}

/// Standard screen frame: illustrated world, back button, title, coins.
class ScreenShell extends StatelessWidget {
  const ScreenShell({
    super.key,
    required this.title,
    required this.child,
    this.showCoins = true,
    this.onBack,
  });

  final String title;
  final Widget child;
  final bool showCoins;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: WorldBackground(
        theme: Catalog.theme(services.progress.data.selectedTheme),
        dim: 0.45,
        groundFraction: 0.1,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gaps.lg,
                  Gaps.sm,
                  Gaps.lg,
                  Gaps.sm,
                ),
                child: Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: Gaps.md),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showCoins) const CoinBadge(),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded progress bar with a dark outline.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = Palette.green,
    this.height = 10,
  });
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height + 4,
      decoration: BoxDecoration(
        color: Palette.outline,
        borderRadius: BorderRadius.circular(height),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A3A),
          borderRadius: BorderRadius.circular(height),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(color, Colors.white, 0.35)!, color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small red notification dot.
class NotifyDot extends StatelessWidget {
  const NotifyDot({super.key, this.count});
  final int? count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: Palette.coral,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: Palette.outline, width: 2.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count == null ? '!' : '$count',
      style: TextStyles.number.copyWith(fontSize: 12, shadows: const []),
    ),
  );
}

/// Fade + slight upward slide page transition.
Route<T> gameRoute<T>(Widget page) => PageRouteBuilder<T>(
  // The name is what analytics reports for this screen.
  settings: RouteSettings(name: page.runtimeType.toString()),
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

void showToast(
  BuildContext context,
  String message, {
  Color color = Palette.panelLight,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
        duration: const Duration(milliseconds: 1600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: const BorderSide(color: Palette.outline, width: 2.5),
        ),
      ),
    );
}

/// Confirmation dialog styled like the game.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  ButtonTone confirmTone = ButtonTone.red,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(Gaps.xl),
      child: GamePanel(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyles.title.copyWith(fontSize: 26),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gaps.md),
            Text(
              message,
              style: TextStyles.body.copyWith(color: Palette.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gaps.xl),
            GameButton(
              label: confirmLabel,
              tone: confirmTone,
              height: 50,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: Gaps.sm),
            GameButton(
              label: 'Cancel',
              tone: ButtonTone.navy,
              height: 46,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
