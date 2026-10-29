import 'dart:math' as math;
import 'dart:ui';

import '../economy/catalog.dart';
import '../economy/upgrades.dart';
import 'ball_art.dart';

/// Cartoon field cannon drawn in world units with its base at (0, 0) and
/// the barrel pointing up: two big spoked wheels, a painted carriage and a
/// banded, tapered barrel with a glowing element core. ~66 wide, ~60 tall.
abstract final class CannonArt {
  static const _outline = Color(0xFF1C1830);
  static final Paint _fill = Paint()..isAntiAlias = true;
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  static void draw(
    Canvas canvas, {
    required double x,
    required double baseY,
    required CannonSkin skin,
    required int level,
    double recoil = 0,
    double tilt = 0,
    double glowPulse = 0,
    double scale = 1,
    double wheelAngle = 0,
    Color? core,
    double muzzleFlash = 0,
  }) {
    final c = canvas;
    c.save();
    c.translate(x, baseY);
    c.scale(scale);

    // Ground shadow.
    _fill.color = const Color(0x44000000);
    c.drawOval(const Rect.fromLTRB(-34, -4, 34, 4), _fill);

    c.save();
    c.rotate(tilt);
    final streams = Upgrades.streams(level);
    final coreColor = core ?? skin.glow;

    // Barrel (behind the wheels, rising out of the carriage).
    final half = 13.0 + (streams - 1) * 3.5;
    final topHalf = half * 0.8;
    final top = -58.0 + recoil;
    final barrel = Path()
      ..moveTo(-half, -14)
      ..lineTo(-topHalf, top + 6)
      ..lineTo(topHalf, top + 6)
      ..lineTo(half, -14)
      ..close();
    _fill.shader = Gradient.linear(
      Offset(-half, 0),
      Offset(half, 0),
      [
        skin.bodyDark,
        shade(skin.body, 0.35),
        skin.body,
        shade(skin.bodyDark, -0.1),
      ],
      const [0, 0.32, 0.58, 1],
    );
    c.drawPath(barrel, _fill);
    _fill.shader = null;
    _stroke
      ..color = _outline
      ..strokeWidth = 2.6;
    c.drawPath(barrel, _stroke);

    // Specular streak.
    _fill.color = const Color(0x55FFFFFF);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-half * 0.55, top + 12, -half * 0.3, -20),
        const Radius.circular(3),
      ),
      _fill,
    );

    // Element core band (glows with the selected element).
    final bandY = -30.0 + recoil * 0.5;
    final bandHalf = half * 0.96;
    _fill.shader = Gradient.radial(Offset(0, bandY), half * 2.2, [
      coreColor.withValues(alpha: 0.55 + 0.3 * glowPulse),
      coreColor.withValues(alpha: 0),
    ]);
    c.drawCircle(Offset(0, bandY), half * 2.2, _fill);
    _fill.shader = null;
    final band = RRect.fromRectAndRadius(
      Rect.fromLTRB(-bandHalf, bandY - 4.5, bandHalf, bandY + 4.5),
      const Radius.circular(3),
    );
    _fill.color = coreColor;
    c.drawRRect(band, _fill);
    _fill.color = const Color(0x88FFFFFF);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-bandHalf + 3, bandY - 3, bandHalf * 0.2, bandY - 1),
        const Radius.circular(2),
      ),
      _fill,
    );
    c.drawRRect(band, _stroke);

    // Trim bands (gold from level 4).
    final trim = level >= 4
        ? const Color(0xFFFFC93D)
        : shade(skin.bodyDark, -0.15);
    for (final y in [top + 18, -19.0]) {
      final w = half - (y - -14) / (top + 6 - -14) * (half - topHalf);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(-w - 1.5, y - 2.5, w + 1.5, y + 2.5),
        const Radius.circular(2),
      );
      _fill.color = trim;
      c.drawRRect(r, _fill);
      _stroke.strokeWidth = 2;
      c.drawRRect(r, _stroke);
    }

    // Muzzle lip with bores.
    final lip = RRect.fromRectAndRadius(
      Rect.fromLTRB(-topHalf - 4, top, topHalf + 4, top + 8),
      const Radius.circular(4),
    );
    _fill.color = shade(skin.body, 0.45);
    c.drawRRect(lip, _fill);
    _stroke.strokeWidth = 2.4;
    c.drawRRect(lip, _stroke);
    _fill.color = _outline;
    for (var i = 0; i < streams; i++) {
      final ox = (i - (streams - 1) / 2) * 10.4;
      c.drawOval(
        Rect.fromCenter(center: Offset(ox, top + 2), width: 6, height: 3),
        _fill,
      );
    }
    if (muzzleFlash > 0) {
      final m = muzzleFlash.clamp(0.0, 1.0);
      _fill.shader = Gradient.radial(
        Offset(0, top - 4),
        16 * m + 4,
        [
          const Color(0xFFFFFFFF),
          coreColor.withValues(alpha: 0.8),
          coreColor.withValues(alpha: 0),
        ],
        const [0, 0.35, 1],
      );
      c.drawCircle(Offset(0, top - 4), 16 * m + 4, _fill);
      _fill.shader = null;
    }

    // Crest spikes at max level.
    if (level >= 5) {
      for (final s in const [-1.0, 1.0]) {
        final spike = Path()
          ..moveTo(s * half * 0.9, -26)
          ..lineTo(s * (half + 9), -34)
          ..lineTo(s * half * 0.95, -38)
          ..close();
        _fill.color = const Color(0xFFFFC93D);
        c.drawPath(spike, _fill);
        _stroke.strokeWidth = 1.8;
        c.drawPath(spike, _stroke);
      }
    }

    // Carriage.
    final carriage = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-24, -19, 24, -6),
      const Radius.circular(6),
    );
    _fill.shader = Gradient.linear(const Offset(0, -19), const Offset(0, -6), [
      shade(skin.carriage, 0.25),
      shade(skin.carriage, -0.2),
    ]);
    c.drawRRect(carriage, _fill);
    _fill.shader = null;
    _stroke.strokeWidth = 2.4;
    c.drawRRect(carriage, _stroke);
    if (level >= 2) {
      _fill.color = skin.accent;
      for (final s in const [-1.0, 1.0]) {
        c.drawCircle(Offset(s * 8, -12.5), 2.2, _fill);
      }
    }

    c.restore(); // tilt

    // Wheels (not tilted, so they stay on the ground).
    for (final s in const [-1.0, 1.0]) {
      _wheel(c, Offset(s * 22, -13), 13, wheelAngle, skin);
    }
    c.restore();
  }

  static void _wheel(
    Canvas c,
    Offset center,
    double r,
    double angle,
    CannonSkin skin,
  ) {
    _fill.color = const Color(0xFF2A2633);
    c.drawCircle(center, r, _fill);
    _fill.color = shade(skin.carriage, -0.1);
    c.drawCircle(center, r * 0.78, _fill);
    _stroke
      ..color = const Color(0xFF2A2633)
      ..strokeWidth = 2.6;
    for (var k = 0; k < 8; k++) {
      final a = angle + k * math.pi / 4;
      c.drawLine(
        center,
        center + Offset(math.cos(a), math.sin(a)) * (r * 0.78),
        _stroke,
      );
    }
    _stroke
      ..color = _outline
      ..strokeWidth = 2.4;
    c.drawCircle(center, r, _stroke);
    c.drawCircle(center, r * 0.78, _stroke..strokeWidth = 1.4);
    // Hub.
    _fill.shader = Gradient.radial(
      center.translate(-1.5, -1.5),
      r * 0.45,
      [shade(skin.accent, 0.5), skin.accent, shade(skin.accent, -0.35)],
      const [0, 0.5, 1],
    );
    c.drawCircle(center, r * 0.34, _fill);
    _fill.shader = null;
    _stroke.strokeWidth = 1.8;
    c.drawCircle(center, r * 0.34, _stroke);
  }
}
