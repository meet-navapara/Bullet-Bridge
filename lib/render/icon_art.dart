import 'dart:math' as math;
import 'dart:ui';

import '../game/sim/entities.dart';
import '../ui/theme/palette.dart';
import 'ball_art.dart';

/// Vector icons for coins and power-ups, drawn centred in a unit box of
/// size [size]. Shared by the game renderer and Flutter widgets.
abstract final class IconArt {
  static final Paint _p = Paint()..isAntiAlias = true;
  static final Paint _s = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Color colorFor(PowerUpType type) => switch (type) {
    PowerUpType.bomb => Palette.orange,
    PowerUpType.slowMotion => Palette.purple,
    PowerUpType.shield => Palette.cyan,
    PowerUpType.powerShot => Palette.yellow,
  };

  static String labelFor(PowerUpType type) => switch (type) {
    PowerUpType.bomb => 'Bomb',
    PowerUpType.slowMotion => 'Slow Motion',
    PowerUpType.shield => 'Shield',
    PowerUpType.powerShot => 'Power Shot',
  };

  static void coin(Canvas canvas, Offset c, double size) {
    final r = size / 2;
    _p.shader = Gradient.radial(
      c.translate(-r * 0.3, -r * 0.35),
      r * 1.4,
      [const Color(0xFFFFF1A8), Palette.gold, const Color(0xFFC77800)],
      const [0, 0.45, 1],
    );
    canvas.drawCircle(c, r, _p);
    _p.shader = null;
    _s
      ..color = const Color(0xFFA35F00)
      ..strokeWidth = r * 0.12;
    canvas.drawCircle(c, r * 0.94, _s);
    _s
      ..color = const Color(0xCCFFF3B0)
      ..strokeWidth = r * 0.1;
    canvas.drawCircle(c, r * 0.62, _s);
    _p.color = const Color(0xFFE59A00);
    canvas.drawPath(_star(c, r * 0.42, r * 0.18), _p);
  }

  static void powerUp(Canvas canvas, PowerUpType type, Offset c, double size) {
    switch (type) {
      case PowerUpType.bomb:
        _bomb(canvas, c, size);
      case PowerUpType.slowMotion:
        _clock(canvas, c, size);
      case PowerUpType.shield:
        _shield(canvas, c, size);
      case PowerUpType.powerShot:
        _bolt(canvas, c, size);
    }
  }

  static void _bomb(Canvas canvas, Offset c, double size) {
    final r = size * 0.36;
    final center = c.translate(0, size * 0.07);
    _p.shader = Gradient.radial(
      center.translate(-r * 0.35, -r * 0.4),
      r * 1.5,
      [
        const Color(0xFF6B7393),
        const Color(0xFF20243A),
        const Color(0xFF07080F),
      ],
      const [0, 0.5, 1],
    );
    canvas.drawCircle(center, r, _p);
    _p.shader = null;
    _p.color = const Color(0xFF3A3F5C);
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(r * 0.45, -r * 0.85),
        width: r * 0.5,
        height: r * 0.35,
      ),
      _p,
    );
    _s
      ..color = const Color(0xFFC9A36B)
      ..strokeWidth = size * 0.05;
    final fuse = Path()
      ..moveTo(center.dx + r * 0.55, center.dy - r * 1.0)
      ..quadraticBezierTo(
        center.dx + r * 0.9,
        center.dy - r * 1.5,
        center.dx + r * 1.2,
        center.dy - r * 1.3,
      );
    canvas.drawPath(fuse, _s);
    _p.color = Palette.yellow;
    canvas.drawPath(
      _star(
        Offset(center.dx + r * 1.22, center.dy - r * 1.32),
        size * 0.13,
        size * 0.05,
      ),
      _p,
    );
    _p.color = Palette.orange;
    canvas.drawCircle(
      Offset(center.dx + r * 1.22, center.dy - r * 1.32),
      size * 0.04,
      _p,
    );
    _p.color = const Color(0x66FFFFFF);
    canvas.drawOval(
      Rect.fromLTWH(center.dx - r * 0.6, center.dy - r * 0.7, r * 0.5, r * 0.3),
      _p,
    );
  }

  static void _clock(Canvas canvas, Offset c, double size) {
    final r = size * 0.38;
    final center = c.translate(0, size * 0.04);
    _p.color = const Color(0xFF7A3BE0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, -r * 1.12),
          width: r * 0.55,
          height: r * 0.3,
        ),
        Radius.circular(r * 0.1),
      ),
      _p,
    );
    _p.shader = Gradient.radial(
      center.translate(-r * 0.3, -r * 0.3),
      r * 1.4,
      [const Color(0xFFD7A6FF), Palette.purple, const Color(0xFF5A1FB0)],
      const [0, 0.45, 1],
    );
    canvas.drawCircle(center, r, _p);
    _p.shader = null;
    _p.color = const Color(0xFFF4ECFF);
    canvas.drawCircle(center, r * 0.72, _p);
    _s
      ..color = const Color(0xFF4A1A90)
      ..strokeWidth = size * 0.055;
    canvas.drawLine(center, center.translate(0, -r * 0.5), _s);
    canvas.drawLine(center, center.translate(r * 0.38, r * 0.12), _s);
    _p.color = const Color(0xFF4A1A90);
    canvas.drawCircle(center, size * 0.04, _p);
  }

  static void _shield(Canvas canvas, Offset c, double size) {
    final w = size * 0.7;
    final h = size * 0.8;
    final top = c.dy - h / 2;
    Path shieldPath(double inset) => Path()
      ..moveTo(c.dx, top + inset)
      ..quadraticBezierTo(
        c.dx + w * 0.3,
        top + h * 0.1 + inset,
        c.dx + w / 2 - inset,
        top + h * 0.12 + inset,
      )
      ..quadraticBezierTo(
        c.dx + w / 2 - inset,
        top + h * 0.7,
        c.dx,
        top + h - inset,
      )
      ..quadraticBezierTo(
        c.dx - w / 2 + inset,
        top + h * 0.7,
        c.dx - w / 2 + inset,
        top + h * 0.12 + inset,
      )
      ..quadraticBezierTo(
        c.dx - w * 0.3,
        top + h * 0.1 + inset,
        c.dx,
        top + inset,
      )
      ..close();
    _p.shader = Gradient.linear(Offset(c.dx, top), Offset(c.dx, top + h), [
      const Color(0xFF8BE6FF),
      const Color(0xFF1D7FE0),
    ]);
    canvas.drawPath(shieldPath(0), _p);
    _p.shader = null;
    _p.color = const Color(0xFF0E4AA8);
    canvas.drawPath(shieldPath(size * 0.09), _p);
    _p.shader = Gradient.linear(Offset(c.dx, top), Offset(c.dx, top + h), [
      const Color(0xFF6FD3FF),
      const Color(0xFF2B8FF0),
    ]);
    canvas.drawPath(shieldPath(size * 0.13), _p);
    _p.shader = null;
    _p.color = const Color(0xE6FFFFFF);
    canvas.drawPath(
      _star(c.translate(0, -size * 0.02), size * 0.17, size * 0.07),
      _p,
    );
  }

  static void _bolt(Canvas canvas, Offset c, double size) {
    final r = size * 0.42;
    final rect = Rect.fromCenter(center: c, width: r * 2, height: r * 2);
    _p.shader = Gradient.linear(rect.topLeft, rect.bottomRight, [
      const Color(0xFFC77BFF),
      const Color(0xFF6A23D6),
    ]);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(r * 0.45));
    canvas.drawRRect(rr, _p);
    _p.shader = null;
    _s
      ..color = const Color(0xFFE4C2FF)
      ..strokeWidth = size * 0.04;
    canvas.drawRRect(rr.deflate(size * 0.03), _s);
    final bolt = Path()
      ..moveTo(c.dx + r * 0.15, c.dy - r * 0.8)
      ..lineTo(c.dx - r * 0.45, c.dy + r * 0.1)
      ..lineTo(c.dx - r * 0.02, c.dy + r * 0.1)
      ..lineTo(c.dx - r * 0.18, c.dy + r * 0.8)
      ..lineTo(c.dx + r * 0.45, c.dy - r * 0.15)
      ..lineTo(c.dx + r * 0.02, c.dy - r * 0.15)
      ..close();
    _p.color = Palette.yellow;
    canvas.drawPath(bolt, _p);
    _s
      ..color = const Color(0xFFB36B00)
      ..strokeWidth = size * 0.03;
    canvas.drawPath(bolt, _s);
  }

  static Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// Ball tinted badge used by tutorial/menus.
  static Color ballColor(int tier) => BallArt.colorForTier(tier);
}
