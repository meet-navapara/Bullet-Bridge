import 'dart:math' as math;
import 'dart:ui';

import '../economy/catalog.dart';
import 'ball_art.dart';

/// Backdrop layers, back to front. Each scrolls at its own parallax rate.
enum WorldLayer { sky, clouds, far, mid, hills }

/// Procedural illustrated world: sky, sun, clouds, low-poly mountains with
/// snow caps, a pine ridge, rolling hills and a grass ground band.
///
/// Every layer is a pure function of (size, groundTop, theme), so the game
/// records each one into a Picture once and replays it with an offset.
abstract final class WorldArt {
  /// Horizontal parallax factor per layer (fraction of cannon offset).
  static const Map<WorldLayer, double> parallax = {
    WorldLayer.sky: 0,
    WorldLayer.clouds: 0.04,
    WorldLayer.far: 0.08,
    WorldLayer.mid: 0.16,
    WorldLayer.hills: 0.28,
  };

  /// Extra width painted on each side so parallax never shows an edge.
  static const double overscan = 0.12;

  /// Paints all layers without parallax (menus, previews).
  static void paintScene(
    Canvas canvas,
    Size size,
    ArenaTheme theme, {
    double? groundTop,
    bool ground = true,
  }) {
    final gTop = groundTop ?? size.height * 0.8;
    for (final layer in WorldLayer.values) {
      paintLayer(canvas, layer, size, gTop, theme);
    }
    if (ground) {
      paintGround(
        canvas,
        Rect.fromLTRB(-4, gTop, size.width + 4, size.height + 4),
        theme,
      );
    }
  }

  static void paintLayer(
    Canvas canvas,
    WorldLayer layer,
    Size size,
    double groundTop,
    ArenaTheme t,
  ) {
    switch (layer) {
      case WorldLayer.sky:
        _sky(canvas, size, t);
      case WorldLayer.clouds:
        _clouds(canvas, size, t);
      case WorldLayer.far:
        _mountains(canvas, size, groundTop, t, far: true);
      case WorldLayer.mid:
        _mountains(canvas, size, groundTop, t, far: false);
      case WorldLayer.hills:
        _hills(canvas, size, groundTop, t);
    }
  }

  static double _left(Size s) => -s.width * overscan;
  static double _right(Size s) => s.width * (1 + overscan);

  static void _sky(Canvas c, Size s, ArenaTheme t) {
    final rect = Rect.fromLTRB(_left(s), -2, _right(s), s.height + 2);
    c.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(rect.topCenter, Offset(0, s.height * 0.75), [
          t.skyTop,
          t.skyBottom,
        ]),
    );
    if (t.stars) {
      final rng = math.Random(11);
      final p = Paint();
      for (var i = 0; i < 90; i++) {
        p.color = Color.fromRGBO(255, 255, 255, 0.3 + rng.nextDouble() * 0.6);
        c.drawCircle(
          Offset(
            _left(s) + rng.nextDouble() * (_right(s) - _left(s)),
            rng.nextDouble() * s.height * 0.5,
          ),
          0.6 + rng.nextDouble() * 1.4,
          p,
        );
      }
      // Aurora ribbons.
      for (var band = 0; band < 2; band++) {
        final path = Path();
        final y0 = s.height * (0.16 + band * 0.08);
        path.moveTo(_left(s), y0);
        for (var x = _left(s); x <= _right(s); x += s.width / 8) {
          path.lineTo(
            x,
            y0 + math.sin(x / s.width * 5 + band) * s.height * 0.03,
          );
        }
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.height * 0.05
            ..color =
                (band == 0 ? const Color(0xFF5CFFB0) : const Color(0xFF7A9CFF))
                    .withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
        );
      }
    }
    // Sun (or moon) with a soft halo.
    final sunC = Offset(s.width * 0.8, s.height * 0.13);
    final r = s.width * 0.09;
    c.drawCircle(
      sunC,
      r * 3.2,
      Paint()
        ..shader = Gradient.radial(sunC, r * 3.2, [
          t.sun.withValues(alpha: 0.55),
          t.sun.withValues(alpha: 0),
        ]),
    );
    c.drawCircle(sunC, r, Paint()..color = t.sun);
  }

  static void _clouds(Canvas c, Size s, ArenaTheme t) {
    final rng = math.Random(21);
    final body = Paint()..color = t.cloud.withValues(alpha: 0.95);
    final shadow = Paint()
      ..color = shade(t.cloud, -0.12).withValues(alpha: 0.9);
    final count = 6;
    for (var i = 0; i < count; i++) {
      final cx =
          _left(s) +
          (i + rng.nextDouble() * 0.6) * (_right(s) - _left(s)) / count;
      final cy = s.height * (0.08 + rng.nextDouble() * 0.3);
      final w = s.width * (0.16 + rng.nextDouble() * 0.14);
      final puffs = 4 + rng.nextInt(3);
      final cloud = Path();
      for (var p = 0; p < puffs; p++) {
        final px = cx - w / 2 + w * (p + 0.5) / puffs;
        final pr =
            w * (0.14 + rng.nextDouble() * 0.1) * (p == puffs ~/ 2 ? 1.35 : 1);
        cloud.addOval(
          Rect.fromCircle(center: Offset(px, cy - pr * 0.3), radius: pr),
        );
      }
      cloud.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - w / 2, cy - w * 0.08, w, w * 0.16),
          Radius.circular(w * 0.08),
        ),
      );
      c.save();
      c.translate(0, w * 0.035);
      c.drawPath(cloud, shadow);
      c.restore();
      c.drawPath(cloud, body);
    }
  }

  static void _mountains(
    Canvas c,
    Size s,
    double groundTop,
    ArenaTheme t, {
    required bool far,
  }) {
    final rng = math.Random(far ? 31 : 47);
    final h = s.height;
    final base = groundTop - h * (far ? 0.02 : 0.0);
    final color = far ? t.farMountain : t.midMountain;
    final light = shade(color, 0.22);
    final dark = shade(color, -0.12);
    final width = _right(s) - _left(s);
    final peaks = far ? 7 : 9;
    final shapes = <(double, double, double)>[];
    for (var i = 0; i < peaks; i++) {
      final px = _left(s) + (i + 0.2 + rng.nextDouble() * 0.6) * width / peaks;
      final ph =
          h *
          (far ? 0.2 + rng.nextDouble() * 0.12 : 0.1 + rng.nextDouble() * 0.08);
      final hw =
          width /
          peaks *
          (far ? 0.95 + rng.nextDouble() * 0.5 : 0.8 + rng.nextDouble() * 0.4);
      shapes.add((px, ph, hw));
    }
    // Taller peaks behind shorter ones.
    shapes.sort((a, b) => b.$2.compareTo(a.$2));
    final fill = Paint();
    for (final (px, ph, hw) in shapes) {
      final top = Offset(px, base - ph);
      final l = Offset(px - hw, base);
      final r = Offset(px + hw, base);
      fill.color = dark;
      c.drawPath(Path()..addPolygon([l, top, r], true), fill);
      fill.color = light;
      final ridge = Offset(px + hw * 0.12, base);
      c.drawPath(Path()..addPolygon([l, top, ridge], true), fill);
      if (far || ph > h * 0.15) {
        _snowCap(c, top, hw, ph, t, rng);
      }
    }
    // Ridge band filling below the peaks.
    fill.color = dark;
    c.drawRect(
      Rect.fromLTRB(_left(s), base - 2, _right(s), base + h * 0.3),
      fill,
    );
    if (!far) _pines(c, s, base, t, rng);
  }

  static void _snowCap(
    Canvas c,
    Offset top,
    double hw,
    double ph,
    ArenaTheme t,
    math.Random rng,
  ) {
    final depth = ph * (0.26 + rng.nextDouble() * 0.08);
    final slope = hw / ph;
    final path = Path()..moveTo(top.dx, top.dy);
    final leftX = top.dx - depth * slope;
    final rightX = top.dx + depth * slope;
    final y = top.dy + depth;
    path.lineTo(rightX, y);
    // Jagged lower edge.
    const teeth = 5;
    for (var i = 1; i <= teeth; i++) {
      final x = rightX - (rightX - leftX) * i / teeth;
      final jag = (i.isOdd ? -1 : 1) * depth * 0.18;
      path.lineTo(x, y + jag);
    }
    path.close();
    c.drawPath(path, Paint()..color = shade(t.snow, -0.08));
    c.save();
    c.clipRect(
      Rect.fromLTRB(leftX - 2, top.dy - 2, top.dx + hw * 0.05, y + depth),
    );
    c.drawPath(path, Paint()..color = t.snow);
    c.restore();
  }

  static void _pines(
    Canvas c,
    Size s,
    double base,
    ArenaTheme t,
    math.Random rng,
  ) {
    final tree = Paint()..color = shade(t.midMountain, -0.35);
    final treeLight = Paint()..color = shade(t.midMountain, -0.22);
    final n = (s.width / 9).round();
    for (var i = 0; i < n; i++) {
      final x = _left(s) + (_right(s) - _left(s)) * (i + rng.nextDouble()) / n;
      final hgt = s.height * (0.03 + rng.nextDouble() * 0.04);
      final w = hgt * 0.42;
      final y = base + s.height * 0.01;
      for (var tier = 0; tier < 2; tier++) {
        final ty = y - hgt * tier * 0.45;
        final th = hgt * (1 - tier * 0.35);
        final p = Path()
          ..addPolygon([
            Offset(x - w * (1 - tier * 0.25), ty),
            Offset(x, ty - th),
            Offset(x + w * (1 - tier * 0.25), ty),
          ], true);
        c.drawPath(p, tier == 0 ? tree : treeLight);
      }
    }
  }

  static void _hills(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final h = s.height;
    for (var band = 0; band < 2; band++) {
      final rng = math.Random(61 + band);
      final y0 = groundTop - h * (band == 0 ? 0.075 : 0.035);
      final amp = h * (band == 0 ? 0.03 : 0.022);
      final path = Path()..moveTo(_left(s), groundTop + 4);
      path.lineTo(_left(s), y0);
      final segs = 5;
      final seg = (_right(s) - _left(s)) / segs;
      var x = _left(s);
      for (var i = 0; i < segs; i++) {
        final cx = x + seg / 2;
        final cy = y0 - amp * (0.4 + rng.nextDouble());
        path.quadraticBezierTo(
          cx,
          cy,
          x + seg,
          y0 + amp * (rng.nextDouble() - 0.5) * 0.6,
        );
        x += seg;
      }
      path.lineTo(_right(s), groundTop + 4);
      path.close();
      final color = band == 0 ? shade(t.hill, 0.18) : t.hill;
      c.drawPath(
        path,
        Paint()
          ..shader = Gradient.linear(
            Offset(0, y0 - amp),
            Offset(0, groundTop),
            [color, shade(color, -0.12)],
          ),
      );
      if (band == 1) {
        // Little trees dotting the front hill.
        final dot = Paint()..color = shade(t.hill, -0.3);
        for (var i = 0; i < 7; i++) {
          final tx =
              _left(s) + (_right(s) - _left(s)) * (i + rng.nextDouble()) / 7;
          final ty = y0 + h * 0.012;
          c.drawCircle(Offset(tx, ty), h * 0.011, dot);
          c.drawCircle(Offset(tx + h * 0.012, ty + h * 0.003), h * 0.008, dot);
        }
      }
    }
  }

  /// The foreground grass band (also the gameplay floor).
  static void paintGround(Canvas c, Rect rect, ArenaTheme t) {
    c.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [t.ground, t.groundDark],
          const [0.15, 1],
        ),
    );
    final lip = (rect.height * 0.08).clamp(4.0, 10.0);
    // Light grass lip with a scalloped edge.
    final lipPath = Path()..moveTo(rect.left, rect.top + lip);
    final step = lip * 2.2;
    for (var x = rect.left; x < rect.right; x += step) {
      lipPath.quadraticBezierTo(
        x + step / 2,
        rect.top - lip * 0.35,
        x + step,
        rect.top + lip * 0.2,
      );
    }
    lipPath
      ..lineTo(rect.right, rect.top + lip)
      ..close();
    c.drawPath(lipPath, Paint()..color = shade(t.ground, 0.28));
    // Soft horizontal stripes like mown grass.
    final stripe = Paint()
      ..color = shade(t.ground, 0.18).withValues(alpha: 0.35);
    final rng = math.Random(77);
    for (var i = 0; i < 6; i++) {
      final y = rect.top + rect.height * (0.18 + i * 0.13);
      final x = rect.left + rng.nextDouble() * rect.width * 0.5;
      final w = rect.width * (0.25 + rng.nextDouble() * 0.35);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, lip * 0.9),
          Radius.circular(lip),
        ),
        stripe,
      );
    }
    // Grass tufts.
    final tuft = Paint()
      ..color = shade(t.ground, -0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, lip * 0.25)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 14; i++) {
      final x = rect.left + rect.width * rng.nextDouble();
      final y = rect.top + rect.height * (0.25 + rng.nextDouble() * 0.6);
      final hgt = lip * (0.8 + rng.nextDouble());
      c.drawLine(Offset(x, y), Offset(x - hgt * 0.4, y - hgt), tuft);
      c.drawLine(Offset(x, y), Offset(x, y - hgt * 1.2), tuft);
      c.drawLine(Offset(x, y), Offset(x + hgt * 0.4, y - hgt), tuft);
    }
  }
}
