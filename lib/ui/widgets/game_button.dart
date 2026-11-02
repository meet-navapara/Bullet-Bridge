import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../theme/palette.dart';

enum ButtonTone { yellow, green, blue, navy, red, purple, white }

class _ToneColors {
  const _ToneColors(this.top, this.bottom, this.lip, this.text);
  final Color top;
  final Color bottom;
  final Color lip;
  final Color text;
}

const _tones = {
  // Molten gold: the primary action.
  ButtonTone.yellow: _ToneColors(
    Color(0xFFFFE27E),
    Color(0xFFFFA935),
    Color(0xFFB8611A),
    Color(0xFF3A1C00),
  ),
  ButtonTone.green: _ToneColors(
    Color(0xFF63F0AE),
    Color(0xFF17B46A),
    Color(0xFF0C7244),
    Colors.white,
  ),
  ButtonTone.blue: _ToneColors(
    Color(0xFF76A6FF),
    Color(0xFF3A5FEF),
    Color(0xFF213AA4),
    Colors.white,
  ),
  // Iron: secondary actions.
  ButtonTone.navy: _ToneColors(
    Color(0xFF353F74),
    Color(0xFF232A55),
    Color(0xFF13183A),
    Colors.white,
  ),
  ButtonTone.red: _ToneColors(
    Color(0xFFFF858B),
    Color(0xFFE53D57),
    Color(0xFF981D33),
    Colors.white,
  ),
  ButtonTone.purple: _ToneColors(
    Color(0xFFC79BFF),
    Color(0xFF834DF0),
    Color(0xFF5025A5),
    Colors.white,
  ),
  ButtonTone.white: _ToneColors(
    Color(0xFFFFFFFF),
    Color(0xFFE2E6F4),
    Color(0xFFA7AECB),
    Color(0xFF1A1F3A),
  ),
};

/// Rounded, softly bevelled forge button with a pressed state, click sound
/// and haptic tick. Disabled when [onPressed] is null.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = ButtonTone.yellow,
    this.height = 56,
    this.icon,
    this.fontSize,
    this.expand = true,
    this.silent = false,
    this.analyticsName,
  });

  /// Name reported when tapped, for buttons whose [label] is empty.
  final String? analyticsName;

  final String label;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final double height;
  final Widget? icon;
  final double? fontSize;
  final bool expand;
  final bool silent;

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _down = false;

  void _tap() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    if (!widget.silent) {
      final services = AppScope.of(context);
      services.audio.play(Sfx.click);
      services.haptics.trigger(Haptic.selection);
      final name = widget.analyticsName ?? widget.label;
      if (name.isNotEmpty) services.analytics.buttonTap(name);
    }
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final c = _tones[widget.tone]!;
    const lip = 4.0;
    final pressed = _down && enabled;
    final radius = BorderRadius.circular(widget.height * 0.3);
    final dark = c.text != Colors.white;
    // Long labels (prices!) scale down instead of being cut off.
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        widget.label,
        maxLines: 1,
        style: TextStyles.button.copyWith(
          color: c.text,
          fontSize: widget.fontSize ?? widget.height * 0.34,
          shadows: dark
              ? const [Shadow(color: Color(0x66FFFFFF), offset: Offset(0, 1))]
              : const [
                  Shadow(color: Color(0x99000000), offset: Offset(0, 1.5)),
                ],
        ),
      ),
    );
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled ? _tap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.45,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 90),
            scale: pressed ? 0.97 : 1,
            child: SizedBox(
              height: widget.height + lip,
              child: Stack(
                children: [
                  // Lip: the darker underside that gives the button depth.
                  Positioned.fill(
                    top: lip,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.lip,
                        borderRadius: radius,
                        boxShadow: enabled && widget.tone != ButtonTone.navy
                            ? Elevation.glow(c.bottom, strength: 0.4)
                            : Elevation.control,
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 70),
                    left: 0,
                    right: 0,
                    top: pressed ? lip - 1 : 0,
                    height: widget.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.top, c.bottom],
                        ),
                        border: Border.all(
                          color: Color.lerp(
                            c.top,
                            Colors.white,
                            0.35,
                          )!.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Soft top sheen.
                          Positioned(
                            left: 1.5,
                            right: 1.5,
                            top: 1.5,
                            height: widget.height * 0.46,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(widget.height * 0.28),
                                  bottom: Radius.circular(widget.height * 0.12),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.28),
                                    Colors.white.withValues(alpha: 0.04),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: widget.icon == null
                                  ? label
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        widget.icon!,
                                        if (widget.label.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Flexible(child: label),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Glassy iron squircle icon button used for back/pause/settings.
class RoundIconButton extends StatefulWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final String? tooltip;

  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          final services = AppScope.of(context);
          services.audio.play(Sfx.click);
          services.haptics.trigger(Haptic.selection);
          final name = widget.tooltip;
          if (name != null) services.analytics.buttonTap(name);
          widget.onPressed();
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _down ? 0.92 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.34),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE6363F78), Color(0xE61D2349)],
              ),
              border: Border.all(color: const Color(0x40FFFFFF), width: 1.2),
              boxShadow: Elevation.control,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: size * 0.52,
              shadows: const [
                Shadow(color: Color(0x99000000), offset: Offset(0, 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
