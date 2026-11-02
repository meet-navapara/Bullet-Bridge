import 'dart:math' as math;
import 'dart:ui';

import '../economy/catalog.dart';
import '../economy/upgrades.dart';
import 'ball_art.dart';

/// The Forge Strider: a hovering turret drawn in world units with its base
/// at (0, 0) and the emitter pointing up. An armoured hull rides on two
/// ember thrusters; curved shoulder plates cradle a glowing element core,
/// and twin rails above it fire the bolts. ~66 wide, ~58 tall, the same
/// envelope the simulation's hitbox was sized for.
abstract final class CannonArt {
  static const _ink = Color(0xFF151A33);
  static final Paint _fill = Paint()..isAntiAlias = true;
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// [wheelAngle] is the distance travelled (kept under its old name); the
  /// thruster flames flicker with it.
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

    final streams = Upgrades.streams(level);
    final coreColor = core ?? skin.glow;
    final flicker = 0.8 + 0.2 * math.sin(wheelAngle * 2.3 + glowPulse * 3);

    // Ground shadow and the thrusters' warm light on the floor.
    _fill.color = const Color(0x40000000);
    c.drawOval(const Rect.fromLTRB(-30, -3.5, 30, 3.5), _fill);
    _fill.shader = Gradient.radial(const Offset(0, -1), 30, [
      skin.glow.withValues(alpha: 0.32 + 0.12 * glowPulse),
      skin.glow.withValues(alpha: 0),
    ]);
    c.drawOval(const Rect.fromLTRB(-34, -7, 34, 5), _fill);
    _fill.shader = null;

    c.save();
    c.rotate(tilt);

    _thrusters(c, skin, flicker);
    _rails(c, skin, level, streams, recoil, coreColor, muzzleFlash);
    _hull(c, skin, level);
    _shoulders(c, skin, level);
    _core(c, skin, coreColor, glowPulse, recoil);

    c.restore(); // tilt
    c.restore();
  }

  static void _thrusters(Canvas c, CannonSkin skin, double flicker) {
    for (final s in const [-1.0, 1.0]) {
      final cx = s * 23;
      // Flame jet below the pod.
      final len = 9 * flicker;
      final jet = Path()
        ..moveTo(cx - 4.2, -7)
        ..quadraticBezierTo(cx - 3, -7 + len * 0.6, cx, -7 + len)
        ..quadraticBezierTo(cx + 3, -7 + len * 0.6, cx + 4.2, -7)
        ..close();
      _fill.shader = Gradient.linear(
        Offset(cx, -7),
        Offset(cx, -7 + len),
        [const Color(0xFFFFF4D0), skin.glow, skin.glow.withValues(alpha: 0)],
        const [0, 0.35, 1],
      );
      c.drawPath(jet, _fill);
      _fill.shader = null;

      // Pod.
      final pod = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - 7, -17, cx + 7, -6),
        const Radius.circular(5),
      );
      _fill.shader = Gradient.linear(
        Offset(cx - 7, 0),
        Offset(cx + 7, 0),
        [skin.bodyDark, shade(skin.body, 0.25), skin.bodyDark],
        const [0, 0.4, 1],
      );
      c.drawRRect(pod, _fill);
      _fill.shader = null;
      _stroke
        ..color = _ink
        ..strokeWidth = 1.6;
      c.drawRRect(pod, _stroke);
      // Nozzle ring.
      _fill.color = shade(skin.accent, -0.1);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - 5.5, -9, cx + 5.5, -6),
          const Radius.circular(1.5),
        ),
        _fill,
      );
    }
  }

  static void _rails(
    Canvas c,
    CannonSkin skin,
    int level,
    int streams,
    double recoil,
    Color coreColor,
    double muzzleFlash,
  ) {
    final top = -56.0 + recoil;
    final railX = 6.0 + (streams - 1) * 3.6;
    const railW = 4.6;

    // Energy channel between the rails.
    final channel = Rect.fromLTRB(-railX, top + 4, railX, -34);
    _fill.shader = Gradient.linear(channel.bottomCenter, channel.topCenter, [
      coreColor.withValues(alpha: 0.75),
      coreColor.withValues(alpha: 0.15),
    ]);
    c.drawRect(channel, _fill);
    _fill.shader = null;

    // Rails: tapered blades with a bright inner edge.
    for (final s in const [-1.0, 1.0]) {
      final inner = s * railX;
      final outer = s * (railX + railW);
      final blade = Path()
        ..moveTo(inner, -32)
        ..lineTo(inner, top + 1)
        ..lineTo(outer - s * 1.2, top + 4)
        ..lineTo(outer + s * 1.4, -32)
        ..close();
      _fill.shader = Gradient.linear(
        Offset(inner, 0),
        Offset(outer, 0),
        [shade(skin.body, 0.45), skin.body, skin.bodyDark],
        const [0, 0.35, 1],
      );
      c.drawPath(blade, _fill);
      _fill.shader = null;
      _stroke
        ..color = _ink
        ..strokeWidth = 1.6;
      c.drawPath(blade, _stroke);
    }

    // Brackets tying the rails together (brass from level 4).
    final trim = level >= 4 ? const Color(0xFFFFC24A) : shade(skin.body, -0.2);
    for (final y in [top + 9, -40.0]) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(-railX - railW - 1, y - 2, railX + railW + 1, y + 2),
        const Radius.circular(2),
      );
      _fill.color = trim;
      c.drawRRect(r, _fill);
      _stroke.strokeWidth = 1.3;
      c.drawRRect(r, _stroke);
    }

    // One glowing emitter per stream at the tip.
    for (var i = 0; i < streams; i++) {
      final ox = (i - (streams - 1) / 2) * 6.5;
      _fill.color = coreColor;
      c.drawCircle(Offset(ox, top + 4.5), 1.9, _fill);
      _fill.color = const Color(0xCCFFFFFF);
      c.drawCircle(Offset(ox, top + 4.2), 0.9, _fill);
    }

    if (muzzleFlash > 0) {
      final m = muzzleFlash.clamp(0.0, 1.0);
      final r = 15 * m + 4;
      _fill.shader = Gradient.radial(
        Offset(0, top - 2),
        r,
        [
          const Color(0xFFFFFFFF),
          coreColor.withValues(alpha: 0.85),
          coreColor.withValues(alpha: 0),
        ],
        const [0, 0.35, 1],
      );
      c.drawCircle(Offset(0, top - 2), r, _fill);
      _fill.shader = null;
    }
  }

  static void _hull(Canvas c, CannonSkin skin, int level) {
    final hull = Path()
      ..moveTo(-33, -12)
      ..lineTo(-27, -20)
      ..lineTo(27, -20)
      ..lineTo(33, -12)
      ..lineTo(25, -5)
      ..lineTo(-25, -5)
      ..close();
    _fill.shader = Gradient.linear(
      const Offset(0, -20),
      const Offset(0, -5),
      [shade(skin.carriage, 0.3), skin.carriage, shade(skin.carriage, -0.35)],
      const [0, 0.45, 1],
    );
    c.drawPath(hull, _fill);
    _fill.shader = null;
    // Lit top edge.
    _stroke
      ..color = shade(skin.carriage, 0.55).withValues(alpha: 0.9)
      ..strokeWidth = 1.4;
    c.drawLine(const Offset(-26, -18.6), const Offset(26, -18.6), _stroke);
    // Panel seams.
    _stroke
      ..color = shade(skin.carriage, -0.45).withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final sx in const [-12.0, 12.0]) {
      c.drawLine(Offset(sx, -18), Offset(sx * 1.1, -6.5), _stroke);
    }
    _stroke
      ..color = _ink
      ..strokeWidth = 1.8;
    c.drawPath(hull, _stroke);

    if (level >= 2) {
      for (final s in const [-1.0, 1.0]) {
        _fill.color = skin.accent;
        c.drawCircle(Offset(s * 19, -12.5), 1.9, _fill);
        _fill.color = const Color(0x99FFFFFF);
        c.drawCircle(Offset(s * 19 - 0.5, -13), 0.7, _fill);
      }
    }
  }

  static void _shoulders(Canvas c, CannonSkin skin, int level) {
    for (final s in const [-1.0, 1.0]) {
      // A crescent plate wrapping the core.
      final plate = Path()
        ..moveTo(s * 9, -19)
        ..quadraticBezierTo(s * 21, -21, s * 20, -29)
        ..quadraticBezierTo(s * 18, -35, s * 10, -37)
        ..quadraticBezierTo(s * 14, -30, s * 12, -24)
        ..quadraticBezierTo(s * 11, -20, s * 9, -19)
        ..close();
      _fill.shader = Gradient.linear(
        Offset(s * 9, -37),
        Offset(s * 21, -20),
        [shade(skin.body, 0.4), skin.body, skin.bodyDark],
        const [0, 0.4, 1],
      );
      c.drawPath(plate, _fill);
      _fill.shader = null;
      _stroke
        ..color = _ink
        ..strokeWidth = 1.6;
      c.drawPath(plate, _stroke);

      // Brass fins on a fully upgraded turret.
      if (level >= 5) {
        final fin = Path()
          ..moveTo(s * 18, -31)
          ..lineTo(s * 27, -37)
          ..lineTo(s * 20, -25)
          ..close();
        _fill.color = const Color(0xFFFFC24A);
        c.drawPath(fin, _fill);
        _stroke.strokeWidth = 1.3;
        c.drawPath(fin, _stroke);
      }
    }
  }

  static void _core(
    Canvas c,
    CannonSkin skin,
    Color coreColor,
    double glowPulse,
    double recoil,
  ) {
    final center = Offset(0, -26 + recoil * 0.3);
    // Halo.
    _fill.shader = Gradient.radial(center, 22, [
      coreColor.withValues(alpha: 0.45 + 0.25 * glowPulse),
      coreColor.withValues(alpha: 0),
    ]);
    c.drawCircle(center, 22, _fill);
    // Housing ring.
    _fill.shader = Gradient.linear(
      center.translate(0, -8.5),
      center.translate(0, 8.5),
      [shade(skin.body, 0.35), skin.bodyDark],
    );
    c.drawCircle(center, 8.5, _fill);
    _fill.shader = null;
    _stroke
      ..color = _ink
      ..strokeWidth = 1.6;
    c.drawCircle(center, 8.5, _stroke);
    // The element orb.
    _fill.shader = Gradient.radial(
      center.translate(-1.8, -2.2),
      7,
      [const Color(0xFFFFFFFF), shade(coreColor, 0.3), coreColor],
      const [0, 0.3, 1],
    );
    c.drawCircle(center, 5.8, _fill);
    _fill.shader = null;
    _fill.color = const Color(0xB3FFFFFF);
    c.drawOval(
      Rect.fromCenter(
        center: center.translate(-1.9, -2.8),
        width: 3,
        height: 1.7,
      ),
      _fill,
    );
  }
}
