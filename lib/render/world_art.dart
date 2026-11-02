import 'dart:math' as math;
import 'dart:ui';

import '../economy/catalog.dart';
import 'ball_art.dart';

/// Backdrop layers, back to front. Each scrolls at its own parallax rate.
enum WorldLayer { sky, clouds, far, mid, hills }

/// Procedural forge-world backdrop: a graded sky with a ringed sun and
/// horizon glow, drifting haze bands, flat-topped mesas, clusters of
/// hexagonal basalt columns, faceted foothills with crystal outcrops and a
/// forged-stone platform as the floor.
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
        _sky(canvas, size, groundTop, t);
      case WorldLayer.clouds:
        _haze(canvas, size, groundTop, t);
      case WorldLayer.far:
        _mesas(canvas, size, groundTop, t);
      case WorldLayer.mid:
        _basalt(canvas, size, groundTop, t);
      case WorldLayer.hills:
        _foothills(canvas, size, groundTop, t);
    }
  }

  static double _left(Size s) => -s.width * overscan;
  static double _right(Size s) => s.width * (1 + overscan);

  static void _sky(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final rect = Rect.fromLTRB(_left(s), -2, _right(s), s.height + 2);
    c.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          Offset(0, groundTop),
          [t.skyTop, Color.lerp(t.skyTop, t.skyBottom, 0.55)!, t.skyBottom],
          const [0, 0.55, 1],
        ),
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
                    .withValues(alpha: 0.16)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
        );
      }
    }

    // Warm glow along the horizon, as if the world's forges were lit.
    final glowC = Offset(s.width * 0.5, groundTop);
    final glowR = s.width * 0.95;
    c.save();
    c.translate(glowC.dx, glowC.dy);
    c.scale(1, 0.45);
    c.drawCircle(
      Offset.zero,
      glowR,
      Paint()
        ..shader = Gradient.radial(Offset.zero, glowR, [
          t.sun.withValues(alpha: 0.42),
          t.sun.withValues(alpha: 0),
        ]),
    );
    c.restore();

    // A ringed sun with faint rays.
    final sunC = Offset(s.width * 0.76, s.height * 0.14);
    final r = s.width * 0.075;
    final rays = Paint()..color = t.sun.withValues(alpha: 0.06);
    for (var i = 0; i < 7; i++) {
      final a = math.pi * 0.55 + i * math.pi / 11;
      final spread = 0.035;
      final far = s.height * 1.2;
      c.drawPath(
        Path()..addPolygon([
          sunC,
          sunC + Offset(math.cos(a - spread), math.sin(a - spread)) * far,
          sunC + Offset(math.cos(a + spread), math.sin(a + spread)) * far,
        ], true),
        rays,
      );
    }
    c.drawCircle(
      sunC,
      r * 3.4,
      Paint()
        ..shader = Gradient.radial(sunC, r * 3.4, [
          t.sun.withValues(alpha: 0.5),
          t.sun.withValues(alpha: 0),
        ]),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.05);
    for (final (k, a) in const [(1.45, 0.32), (1.85, 0.18)]) {
      ring.color = t.sun.withValues(alpha: a);
      c.drawCircle(sunC, r * k, ring);
    }
    c.drawCircle(
      sunC,
      r,
      Paint()
        ..shader = Gradient.radial(
          sunC.translate(-r * 0.3, -r * 0.3),
          r * 1.3,
          [Color.lerp(t.sun, const Color(0xFFFFFFFF), 0.6)!, t.sun],
        ),
    );
  }

  /// Long, soft stratus bands instead of cartoon puff clouds.
  static void _haze(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final rng = math.Random(21);
    final width = _right(s) - _left(s);
    final p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final lit = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < 4; i++) {
      final w = width * (0.35 + rng.nextDouble() * 0.3);
      final x = _left(s) + rng.nextDouble() * (width - w);
      final y = groundTop * (0.14 + i * 0.15 + rng.nextDouble() * 0.06);
      final h = s.height * (0.014 + rng.nextDouble() * 0.01);
      final band = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(h),
      );
      p.color = t.cloud.withValues(alpha: 0.26 + rng.nextDouble() * 0.12);
      c.drawRRect(band, p);
      // Sunlit upper edge.
      lit.color = Color.lerp(
        t.cloud,
        const Color(0xFFFFFFFF),
        0.5,
      )!.withValues(alpha: 0.28);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + w * 0.12, y, w * 0.6, h * 0.35),
          Radius.circular(h),
        ),
        lit,
      );
    }
  }

  /// Distant flat-topped buttes with strata lines.
  static void _mesas(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final rng = math.Random(31);
    final h = s.height;
    final base = groundTop - h * 0.015;
    final color = t.farMountain;
    final light = shade(color, 0.16);
    final dark = shade(color, -0.06);
    final width = _right(s) - _left(s);
    const count = 6;
    final strata = Paint()
      ..color = shade(color, 0.28).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, h * 0.002);
    final shapes = <(double, double, double, double)>[];
    for (var i = 0; i < count; i++) {
      final px = _left(s) + (i + 0.15 + rng.nextDouble() * 0.7) * width / count;
      final ph = h * (0.12 + rng.nextDouble() * 0.14);
      final top = width / count * (0.25 + rng.nextDouble() * 0.3);
      final foot = top + width / count * (0.35 + rng.nextDouble() * 0.25);
      shapes.add((px, ph, top, foot));
    }
    shapes.sort((a, b) => b.$2.compareTo(a.$2));
    final fill = Paint();
    for (final (px, ph, top, foot) in shapes) {
      final y = base - ph;
      final ledge = ph * 0.12;
      final body = Path()
        ..addPolygon([
          Offset(px - foot, base),
          Offset(px - top * 1.08, y + ledge),
          Offset(px - top, y),
          Offset(px + top, y),
          Offset(px + top * 1.08, y + ledge),
          Offset(px + foot, base),
        ], true);
      fill.color = dark;
      c.drawPath(body, fill);
      // Sunlit right face.
      fill.color = light;
      c.drawPath(
        Path()..addPolygon([
          Offset(px + top * 0.25, y),
          Offset(px + top, y),
          Offset(px + top * 1.08, y + ledge),
          Offset(px + foot, base),
          Offset(px + foot * 0.35, base),
        ], true),
        fill,
      );
      // Rim light on the flat top.
      c.drawLine(
        Offset(px - top, y),
        Offset(px + top, y),
        Paint()
          ..color = t.snow.withValues(alpha: 0.7)
          ..strokeWidth = math.max(1.2, h * 0.003),
      );
      c.save();
      c.clipPath(body);
      for (var k = 1; k <= 3; k++) {
        final sy = y + ph * (0.22 + k * 0.17);
        c.drawLine(Offset(px - foot, sy), Offset(px + foot, sy), strata);
      }
      c.restore();
    }
    fill.color = dark;
    c.drawRect(
      Rect.fromLTRB(_left(s), base - 1, _right(s), base + h * 0.3),
      fill,
    );
    // Atmospheric haze over the far range.
    c.drawRect(
      Rect.fromLTRB(_left(s), base - h * 0.3, _right(s), base + 2),
      Paint()
        ..shader = Gradient.linear(Offset(0, base - h * 0.3), Offset(0, base), [
          t.skyBottom.withValues(alpha: 0),
          t.skyBottom.withValues(alpha: 0.4),
        ]),
    );
  }

  /// Clusters of hexagonal basalt columns, the signature landform.
  static void _basalt(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final rng = math.Random(47);
    final h = s.height;
    final base = groundTop;
    final color = t.midMountain;
    final width = _right(s) - _left(s);
    final cw = math.max(9.0, s.width * 0.034);
    final side = Paint();
    final face = Paint();
    final cap = Paint();
    final edge = Paint()
      ..color = shade(color, -0.4).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    var x = _left(s) + rng.nextDouble() * cw * 4;
    while (x < _right(s)) {
      final n = 3 + rng.nextInt(5);
      final peak = h * (0.06 + rng.nextDouble() * 0.1);
      for (var i = 0; i < n; i++) {
        // Tallest in the middle of the cluster, stepping down at the sides.
        final centre = 1 - ((i - (n - 1) / 2).abs() / ((n + 1) / 2));
        final ch =
            peak * (0.45 + 0.55 * centre) * (0.85 + rng.nextDouble() * 0.3);
        final cx = x + i * cw;
        final top = base - ch;
        final capH = cw * 0.32;
        side.color = shade(color, -0.12);
        c.drawRect(Rect.fromLTRB(cx, top, cx + cw, base + 2), side);
        face.color = shade(color, 0.06);
        c.drawRect(Rect.fromLTRB(cx, top, cx + cw * 0.45, base + 2), face);
        c.drawLine(Offset(cx, top), Offset(cx, base), edge);
        // Hexagonal top face, lit by the sky.
        cap.color = Color.lerp(t.snow, color, 0.45)!;
        c.drawPath(
          Path()..addPolygon([
            Offset(cx, top),
            Offset(cx + cw * 0.25, top - capH / 2),
            Offset(cx + cw * 0.75, top - capH / 2),
            Offset(cx + cw, top),
            Offset(cx + cw * 0.75, top + capH / 2),
            Offset(cx + cw * 0.25, top + capH / 2),
          ], true),
          cap,
        );
      }
      x += n * cw + width * (0.04 + rng.nextDouble() * 0.12);
    }
    // Rubble line tying the clusters to the ground.
    side.color = shade(color, -0.2);
    c.drawRect(
      Rect.fromLTRB(_left(s), base - h * 0.012, _right(s), base + h * 0.3),
      side,
    );
  }

  /// Low faceted foothills dotted with crystal outcrops.
  static void _foothills(Canvas c, Size s, double groundTop, ArenaTheme t) {
    final h = s.height;
    for (var band = 0; band < 2; band++) {
      final rng = math.Random(61 + band);
      final y0 = groundTop - h * (band == 0 ? 0.05 : 0.022);
      final amp = h * (band == 0 ? 0.022 : 0.016);
      final pts = <Offset>[
        Offset(_left(s), groundTop + 4),
        Offset(_left(s), y0),
      ];
      final segs = 9;
      final seg = (_right(s) - _left(s)) / segs;
      for (var i = 1; i <= segs; i++) {
        pts.add(Offset(_left(s) + seg * i, y0 - amp * rng.nextDouble()));
      }
      pts.add(Offset(_right(s), groundTop + 4));
      final color = band == 0 ? shade(t.hill, 0.1) : shade(t.hill, -0.04);
      final path = Path()..addPolygon(pts, true);
      c.drawPath(
        path,
        Paint()
          ..shader = Gradient.linear(
            Offset(0, y0 - amp),
            Offset(0, groundTop),
            [color, shade(color, -0.22)],
          ),
      );
      // Facet edges catching the light.
      final facet = Paint()
        ..color = shade(color, 0.22).withValues(alpha: 0.55)
        ..strokeWidth = 1;
      for (var i = 2; i < pts.length - 1; i++) {
        c.drawLine(pts[i], Offset(pts[i].dx + seg * 0.2, groundTop), facet);
      }
      if (band == 1) {
        for (var i = 0; i < 6; i++) {
          final cx =
              _left(s) + (_right(s) - _left(s)) * (i + rng.nextDouble()) / 6;
          _outcrop(c, Offset(cx, y0 + h * 0.01), h * 0.02, t);
        }
      }
    }
  }

  static void _outcrop(Canvas c, Offset at, double size, ArenaTheme t) {
    final dark = Paint()..color = shade(t.hill, -0.35);
    final lit = Paint()..color = Color.lerp(t.snow, t.hill, 0.35)!;
    for (final (dx, hgt, w) in const [
      (-0.55, 0.9, 0.35),
      (0.0, 1.5, 0.42),
      (0.5, 1.1, 0.34),
    ]) {
      final b = at.translate(dx * size, 0);
      final tip = b.translate(dx * size * 0.2, -hgt * size);
      c.drawPath(
        Path()..addPolygon([
          b.translate(-w * size, 0),
          tip,
          b.translate(w * size, 0),
        ], true),
        dark,
      );
      c.drawPath(
        Path()..addPolygon([b.translate(-w * size, 0), tip, b], true),
        lit,
      );
    }
  }

  /// The forged-stone platform (also the gameplay floor): a brass rim, a
  /// glowing seam and riveted plates. Tinted by the theme's ground colour.
  static void paintGround(Canvas c, Rect rect, ArenaTheme t) {
    final stone = Color.lerp(t.ground, const Color(0xFF2A2840), 0.62)!;
    final stoneDark = Color.lerp(t.groundDark, const Color(0xFF12111E), 0.72)!;
    c.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [stone, stoneDark],
          const [0.1, 1],
        ),
    );
    final rim = (rect.height * 0.07).clamp(4.0, 9.0);
    final brass = Color.lerp(t.ground, const Color(0xFFE2B15C), 0.6)!;
    // Brass rim.
    c.drawRect(
      Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + rim),
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          Offset(rect.center.dx, rect.top + rim),
          [shade(brass, 0.35), brass, shade(brass, -0.35)],
          const [0, 0.35, 1],
        ),
    );
    c.drawLine(
      rect.topLeft,
      rect.topRight,
      Paint()
        ..color = const Color(0x8CFFFFFF)
        ..strokeWidth = 1.2,
    );
    // Ember seam just under the rim.
    final seamY = rect.top + rim + 2.5;
    c.drawLine(
      Offset(rect.left, seamY),
      Offset(rect.right, seamY),
      Paint()
        ..color = Color.lerp(
          t.sun,
          const Color(0xFFFF7A2B),
          0.6,
        )!.withValues(alpha: 0.75)
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // Riveted plates.
    final plateTop = seamY + 3;
    final plateH = math.min(rect.height * 0.32, rim * 5);
    final plateW = plateH * 2.4;
    final seam = Paint()
      ..color = stoneDark.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    final bevel = Paint()
      ..color = shade(stone, 0.18).withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final rivet = Paint()..color = shade(brass, -0.15).withValues(alpha: 0.85);
    for (var row = 0; row < 2; row++) {
      final y = plateTop + row * plateH;
      final offset = row.isOdd ? plateW / 2 : 0.0;
      c.drawLine(Offset(rect.left, y), Offset(rect.right, y), bevel);
      for (var x = rect.left - offset; x < rect.right; x += plateW) {
        c.drawLine(Offset(x, y), Offset(x, y + plateH), seam);
        c.drawCircle(Offset(x + 5, y + 4), 1.3, rivet);
        c.drawCircle(Offset(x + plateW - 5, y + 4), 1.3, rivet);
      }
    }
    // Shade the lower area so the HUD buttons sit on calm ground.
    c.drawRect(
      Rect.fromLTRB(rect.left, plateTop + plateH, rect.right, rect.bottom),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, plateTop + plateH),
          rect.bottomCenter,
          [stoneDark.withValues(alpha: 0), stoneDark.withValues(alpha: 0.85)],
        ),
    );
  }
}
