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
  ButtonTone.yellow: _ToneColors(
    Color(0xFFFFE66B),
    Color(0xFFFFB81C),
    Color(0xFFC77700),
    Color(0xFF3B2300),
  ),
  ButtonTone.green: _ToneColors(
    Color(0xFF6BF08C),
    Color(0xFF22B84E),
    Color(0xFF137A33),
    Colors.white,
  ),
  ButtonTone.blue: _ToneColors(
    Color(0xFF5AB2FF),
    Color(0xFF2569F0),
    Color(0xFF15409E),
    Colors.white,
  ),
  ButtonTone.navy: _ToneColors(
    Color(0xFF2A3B85),
    Color(0xFF1A2766),
    Color(0xFF0D1440),
    Colors.white,
  ),
  ButtonTone.red: _ToneColors(
    Color(0xFFFF7A7E),
    Color(0xFFE5394B),
    Color(0xFF931B2A),
    Colors.white,
  ),
  ButtonTone.purple: _ToneColors(
    Color(0xFFC690FF),
    Color(0xFF8A3DF0),
    Color(0xFF5420A3),
    Colors.white,
  ),
  ButtonTone.white: _ToneColors(
    Color(0xFFFFFFFF),
    Color(0xFFE9ECF4),
    Color(0xFFB4BACB),
    Color(0xFF1F1F1F),
  ),
};

/// Chunky glossy arcade button with a pressed state, click sound and
/// haptic tick. Disabled when [onPressed] is null.
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
    const lip = 5.0;
    final pressed = _down && enabled;
    final radius = BorderRadius.circular(widget.height * 0.32);
    // Long labels (prices!) scale down instead of being cut off.
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        widget.label,
        maxLines: 1,
        style: TextStyles.button.copyWith(
          color: c.text,
          fontSize: widget.fontSize ?? widget.height * 0.4,
          shadows: c.text == Colors.white
              ? TextStyles.button.shadows
              : const [],
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
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(
            height: widget.height + lip,
            child: Stack(
              children: [
                Positioned.fill(
                  top: lip,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.lip,
                      borderRadius: radius,
                      border: Border.all(color: Palette.outline, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 60),
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
                      // Thick cartoon outline.
                      border: Border.all(color: Palette.outline, width: 3),
                    ),
                    child: Stack(
                      children: [
                        // Gloss highlight.
                        Positioned(
                          left: 10,
                          right: 10,
                          top: 4,
                          height: widget.height * 0.3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.height,
                              ),
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Round icon button used for back/pause/settings.
class RoundIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final services = AppScope.of(context);
          services.audio.play(Sfx.click);
          services.haptics.trigger(Haptic.selection);
          final name = tooltip;
          if (name != null) services.analytics.buttonTap(name);
          onPressed();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.32),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5AB2FF), Color(0xFF2569F0)],
            ),
            border: Border.all(color: Palette.outline, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.55,
            shadows: const [
              Shadow(color: Palette.outline, offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}
