import 'dart:math' as math;
import 'dart:ui';

import '../game/sim/entities.dart';
import 'ball_art.dart';
import 'crystal_art.dart';

/// Icons for elements and hull points, centred in a box of [size].
abstract final class HudArt {
  static const _outline = Color(0xFF1C1830);
  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  static String elementName(Element e) => switch (e) {
    Element.kinetic => 'Kinetic',
    Element.fire => 'Fire',
    Element.ice => 'Ice',
    Element.electric => 'Shock',
  };

  static void element(Canvas c, Element e, Offset center, double size) {
    final s = size / 2;
    final color = elementColor(e);
    _stroke
      ..color = _outline
      ..strokeWidth = math.max(1.5, size * 0.06);
    switch (e) {
      case Element.kinetic:
        // Steel cannonball with a highlight.
        _fill.shader = Gradient.radial(
          center.translate(-s * 0.3, -s * 0.3),
          s,
          [
            const Color(0xFFFFFFFF),
            const Color(0xFF9AA6BF),
            const Color(0xFF4A5268),
          ],
          const [0, 0.4, 1],
        );
        c.drawCircle(center, s * 0.62, _fill);
        _fill.shader = null;
        c.drawCircle(center, s * 0.62, _stroke);
      case Element.fire:
        final f = Path()
          ..moveTo(center.dx, center.dy - s * 0.85)
          ..quadraticBezierTo(
            center.dx + s * 0.8,
            center.dy - s * 0.1,
            center.dx + s * 0.5,
            center.dy + s * 0.55,
          )
          ..quadraticBezierTo(
            center.dx,
            center.dy + s * 0.95,
            center.dx - s * 0.5,
            center.dy + s * 0.55,
          )
          ..quadraticBezierTo(
            center.dx - s * 0.75,
            center.dy,
            center.dx - s * 0.2,
            center.dy - s * 0.35,
          )
          ..quadraticBezierTo(
            center.dx - s * 0.05,
            center.dy - s * 0.1,
            center.dx,
            center.dy - s * 0.85,
          )
          ..close();
        _fill.color = color;
        c.drawPath(f, _fill);
        c.drawPath(f, _stroke);
        _fill.color = const Color(0xFFFFE07A);
        c.drawCircle(center.translate(0, s * 0.35), s * 0.28, _fill);
      case Element.ice:
        for (var k = 0; k < 3; k++) {
          final a = k * math.pi / 3;
          final d = Offset(math.cos(a), math.sin(a)) * (s * 0.8);
          _stroke
            ..color = _outline
            ..strokeWidth = size * 0.16;
          c.drawLine(center - d, center + d, _stroke);
          _stroke
            ..color = color
            ..strokeWidth = size * 0.09;
          c.drawLine(center - d, center + d, _stroke);
        }
        _fill.color = const Color(0xFFFFFFFF);
        c.drawCircle(center, s * 0.18, _fill);
      case Element.electric:
        final bolt = Path()
          ..moveTo(center.dx + s * 0.15, center.dy - s * 0.9)
          ..lineTo(center.dx - s * 0.5, center.dy + s * 0.1)
          ..lineTo(center.dx - s * 0.02, center.dy + s * 0.1)
          ..lineTo(center.dx - s * 0.2, center.dy + s * 0.9)
          ..lineTo(center.dx + s * 0.5, center.dy - s * 0.2)
          ..lineTo(center.dx + s * 0.05, center.dy - s * 0.2)
          ..close();
        _fill.color = color;
        c.drawPath(bolt, _fill);
        _stroke.strokeWidth = math.max(1.5, size * 0.06);
        c.drawPath(bolt, _stroke..color = _outline);
    }
  }

  static void heart(
    Canvas c,
    Offset center,
    double size, {
    required bool filled,
  }) {
    final s = size / 2;
    final p = Path()
      ..moveTo(center.dx, center.dy + s * 0.8)
      ..cubicTo(
        center.dx - s * 1.2,
        center.dy,
        center.dx - s * 0.7,
        center.dy - s * 0.95,
        center.dx,
        center.dy - s * 0.35,
      )
      ..cubicTo(
        center.dx + s * 0.7,
        center.dy - s * 0.95,
        center.dx + s * 1.2,
        center.dy,
        center.dx,
        center.dy + s * 0.8,
      )
      ..close();
    _fill.color = filled ? const Color(0xFFFF4B5C) : const Color(0x55262040);
    c.drawPath(p, _fill);
    if (filled) {
      _fill.color = shade(const Color(0xFFFF4B5C), 0.5);
      c.drawCircle(center.translate(-s * 0.38, -s * 0.3), s * 0.16, _fill);
    }
    _stroke
      ..color = _outline
      ..strokeWidth = math.max(1.5, size * 0.08);
    c.drawPath(p, _stroke);
  }
}
