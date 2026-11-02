import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../config/app_config.dart';
import '../../economy/catalog.dart';
import '../theme/palette.dart';
import 'art.dart';
import 'game_button.dart';

/// Iron-glass panel: a cool gradient, a light rim, a soft top sheen and a
/// deep soft shadow. [wood] gives the warm forge variant with a brass rim.
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
    final rim =
        highlight ??
        (wood
            ? Palette.brass.withValues(alpha: 0.55)
            : Palette.panelBorder.withValues(alpha: 0.8));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top.withValues(alpha: 0.97), bottom.withValues(alpha: 0.97)],
        ),
        border: Border.all(color: rim, width: highlight == null ? 1.2 : 2),
        boxShadow: [
          ...Elevation.panel,
          if (highlight != null)
            BoxShadow(
              color: highlight!.withValues(alpha: 0.35),
              blurRadius: 22,
              spreadRadius: -2,
            ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.55),
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Brass-to-ember fill shared by every UI icon.
class ForgeIcon extends StatelessWidget {
  const ForgeIcon(this.icon, {super.key, this.size = 26});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (r) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFE7A6), Color(0xFFFFB443), Color(0xFFFF7A2B)],
    ).createShader(r),
    child: Icon(icon, size: size, color: Colors.white),
  );
}

/// Glass pill used in HUDs (coins, score), with its icon overlapping the
/// left end.
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
            padding: const EdgeInsets.only(left: 14),
            child: Container(
              height: 32,
              padding: EdgeInsets.only(
                left: 26,
                right: onAdd == null ? 14 : 36,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xD9262E5A), Color(0xD9121733)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33FFFFFF)),
                boxShadow: Elevation.control,
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
          icon,
          if (onAdd != null)
            Positioned(
              right: 3,
              child: GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF63F0AE), Color(0xFF17B46A)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0x66FFFFFF)),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 19,
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

/// Coin total chip. Rebuilds only when coins change, and rolls to the new
/// total instead of jumping.
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
        child: RollingNumber(
          value: progress.data.coins,
          style: TextStyles.number.copyWith(fontSize: 16),
        ),
      ),
    );
  }
}

/// An integer that counts to its new value when it changes.
class RollingNumber extends StatelessWidget {
  const RollingNumber({super.key, required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatInt(v.round()), style: style),
    );
  }
}

/// The BOOMFORGE wordmark: "BOOM" in molten metal, "FORGE" in brushed
/// steel, set straight on an ink stroke, with the tagline between two ember
/// rules.
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: TextStyles.display,
      fontSize: size,
      height: 1,
      letterSpacing: size * 0.02,
    );
    Widget word(String text, List<Color> colors) => Stack(
      children: [
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = Palette.outline,
            shadows: [
              Shadow(
                color: const Color(0x99000000),
                offset: Offset(0, size * 0.08),
                blurRadius: size * 0.12,
              ),
            ],
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: const [0, 0.48, 0.52, 1],
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A hard split in each gradient reads as a polished bevel.
                  word(title.substring(0, split), const [
                    Color(0xFFFFF3B8),
                    Color(0xFFFFC245),
                    Color(0xFFFF9A2E),
                    Color(0xFFE2471A),
                  ]),
                  word(title.substring(split), const [
                    Color(0xFFFFFFFF),
                    Color(0xFFD5DDF2),
                    Color(0xFFA6B2D6),
                    Color(0xFF6874A3),
                  ]),
                ],
              ),
              SizedBox(height: size * 0.14),
              _Tagline(text: AppConfig.tagline.toUpperCase(), size: size * 0.2),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget rule(bool left) => Container(
      width: size * 3,
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: left
              ? [Palette.ember.withValues(alpha: 0), Palette.ember]
              : [Palette.ember, Palette.ember.withValues(alpha: 0)],
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule(true),
        SizedBox(width: size * 0.6),
        Text(
          text,
          style: TextStyles.button.copyWith(
            fontSize: size,
            letterSpacing: size * 0.35,
            color: const Color(0xFFFFE2B8),
          ),
        ),
        SizedBox(width: size * 0.25),
        rule(false),
      ],
    );
  }
}

/// Standard screen frame: dimmed world, back button, title, coins.
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
        dim: 0.6,
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
                        style: TextStyles.title.copyWith(fontSize: 24),
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

/// Rounded progress bar in a recessed well, with a glossy fill.
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
        color: const Color(0xB30A0D1F),
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      padding: const EdgeInsets.all(2),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(color, Colors.white, 0.4)!, color],
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small notification dot.
class NotifyDot extends StatelessWidget {
  const NotifyDot({super.key, this.count});
  final int? count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFF8A7A), Color(0xFFE8364F)],
      ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Palette.background, width: 2),
      boxShadow: Elevation.glow(Palette.coral, strength: 0.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count == null ? '!' : '$count',
      style: TextStyles.number.copyWith(fontSize: 11, shadows: const []),
    ),
  );
}

/// Fade + slight upward slide page transition.
Route<T> gameRoute<T>(Widget page) => PageRouteBuilder<T>(
  // The name is what analytics reports for this screen.
  settings: RouteSettings(name: page.runtimeType.toString()),
  transitionDuration: const Duration(milliseconds: 280),
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
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
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
          side: const BorderSide(color: Color(0x40FFFFFF)),
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
    barrierColor: const Color(0xA60A0D1F),
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
              style: TextStyles.title.copyWith(fontSize: 23),
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
