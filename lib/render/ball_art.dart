import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../ui/theme/palette.dart';

Color shade(Color c, double amount) {
  // amount > 0 lightens towards white, < 0 darkens towards black.
  final target = amount >= 0
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  return Color.lerp(c, target, amount.abs())!;
}

/// Draws glossy numbered balls. Paints and text layouts are cached so a
/// frame with many balls allocates almost nothing.
class BallArt {
  final Map<int, Paint> _bodies = {};
  final Map<int, Paint> _glows = {};
  final Map<int, Paint> _rims = {};
  final Map<String, (TextPainter, TextPainter)> _labels = {};
  final Paint _highlight = Paint()..color = const Color(0x8CFFFFFF);
  final Paint _flash = Paint();

  Paint _body(Color color) => _bodies.putIfAbsent(
    color.toARGB32(),
    () => Paint()
      ..shader = ui.Gradient.radial(
        const Offset(-0.35, -0.42),
        1.45,
        [shade(color, 0.5), color, shade(color, -0.38)],
        const [0.0, 0.5, 1.0],
      ),
  );

  Paint _glow(Color color) => _glows.putIfAbsent(
    color.toARGB32(),
    () => Paint()
      ..shader = ui.Gradient.radial(Offset.zero, 1.0, [
        color.withValues(alpha: 0.42),
        color.withValues(alpha: 0),
      ]),
  );

  Paint _rim(Color color) => _rims.putIfAbsent(
    color.toARGB32(),
    () => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..color = shade(color, -0.5),
  );

  void draw(
    Canvas canvas, {
    required double x,
    required double y,
    required double radius,
    required Color color,
    String? label,
    double flash = 0,
    double squash = 0,
    bool glow = true,
  }) {
    canvas.save();
    // Squash anchors at the bottom of the ball so it "lands".
    final sx = 1 + 0.2 * squash;
    final sy = 1 - 0.2 * squash;
    canvas.translate(x, y + radius * (1 - sy));
    if (glow) {
      canvas.save();
      canvas.scale(radius * 1.65);
      canvas.drawCircle(Offset.zero, 1, _glow(color));
      canvas.restore();
    }
    canvas.save();
    canvas.scale(radius * sx, radius * sy);
    canvas.drawCircle(Offset.zero, 1, _body(color));
    canvas.drawCircle(Offset.zero, 0.965, _rim(color));
    canvas.drawOval(const Rect.fromLTWH(-0.62, -0.78, 0.62, 0.34), _highlight);
    if (flash > 0) {
      _flash.color = Color.fromRGBO(255, 255, 255, (flash * 0.7).clamp(0, 1));
      canvas.drawCircle(Offset.zero, 1, _flash);
    }
    canvas.restore();
    if (label != null) _drawLabel(canvas, label, radius);
    canvas.restore();
  }

  void _drawLabel(Canvas canvas, String label, double radius) {
    final factor = switch (label.length) {
      1 || 2 => 0.95,
      3 => 0.78,
      _ => 0.62,
    };
    final fontSize = (radius * factor * 2).roundToDouble() / 2;
    final key = '$label@$fontSize';
    if (_labels.length > 400) _labels.clear();
    final painters = _labels.putIfAbsent(key, () {
      TextPainter make(Paint? stroke) => TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: TextStyles.display,
            fontSize: fontSize,
            height: 1,
            color: stroke == null ? const Color(0xFFFFFFFF) : null,
            foreground: stroke,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, fontSize * 0.14)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x99000000);
      return (make(outline), make(null));
    });
    final (outline, fill) = painters;
    final offset = Offset(-fill.width / 2, -fill.height / 2 + fontSize * 0.04);
    outline.paint(canvas, offset);
    fill.paint(canvas, offset);
  }

  static Color colorForTier(int tier) =>
      Palette.ballTiers[tier.clamp(0, Palette.ballTiers.length - 1)];
}
