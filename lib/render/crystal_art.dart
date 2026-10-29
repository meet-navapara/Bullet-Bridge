import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../config/balance.dart';
import '../config/bosses.dart';
import '../game/sim/boss.dart';
import '../game/sim/entities.dart';
import '../ui/theme/palette.dart';
import 'ball_art.dart';

part 'boss_art.dart';

/// Colours of each hazard kind.
Color hazardColor(HazardKind k) => switch (k) {
  HazardKind.blaze => const Color(0xFFFF6A2B),
  HazardKind.frost => const Color(0xFF5FD8FF),
  HazardKind.storm => const Color(0xFFB45CFF),
};

Color elementColor(Element e) => switch (e) {
  Element.kinetic => const Color(0xFFF2F6FF),
  Element.fire => const Color(0xFFFF7A2B),
  Element.ice => const Color(0xFF7FE6FF),
  Element.electric => const Color(0xFFFFE14A),
};

const _outline = Color(0xFF1C1830);
const _lightDir = Offset(-0.6, -0.8);

/// Pre-computed lighting for one gem colour.
class _GemPaints {
  _GemPaints(Color base, int facets) {
    for (var k = 0; k < facets; k++) {
      final mid = (k + 0.5) / facets * math.pi * 2 - math.pi / 2;
      final b = math.cos(mid) * _lightDir.dx + math.sin(mid) * _lightDir.dy;
      final t = (b + 1) / 2;
      facetPaints.add(
        Paint()..color = Color.lerp(shade(base, -0.42), shade(base, 0.38), t)!,
      );
    }
    table = Paint()..color = shade(base, 0.18);
    tableHi = Paint()..color = shade(base, 0.55);
  }
  final List<Paint> facetPaints = [];
  late final Paint table;
  late final Paint tableHi;
}

/// Unit-space gem geometry (outer ring + inner table) with slight
/// irregularity so every crystal does not look identical.
class _GemShape {
  _GemShape(int facets, int variant) {
    final rng = math.Random(variant * 97 + facets);
    final outerPts = <Offset>[];
    final innerPts = <Offset>[];
    for (var k = 0; k < facets; k++) {
      final a = k / facets * math.pi * 2 - math.pi / 2 + math.pi / facets;
      final r = 1 - rng.nextDouble() * 0.07;
      outerPts.add(Offset(math.cos(a) * r, math.sin(a) * r));
      innerPts.add(
        Offset(math.cos(a) * 0.52 - 0.06, math.sin(a) * 0.52 - 0.08),
      );
    }
    outer = Path()..addPolygon(outerPts, true);
    inner = Path()..addPolygon(innerPts, true);
    for (var k = 0; k < facets; k++) {
      final n = (k + 1) % facets;
      facets_.add(
        Path()..addPolygon([
          outerPts[k],
          outerPts[n],
          innerPts[n],
          innerPts[k],
        ], true),
      );
    }
    sparkle = Path()
      ..addPolygon([
        innerPts[facets - 1],
        Offset.lerp(innerPts[facets - 1], innerPts[0], 0.6)!,
        Offset.lerp(innerPts[facets - 1], const Offset(-0.06, -0.08), 0.5)!,
      ], true);
  }
  late final Path outer;
  late final Path inner;
  late final Path sparkle;
  final List<Path> facets_ = [];
}

class CrystalArt {
  final Map<(int, int), _GemPaints> _paints = {};
  final Map<(int, int), _GemShape> _shapes = {};
  final Map<String, (TextPainter, TextPainter)> _labels = {};
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  final Paint _fill = Paint();

  _GemPaints _gemPaints(Color c, int facets) =>
      _paints.putIfAbsent((c.toARGB32(), facets), () => _GemPaints(c, facets));
  _GemShape _shape(int facets, int variant) => _shapes.putIfAbsent((
    facets,
    variant % 3,
  ), () => _GemShape(facets, variant % 3));

  // ------------------------------------------------------------ sprites
  //
  // Gem bodies and glows are rasterised once per (colour, size) and drawn as
  // images. Drawing ~15 paths plus a fresh gradient shader per crystal per
  // frame was the biggest cost of the creature pass.

  // Insertion-ordered: a hit moves the sprite to the end, so the first entry
  // is always the least recently used one.
  final Map<Object, ui.Image> _sprites = {};
  int _spriteBytes = 0;

  /// GPU texture budget for cached sprites. Large geodes are ~1 MB each at
  /// phone densities; evicting one old sprite at a time avoids both
  /// unbounded memory and the hitch of re-rasterising everything at once.
  static const int spriteBudgetBytes = 48 << 20;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.medium;
  double _pixelRatio = 3;

  /// Physical pixels per canvas unit; sprites are rasterised at this
  /// density so they stay sharp.
  double get pixelRatio => _pixelRatio;
  set pixelRatio(double value) {
    final v = value.clamp(1.0, 4.0);
    if ((v - _pixelRatio).abs() < 0.01) return;
    _pixelRatio = v;
    clearSprites();
  }

  void clearSprites() {
    for (final image in _sprites.values) {
      image.dispose();
    }
    _sprites.clear();
    _spriteBytes = 0;
  }

  void dispose() => clearSprites();

  int get spriteCount => _sprites.length;
  int get spriteBytes => _spriteBytes;

  /// Sprites rasterised so far (cache misses), for profiling.
  int spriteMisses = 0;

  /// Rasterises the shard sprites of every tier up front, so the first
  /// appearance of a new size or colour does not cost a frame mid-wave.
  void prewarm(List<double> radii, Color Function(int tier) colorFor) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (var tier = 0; tier < radii.length; tier++) {
      for (var variant = 0; variant < 3; variant++) {
        shard(
          c,
          x: 0,
          y: 0,
          r: radii[tier],
          color: colorFor(tier),
          text: '',
          variant: variant,
        );
      }
    }
    rec.endRecording().dispose();
  }

  ui.Image _sprite(Object key, double half, void Function(Canvas) paint) {
    final cached = _sprites.remove(key);
    if (cached != null) return _sprites[key] = cached;
    spriteMisses++;
    final px = math.max(1, (half * 2 * _pixelRatio).ceil());
    final bytes = px * px * 4;
    while (_sprites.isNotEmpty && _spriteBytes + bytes > spriteBudgetBytes) {
      final oldest = _sprites.keys.first;
      final image = _sprites.remove(oldest)!;
      _spriteBytes -= image.width * image.height * 4;
      image.dispose();
    }
    _spriteBytes += bytes;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..scale(px / (half * 2))
      ..translate(half, half);
    paint(c);
    final picture = rec.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    return _sprites[key] = image;
  }

  void _drawSprite(Canvas c, ui.Image image, double half, {double flash = 0}) {
    _spritePaint.colorFilter = flash > 0
        ? ColorFilter.mode(
            Color.fromRGBO(255, 255, 255, flash.clamp(0.0, 1.0)),
            BlendMode.srcATop,
          )
        : null;
    c.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTRB(-half, -half, half, half),
      _spritePaint,
    );
  }

  /// Soft radial glow of radius [r] around the origin.
  void _glow(Canvas c, double r, Color color, double alpha) {
    final image = _sprite(('glow', color.toARGB32(), r.round(), alpha), r, (g) {
      g.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, r, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
    });
    _drawSprite(c, image, r);
  }

  /// A faceted gem of radius [r] centred at the canvas origin.
  void _gem(
    Canvas c,
    double r,
    Color color, {
    int facets = 8,
    int variant = 0,
    double outlineWidth = 2.2,
    double flash = 0,
  }) {
    final half = r + outlineWidth + 1;
    final image = _sprite(
      ('gem', color.toARGB32(), facets, variant % 3, outlineWidth, r.round()),
      half,
      (g) => _paintGem(g, r, color, facets, variant, outlineWidth),
    );
    _drawSprite(c, image, half, flash: flash);
  }

  void _paintGem(
    Canvas c,
    double r,
    Color color,
    int facets,
    int variant,
    double outlineWidth,
  ) {
    final shape = _shape(facets, variant);
    final paints = _gemPaints(color, facets);
    c.save();
    c.scale(r);
    for (var k = 0; k < facets; k++) {
      c.drawPath(shape.facets_[k], paints.facetPaints[k]);
    }
    c.drawPath(shape.inner, paints.table);
    c.drawPath(shape.sparkle, paints.tableHi);
    _stroke
      ..color = _outline
      ..strokeWidth = outlineWidth / r;
    c.drawPath(shape.outer, _stroke);
    _stroke
      ..color = _outline.withValues(alpha: 0.35)
      ..strokeWidth = 1 / r;
    c.drawPath(shape.inner, _stroke);
    c.restore();
  }

  void label(
    Canvas c,
    String text,
    double size, {
    double dy = 0,
    Color color = const Color(0xFFFFFFFF),
  }) {
    final fontSize = (size * 2).roundToDouble() / 2;
    final key = '$text@$fontSize@${color.toARGB32()}';
    if (_labels.length > 500) _labels.clear();
    final painters = _labels.putIfAbsent(key, () {
      TextPainter make(Paint? stroke) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: TextStyles.display,
            fontSize: fontSize,
            height: 1,
            color: stroke == null ? color : null,
            foreground: stroke,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return (
        make(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, fontSize * 0.2)
            ..strokeJoin = StrokeJoin.round
            ..color = _outline,
        ),
        make(null),
      );
    });
    final (o, f) = painters;
    final off = Offset(-f.width / 2, dy - f.height / 2 + fontSize * 0.05);
    o.paint(c, off);
    f.paint(c, off);
  }

  static double labelScale(String text) => switch (text.length) {
    1 || 2 => 1.0,
    3 => 0.82,
    _ => 0.66,
  };

  // --------------------------------------------------------------- shards

  void shard(
    Canvas c, {
    required double x,
    required double y,
    required double r,
    required Color color,
    required String text,
    int variant = 0,
    double flash = 0,
    double squash = 0,
    bool frozen = false,
    bool chilled = false,
    double spin = 0,
  }) {
    c.save();
    // Hits make the crystal swell briefly; landings squash it.
    // Under steady fire a crystal is re-hit before the flash ends, so the
    // flash is squared (a sharp pulse) and kept light: the gem must keep
    // its colour instead of staying washed out.
    final pop = 1 + 0.04 * flash;
    final sx = (1 + 0.18 * squash) * pop;
    final sy = (1 - 0.18 * squash) * pop;
    c.translate(x, y + r * (1 - sy));
    _glow(c, r * 1.5, color, 0.3);
    c.save();
    c.scale(sx, sy);
    // The gem rolls as it travels; the number stays upright.
    c.rotate(spin);
    _gem(c, r, color, variant: variant, flash: flash * flash * 0.2);
    c.restore();
    label(c, text, r * 0.95 * labelScale(text));
    if (chilled && !frozen) {
      _stroke
        ..color = const Color(0xCC9BEBFF)
        ..strokeWidth = 2;
      c.drawCircle(Offset.zero, r * 1.08, _stroke);
    }
    if (frozen) _ice(c, r);
    c.restore();
  }

  void _ice(Canvas c, double r) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCircle(center: Offset.zero, radius: r * 1.18),
      Radius.circular(r * 0.35),
    );
    _fill.color = const Color(0x6699E6FF);
    c.drawRRect(rect, _fill);
    _stroke
      ..color = const Color(0xE6FFFFFF)
      ..strokeWidth = 2;
    c.drawRRect(rect, _stroke);
    _stroke.strokeWidth = 1.5;
    c.drawLine(Offset(-r * 0.8, -r * 0.5), Offset(-r * 0.4, -r * 0.9), _stroke);
    c.drawLine(
      Offset(-r * 0.85, -r * 0.1),
      Offset(-r * 0.6, -r * 0.35),
      _stroke,
    );
  }

  // --------------------------------------------------------------- geodes

  void geode(
    Canvas c, {
    required double x,
    required double y,
    required double r,
    required Color coreColor,
    required String text,
    required double armorFraction,
    int variant = 0,
    double flash = 0,
    double squash = 0,
    bool frozen = false,
    double spin = 0,
  }) {
    c.save();
    final pop = 1 + 0.04 * flash;
    final sx = (1 + 0.12 * squash) * pop;
    final sy = (1 - 0.12 * squash) * pop;
    c.translate(x, y + r * (1 - sy));
    c.save();
    c.scale(sx, sy);
    c.rotate(spin);
    final cracks = ((1 - armorFraction) * 4).floor();
    final half = r * 1.12 + 3;
    final image = _sprite(
      ('geode', coreColor.toARGB32(), variant % 4, cracks, r.round()),
      half,
      (g) => _paintGeode(g, r, coreColor, variant % 4, cracks),
    );
    _drawSprite(c, image, half, flash: flash * flash * 0.2);
    c.restore();
    label(c, text, r * 0.8 * labelScale(text), color: const Color(0xFFE9E2DA));
    if (frozen) _ice(c, r);
    c.restore();
  }

  void _paintGeode(
    Canvas c,
    double r,
    Color coreColor,
    int variant,
    int cracks,
  ) {
    final rng = math.Random(variant * 13 + 5);
    final pts = <Offset>[];
    for (var k = 0; k < 11; k++) {
      final a = k / 11 * math.pi * 2;
      final rr = r * (0.93 + rng.nextDouble() * 0.12);
      pts.add(Offset(math.cos(a) * rr, math.sin(a) * rr));
    }
    final rock = Path()..addPolygon(pts, true);
    _fill.shader = ui.Gradient.radial(
      Offset(-r * 0.35, -r * 0.4),
      r * 1.6,
      [
        const Color(0xFFB7A391),
        const Color(0xFF7A6656),
        const Color(0xFF4A3D35),
      ],
      const [0, 0.5, 1],
    );
    c.drawPath(rock, _fill);
    _fill.shader = null;
    // Darker rock facets.
    _fill.color = const Color(0x33000000);
    for (var k = 0; k < 4; k++) {
      final a = pts[k * 2 + 1];
      final b = pts[k * 2 + 2];
      c.drawPath(
        Path()..addPolygon([a, b, Offset.lerp(a, b, 0.5)! * 0.55], true),
        _fill,
      );
    }
    // Crystals poking through the shell.
    for (var k = 0; k < 3; k++) {
      final a = -math.pi / 2 + (k - 1) * 0.9;
      final base = Offset(math.cos(a) * r * 0.75, math.sin(a) * r * 0.75);
      final tip = Offset(math.cos(a) * r * 1.12, math.sin(a) * r * 1.12);
      final side = Offset(-math.sin(a), math.cos(a)) * (r * 0.14);
      _fill.color = shade(coreColor, 0.15);
      c.drawPath(
        Path()..addPolygon([base - side, tip, base + side], true),
        _fill,
      );
      _stroke
        ..color = _outline
        ..strokeWidth = 1.5;
      c.drawPath(
        Path()..addPolygon([base - side, tip, base + side], true),
        _stroke,
      );
    }
    // Cracks grow as the shell weakens.
    _stroke
      ..color = const Color(0xFF2A211C)
      ..strokeWidth = math.max(1.4, r * 0.06)
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < cracks; k++) {
      final a = k * 1.7 + 0.4;
      final p0 = Offset(math.cos(a) * r * 0.95, math.sin(a) * r * 0.95);
      final p1 = Offset(
        math.cos(a + 0.3) * r * 0.55,
        math.sin(a + 0.3) * r * 0.55,
      );
      final p2 = Offset(
        math.cos(a - 0.2) * r * 0.25,
        math.sin(a - 0.2) * r * 0.25,
      );
      c.drawPath(Path()..addPolygon([p0, p1, p2], false), _stroke);
    }
    _stroke
      ..color = _outline
      ..strokeWidth = 2.4;
    c.drawPath(rock, _stroke);
  }

  // -------------------------------------------------------------- skyrays

  void skyray(
    Canvas c, {
    required double x,
    required double y,
    required double r,
    required String text,
    required double phase,
    required double dropWarning,
    double flash = 0,
    bool frozen = false,
    double dir = 1,
  }) {
    const color = Color(0xFFE05CFF);
    c.save();
    c.translate(x, y);
    final flap = 0.55 + 0.45 * math.sin(phase * 3);
    // Wings.
    for (final s in const [-1.0, 1.0]) {
      final wing = Path()
        ..moveTo(s * r * 0.5, -r * 0.2)
        ..lineTo(s * r * 2.0, -r * 0.2 - r * 0.7 * flap)
        ..lineTo(s * r * 1.6, r * 0.25)
        ..lineTo(s * r * 0.5, r * 0.3)
        ..close();
      _fill.color = shade(color, s < 0 ? 0.25 : -0.1);
      c.drawPath(wing, _fill);
      _stroke
        ..color = _outline
        ..strokeWidth = 2;
      c.drawPath(wing, _stroke);
    }
    // Tail.
    final tail = Path()
      ..moveTo(-r * 0.2, r * 0.6)
      ..lineTo(0, r * 1.5)
      ..lineTo(r * 0.2, r * 0.6)
      ..close();
    _fill.color = shade(color, -0.25);
    c.drawPath(tail, _fill);
    c.drawPath(tail, _stroke);
    _gem(c, r, color, facets: 6, variant: 1, flash: flash * flash * 0.2);
    label(c, text, r * 0.9 * labelScale(text));
    if (dropWarning > 0) {
      final g = dropWarning.clamp(0.0, 1.0);
      _fill.shader = ui.Gradient.radial(Offset(0, r * 1.1), r * 0.9, [
        const Color(0xFFFFE0FF).withValues(alpha: g),
        const Color(0x00FF4DE0),
      ]);
      c.drawCircle(Offset(0, r * 1.1), r * 0.9, _fill);
      _fill.shader = null;
    }
    if (frozen) _ice(c, r * 1.2);
    c.restore();
  }

  // -------------------------------------------------------------- hazards

  void hazard(Canvas c, Hazard hz, double time) {
    final color = hazardColor(hz.kind);
    final bob = math.sin(time * 1.8 + hz.bobSeed) * 4;
    final r = hz.radius;
    c.save();
    c.translate(hz.x, hz.y + bob);
    final pulse = 0.75 + 0.25 * math.sin(time * 5 + hz.bobSeed);
    c.save();
    c.translate(0, -6);
    c.scale(0.8 + 0.2 * pulse);
    _glow(c, r * 2.6, color, 0.5);
    c.restore();
    // Floating rock islet with a grass top.
    final rock = Path()
      ..moveTo(-r * 1.3, r * 0.15)
      ..lineTo(r * 1.3, r * 0.15)
      ..lineTo(r * 0.7, r * 0.75)
      ..lineTo(r * 0.15, r * 1.35)
      ..lineTo(-r * 0.45, r * 0.85)
      ..close();
    _fill.color = const Color(0xFF7A5E4A);
    c.drawPath(rock, _fill);
    _stroke
      ..color = _outline
      ..strokeWidth = 2;
    c.drawPath(rock, _stroke);
    final grass = RRect.fromRectAndRadius(
      Rect.fromLTRB(-r * 1.38, -r * 0.05, r * 1.38, r * 0.3),
      Radius.circular(r * 0.15),
    );
    _fill.color = const Color(0xFF5CC94A);
    c.drawRRect(grass, _fill);
    c.drawRRect(grass, _stroke);
    // Crystal cluster.
    for (final (dx, h, tilt) in const [
      (-0.55, 1.2, -0.35),
      (0.55, 1.05, 0.35),
      (0.0, 1.75, 0.0),
    ]) {
      c.save();
      c.translate(dx * r, 0);
      c.rotate(tilt);
      final w = r * 0.42;
      final hh = r * h;
      final prism = Path()
        ..moveTo(-w, 0)
        ..lineTo(-w, -hh * 0.7)
        ..lineTo(0, -hh)
        ..lineTo(w, -hh * 0.7)
        ..lineTo(w, 0)
        ..close();
      _fill.color = shade(color, -0.15);
      c.drawPath(prism, _fill);
      _fill.color = shade(color, 0.35);
      c.drawPath(
        Path()..addPolygon([
          Offset(-w, 0),
          Offset(-w, -hh * 0.7),
          Offset(0, -hh),
          const Offset(0, 0),
        ], true),
        _fill,
      );
      if (hz.hitFlash > 0) {
        _fill.color = const Color(0x99FFFFFF);
        c.drawPath(prism, _fill);
      }
      c.drawPath(prism, _stroke);
      c.restore();
    }
    // Kind emblem flicker.
    switch (hz.kind) {
      case HazardKind.blaze:
        final f = 0.8 + 0.2 * math.sin(time * 14 + hz.bobSeed);
        _fill.color = const Color(0xFFFFD23F);
        c.drawPath(_flame(Offset(0, -r * 1.9), r * 0.45 * f), _fill);
      case HazardKind.frost:
        _stroke
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.6;
        for (var k = 0; k < 3; k++) {
          final a = k * math.pi / 3 + time;
          final d = Offset(math.cos(a), math.sin(a)) * (r * 0.35);
          c.drawLine(Offset(0, -r * 2.1) - d, Offset(0, -r * 2.1) + d, _stroke);
        }
      case HazardKind.storm:
        if ((time * 6 + hz.id).floor().isEven) {
          _stroke
            ..color = const Color(0xFFFFF27A)
            ..strokeWidth = 2;
          c.drawPath(
            Path()..addPolygon([
              Offset(-r * 0.2, -r * 2.4),
              Offset(r * 0.1, -r * 2.0),
              Offset(-r * 0.1, -r * 1.95),
              Offset(r * 0.25, -r * 1.55),
            ], false),
            _stroke,
          );
        }
    }
    // Health pip bar once damaged.
    final f = (hz.hp / hz.maxHp).clamp(0.0, 1.0);
    if (f < 1) {
      final bar = Rect.fromLTWH(-r, r * 1.55, r * 2, 4);
      _fill.color = const Color(0xAA1C1830);
      c.drawRRect(
        RRect.fromRectAndRadius(bar.inflate(1.5), const Radius.circular(3)),
        _fill,
      );
      _fill.color = color;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * f, bar.height),
          const Radius.circular(2),
        ),
        _fill,
      );
    }
    c.restore();
  }

  static Path _flame(Offset base, double s) => Path()
    ..moveTo(base.dx, base.dy - s * 1.6)
    ..quadraticBezierTo(
      base.dx + s,
      base.dy - s * 0.4,
      base.dx + s * 0.55,
      base.dy + s * 0.4,
    )
    ..quadraticBezierTo(
      base.dx,
      base.dy + s * 0.8,
      base.dx - s * 0.55,
      base.dy + s * 0.4,
    )
    ..quadraticBezierTo(
      base.dx - s,
      base.dy - s * 0.4,
      base.dx,
      base.dy - s * 1.6,
    )
    ..close();

  // --------------------------------------------------------- enemy shots

  void enemyShot(Canvas c, EnemyShot s) {
    final angle = math.atan2(s.vy, s.vx) - math.pi / 2;
    c.save();
    c.translate(s.x, s.y);
    c.rotate(angle);
    final r = s.radius;
    _fill.shader = ui.Gradient.linear(Offset(0, -r * 3.5), const Offset(0, 0), [
      const Color(0x00FF5CE6),
      const Color(0x99FF5CE6),
    ]);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-r * 0.5, -r * 3.5, r, r * 3.5),
        Radius.circular(r * 0.5),
      ),
      _fill,
    );
    _fill.shader = null;
    final body = Path()
      ..moveTo(0, r * 1.5)
      ..lineTo(r * 0.75, 0)
      ..lineTo(0, -r * 1.2)
      ..lineTo(-r * 0.75, 0)
      ..close();
    _fill.color = const Color(0xFFFF73E8);
    c.drawPath(body, _fill);
    _fill.color = const Color(0xFFFFD1F7);
    c.drawPath(
      Path()..addPolygon([
        Offset(0, r * 1.5),
        Offset(-r * 0.75, 0),
        Offset(0, -r * 1.2),
      ], true),
      _fill,
    );
    _stroke
      ..color = _outline
      ..strokeWidth = 1.6;
    c.drawPath(body, _stroke);
    c.restore();
  }

  // ------------------------------------------------------------- treasure

  /// A gold treasure crystal with a turning sparkle.
  void treasure(
    Canvas c, {
    required double x,
    required double y,
    required double r,
    required String text,
    required double time,
    double flash = 0,
  }) {
    const gold = Color(0xFFFFC83A);
    c.save();
    c.translate(x, y);
    _glow(c, r * 1.9, gold, 0.5);
    c.save();
    c.rotate(math.sin(time * 2) * 0.25);
    _gem(c, r, gold, facets: 6, variant: 1, flash: flash * flash * 0.2);
    c.restore();
    // Four-point sparkle orbiting the gem.
    final a = time * 3;
    c.save();
    c.translate(math.cos(a) * r * 0.9, math.sin(a) * r * 0.9);
    final s = 4 + 2 * math.sin(time * 9);
    _fill.color = const Color(0xFFFFFFFF);
    c.drawPath(
      Path()
        ..moveTo(0, -s * 2)
        ..lineTo(s * 0.4, 0)
        ..lineTo(0, s * 2)
        ..lineTo(-s * 0.4, 0)
        ..close()
        ..moveTo(-s * 2, 0)
        ..lineTo(0, s * 0.4)
        ..lineTo(s * 2, 0)
        ..lineTo(0, -s * 0.4)
        ..close(),
      _fill,
    );
    c.restore();
    label(c, text, r * 0.9 * labelScale(text), color: const Color(0xFF5A3A00));
    c.restore();
  }

  /// Elemental affinity ring: the crystal resists this element.
  void affinityRing(Canvas c, double x, double y, double r, Element e) {
    final color = elementColor(e);
    _stroke
      ..color = _outline
      ..strokeWidth = 5;
    c.drawCircle(Offset(x, y), r * 1.1, _stroke);
    _stroke
      ..color = color
      ..strokeWidth = 3;
    c.drawCircle(Offset(x, y), r * 1.1, _stroke);
    // A small element pip on top.
    final pip = Offset(x, y - r * 1.1);
    _fill.color = _outline;
    c.drawCircle(pip, 7, _fill);
    _fill.color = color;
    c.drawCircle(pip, 5, _fill);
  }

  // ------------------------------------------------------------ telegraphs

  void telegraph(Canvas c, Telegraph t, double floorY, double time) {
    final p = t.progress;
    final blink = (math.sin(time * 22) + 1) / 2;
    final w = t.width;
    final color = switch (t.kind) {
      TelegraphKind.slam => const Color(0xFFFF3B30),
      TelegraphKind.rain => const Color(0xFFFF7A2B),
      TelegraphKind.zap => const Color(0xFFFFE14A),
    };
    _fill.shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, floorY), [
      color.withValues(alpha: 0),
      color.withValues(alpha: 0.18 + 0.25 * p),
    ]);
    c.drawRect(Rect.fromLTRB(t.x - w, 0, t.x + w, floorY), _fill);
    _fill.shader = null;
    if (t.kind == TelegraphKind.zap) {
      // Column edges charge up as the strike approaches.
      _stroke
        ..color = color.withValues(alpha: 0.3 + 0.6 * p * blink)
        ..strokeWidth = 2;
      c.drawLine(Offset(t.x - w, 0), Offset(t.x - w, floorY), _stroke);
      c.drawLine(Offset(t.x + w, 0), Offset(t.x + w, floorY), _stroke);
    }
    // Target marker on the ground.
    _stroke
      ..color = color.withValues(alpha: 0.5 + 0.5 * blink)
      ..strokeWidth = 3;
    c.drawOval(
      Rect.fromCenter(
        center: Offset(t.x, floorY - 2),
        width: w * 2.4 * (1.3 - p * 0.3),
        height: math.max(8, w * 0.6),
      ),
      _stroke,
    );
    // Chevrons.
    _fill.color = color.withValues(alpha: 0.4 + 0.5 * blink);
    for (var k = 0; k < 2; k++) {
      final cy = floorY * (0.35 + 0.3 * k) + (time * 120 % 40);
      c.drawPath(
        Path()..addPolygon([
          Offset(t.x - 8, cy),
          Offset(t.x + 8, cy),
          Offset(t.x, cy + 10),
        ], true),
        _fill,
      );
    }
  }

  /// Boss floor attack: a blinking outline while warning, then lava or
  /// frost covering that stretch of ground.
  void floorZone(Canvas c, FloorZone z, double floorY, double time) {
    final lava = z.kind == ZoneKind.lava;
    final color = lava ? const Color(0xFFFF5A1F) : const Color(0xFF8FE8FF);
    final rect = Rect.fromLTRB(
      z.x - z.halfWidth,
      floorY - 16,
      z.x + z.halfWidth,
      floorY + 6,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    if (!z.armed) {
      final blink = (math.sin(time * 18) + 1) / 2;
      _fill.color = color.withValues(alpha: 0.12 + 0.25 * z.warnProgress);
      c.drawRRect(rrect, _fill);
      _stroke
        ..color = color.withValues(alpha: 0.5 + 0.5 * blink)
        ..strokeWidth = 3;
      c.drawRRect(rrect, _stroke);
      return;
    }
    final fade = lava ? 1.0 : (z.active / 1.2).clamp(0.0, 1.0);
    _fill.shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
      (lava ? const Color(0xFFFFE07A) : const Color(0xFFFFFFFF)).withValues(
        alpha: 0.95 * fade,
      ),
      color.withValues(alpha: 0.9 * fade),
    ]);
    c.drawRRect(rrect, _fill);
    _fill.shader = null;
    if (lava) {
      // Bubbles.
      _fill.color = const Color(0xFFFFF0B0);
      for (var k = 0; k < 4; k++) {
        final phase = (time * 1.6 + k * 0.37) % 1;
        final bx = z.x - z.halfWidth * 0.8 + k * z.halfWidth * 0.53;
        c.drawCircle(
          Offset(bx, floorY - 12 - phase * 16),
          3 * (1 - phase),
          _fill,
        );
      }
      // Heat glow above the pool.
      _fill.shader = ui.Gradient.linear(
        Offset(z.x, floorY - 70),
        Offset(z.x, floorY - 10),
        [color.withValues(alpha: 0), color.withValues(alpha: 0.35)],
      );
      c.drawRect(
        Rect.fromLTRB(
          z.x - z.halfWidth,
          floorY - 70,
          z.x + z.halfWidth,
          floorY - 10,
        ),
        _fill,
      );
      _fill.shader = null;
    } else {
      // Ice spikes.
      _fill.color = const Color(0xFFE8FBFF).withValues(alpha: fade);
      for (var k = 0; k < 5; k++) {
        final bx = z.x - z.halfWidth * 0.8 + k * z.halfWidth * 0.4;
        c.drawPath(
          Path()..addPolygon([
            Offset(bx - 6, floorY - 12),
            Offset(bx, floorY - 34 - (k.isEven ? 8 : 0)),
            Offset(bx + 6, floorY - 12),
          ], true),
          _fill,
        );
      }
    }
    _stroke
      ..color = _outline.withValues(alpha: fade)
      ..strokeWidth = 2.5;
    c.drawRRect(rrect, _stroke);
  }
}
