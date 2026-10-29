import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../render/ball_art.dart';
import '../ui/theme/palette.dart';

enum _Kind { spark, shard, rock, smoke, fireball }

/// Purely cosmetic effects in world units. They never affect gameplay and
/// are capped so heavy waves cannot flood the renderer.
class EffectsLayer {
  EffectsLayer({required this.reducedMotion});

  bool reducedMotion;
  // Seeded: effects are purely cosmetic, and a fixed seed makes rendered
  // frames reproducible (screenshot tests).
  final _rng = math.Random(7);
  final List<_Particle> _particles = [];
  final List<_Ring> _rings = [];
  final List<_Arc> _arcs = [];
  final List<_FloatText> _texts = [];
  final Paint _paint = Paint();
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Map<String, TextPainter> _textCache = {};
  static final Path _triangle = Path()
    ..addPolygon(const [
      Offset(0, -1),
      Offset(0.8, 0.7),
      Offset(-0.7, 0.5),
    ], true);

  static const int maxParticles = 240;

  double shake = 0;
  double flash = 0;
  String? bannerText;
  String? bannerSub;
  Color bannerColor = Palette.yellow;
  double bannerTime = 0;
  static const double bannerDuration = 1.6;

  int chainShown = 0;
  double chainTime = 0;

  int get particleCount => _particles.length;

  void clear() {
    _particles.clear();
    _rings.clear();
    _arcs.clear();
    _texts.clear();
    shake = 0;
    flash = 0;
    bannerText = null;
    bannerTime = 0;
    chainTime = 0;
  }

  bool get _full => _particles.length >= maxParticles;
  int _n(int count) => reducedMotion ? (count / 2).ceil() : count;

  void _add(
    _Kind kind,
    double x,
    double y,
    double vx,
    double vy,
    double life,
    double size,
    Color color, {
    double spin = 0,
    double gravity = 520,
  }) {
    if (_full) return;
    _particles.add(
      _Particle(
        kind,
        x,
        y,
        vx,
        vy,
        life,
        size,
        color,
        _rng.nextDouble() * 6.28,
        spin,
        gravity,
      ),
    );
  }

  /// Generic radial burst of sparks.
  void burst(
    double x,
    double y,
    Color color, {
    int count = 12,
    double speed = 220,
    double size = 3.2,
  }) {
    for (var i = 0; i < _n(count); i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = speed * (0.35 + _rng.nextDouble() * 0.75);
      _add(
        _Kind.spark,
        x,
        y,
        math.cos(a) * s,
        math.sin(a) * s - 40,
        0.35 + _rng.nextDouble() * 0.35,
        size * (0.6 + _rng.nextDouble() * 0.8),
        i.isEven ? color : Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!,
      );
    }
  }

  /// Crystal shatter: spinning triangular shards in the crystal's colour.
  void shatter(double x, double y, Color color, double radius) {
    final count = _n((6 + radius / 3).round());
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = 120 + _rng.nextDouble() * 220;
      _add(
        _Kind.shard,
        x + math.cos(a) * radius * 0.4,
        y + math.sin(a) * radius * 0.4,
        math.cos(a) * s,
        math.sin(a) * s - 120,
        0.6 + _rng.nextDouble() * 0.4,
        radius * (0.18 + _rng.nextDouble() * 0.2),
        i % 3 == 0
            ? shade(color, 0.45)
            : (i % 3 == 1 ? color : shade(color, -0.3)),
        spin: (_rng.nextDouble() - 0.5) * 18,
        gravity: 700,
      );
    }
    burst(
      x,
      y,
      Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!,
      count: 6,
      speed: 160,
      size: 2.4,
    );
  }

  /// Rock chunks (geode shells, boss plates).
  void rocks(double x, double y, double radius) {
    for (var i = 0; i < _n((5 + radius / 4).round()); i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = 100 + _rng.nextDouble() * 180;
      _add(
        _Kind.rock,
        x,
        y,
        math.cos(a) * s,
        math.sin(a) * s - 150,
        0.8 + _rng.nextDouble() * 0.3,
        radius * (0.16 + _rng.nextDouble() * 0.14),
        i.isEven ? const Color(0xFF8C7A6B) : const Color(0xFF5E5148),
        spin: (_rng.nextDouble() - 0.5) * 10,
        gravity: 900,
      );
    }
    smoke(x, y, radius * 0.6, count: 4);
  }

  void smoke(
    double x,
    double y,
    double size, {
    int count = 6,
    Color color = const Color(0xFFB9B4C7),
  }) {
    for (var i = 0; i < _n(count); i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = 20 + _rng.nextDouble() * 50;
      _add(
        _Kind.smoke,
        x + math.cos(a) * size * 0.4,
        y + math.sin(a) * size * 0.4,
        math.cos(a) * s,
        math.sin(a) * s - 30,
        0.7 + _rng.nextDouble() * 0.5,
        size * (0.5 + _rng.nextDouble() * 0.5),
        color,
        gravity: -40,
      );
    }
  }

  /// Layered explosion: flash, fireballs, smoke, sparks and a shockwave.
  void explosion(
    double x,
    double y,
    double radius, {
    Color core = const Color(0xFFFFE07A),
    Color outer = const Color(0xFFFF6A2B),
  }) {
    flash = math.max(flash, reducedMotion ? 0.15 : 0.35);
    for (var i = 0; i < _n(9); i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final d = radius * 0.35 * _rng.nextDouble();
      _add(
        _Kind.fireball,
        x + math.cos(a) * d,
        y + math.sin(a) * d,
        math.cos(a) * 60,
        math.sin(a) * 60 - 20,
        0.35 + _rng.nextDouble() * 0.25,
        radius * (0.25 + _rng.nextDouble() * 0.2),
        i.isEven ? core : outer,
        gravity: -60,
      );
    }
    smoke(x, y, radius * 0.4, count: 7);
    burst(x, y, core, count: 16, speed: 320, size: 3.5);
    ring(x, y, radius, outer, life: 0.45, width: 8);
    ring(x, y, radius * 0.6, core, life: 0.3, width: 5);
  }

  void frostNova(double x, double y, double radius) {
    ring(x, y, radius, const Color(0xFF9BEBFF), life: 0.55, width: 9);
    for (var i = 0; i < _n(16); i++) {
      final a = i / 16 * math.pi * 2;
      _add(
        _Kind.shard,
        x,
        y,
        math.cos(a) * 280,
        math.sin(a) * 280,
        0.45,
        6,
        i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFF7FE6FF),
        spin: 6,
        gravity: 0,
      );
    }
    smoke(x, y, radius * 0.3, count: 5, color: const Color(0xFFDFF7FF));
  }

  void ring(
    double x,
    double y,
    double radius,
    Color color, {
    double life = 0.45,
    double width = 5,
  }) {
    _rings.add(_Ring(x, y, radius, color, life, width));
  }

  /// Jagged lightning along a polyline.
  void lightning(List<Offset> points, {Color color = const Color(0xFFFFE14A)}) {
    if (points.length < 2) return;
    if (_arcs.length > 24) _arcs.removeAt(0);
    final jagged = <Offset>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final len = (b - a).distance;
      final segs = math.max(3, (len / 14).round());
      final normal = Offset(-(b - a).dy, (b - a).dx) / (len + 1e-6);
      for (var s = 1; s < segs; s++) {
        final p = Offset.lerp(a, b, s / segs)!;
        jagged.add(p + normal * ((_rng.nextDouble() - 0.5) * 16));
      }
      jagged.add(b);
      burst(b.dx, b.dy, color, count: 3, speed: 120, size: 2);
    }
    _arcs.add(_Arc(jagged, color, 0.18));
  }

  void floatText(
    double x,
    double y,
    String text,
    Color color, {
    double size = 15,
  }) {
    if (_texts.length > 14) _texts.removeAt(0);
    _texts.add(_FloatText(x, y, text, color, 0.9, size));
  }

  void addShake(double amount) {
    if (reducedMotion) return;
    // Kept gentle: strong shake hurts readability more than it adds impact.
    shake = math.min(7, shake + amount * 0.6);
  }

  void showBanner(String text, {String? sub, Color color = Palette.yellow}) {
    bannerText = text;
    bannerSub = sub;
    bannerColor = color;
    bannerTime = bannerDuration;
  }

  void showChain(int count) {
    chainShown = count;
    chainTime = 1.1;
  }

  void update(double dt) {
    for (final p in _particles) {
      p.life -= dt;
      p.vy += p.gravity * dt;
      final drag = p.kind == _Kind.smoke ? 2.5 : 1.6;
      p.vx *= 1 - drag * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final a in _arcs) {
      a.age += dt;
    }
    _arcs.removeWhere((a) => a.age >= a.life);
    for (final t in _texts) {
      t.age += dt;
      t.y -= 50 * dt;
    }
    _texts.removeWhere((t) => t.age >= t.life);
    shake = math.max(0, shake - dt * 30);
    flash = math.max(0, flash - dt * 2.5);
    if (bannerTime > 0) bannerTime = math.max(0, bannerTime - dt);
    if (chainTime > 0) chainTime = math.max(0, chainTime - dt);
  }

  Offset shakeOffset() {
    if (shake <= 0) return Offset.zero;
    return Offset(
      (_rng.nextDouble() - 0.5) * shake,
      (_rng.nextDouble() - 0.5) * shake,
    );
  }

  /// Back layer (smoke) drawn behind creatures.
  void renderBack(Canvas canvas) {
    for (final p in _particles) {
      if (p.kind != _Kind.smoke) continue;
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      _paint.color = p.color.withValues(alpha: 0.45 * t);
      canvas.drawCircle(Offset(p.x, p.y), p.size * (1.6 - 0.6 * t), _paint);
    }
  }

  void render(Canvas canvas) {
    for (final p in _particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      switch (p.kind) {
        case _Kind.smoke:
          break;
        case _Kind.spark:
          _paint.color = p.color.withValues(alpha: t);
          canvas.drawCircle(Offset(p.x, p.y), p.size * (0.4 + 0.6 * t), _paint);
        case _Kind.fireball:
          final r = p.size * (1.4 - 0.6 * t);
          _paint.shader = RadialGradient(
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: t),
              p.color.withValues(alpha: t),
              const Color(0xFFB0301A).withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: Offset(p.x, p.y), radius: r));
          canvas.drawCircle(Offset(p.x, p.y), r, _paint);
          _paint.shader = null;
        case _Kind.shard:
        case _Kind.rock:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.angle);
          canvas.scale(p.size);
          _paint.color = p.color.withValues(alpha: math.min(1, t * 2));
          canvas.drawPath(_triangle, _paint);
          canvas.restore();
      }
    }
    for (final r in _rings) {
      final t = r.age / r.life;
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      _ringPaint
        ..strokeWidth = r.width * (1 - t) + 0.5
        ..color = r.color.withValues(alpha: (1 - t) * 0.9);
      canvas.drawCircle(Offset(r.x, r.y), r.radius * eased, _ringPaint);
    }
    for (final a in _arcs) {
      final alpha = (1 - a.age / a.life).clamp(0.0, 1.0);
      final path = Path()..addPolygon(a.points, false);
      _arcPaint
        ..strokeWidth = 7
        ..color = a.color.withValues(alpha: 0.35 * alpha);
      canvas.drawPath(path, _arcPaint);
      _arcPaint
        ..strokeWidth = 2.4
        ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
      canvas.drawPath(path, _arcPaint);
    }
    for (final t in _texts) {
      final painter = _text(t.text, t.size, t.color);
      final alpha = (1 - t.age / t.life).clamp(0.0, 1.0);
      final topLeft = Offset(t.x - painter.width / 2, t.y - painter.height / 2);
      _fadeLayer(canvas, topLeft & painter.size, alpha);
      painter.paint(canvas, topLeft);
      canvas.restore();
    }
  }

  final Paint _layerPaint = Paint();

  /// Opens a fade layer clipped to [bounds]. Unbounded layers allocate a
  /// full-screen offscreen texture each, which is what made busy waves lag.
  void _fadeLayer(Canvas canvas, Rect bounds, double alpha) {
    if (alpha >= 0.99) {
      canvas.save();
      return;
    }
    _layerPaint.color = Color.fromRGBO(0, 0, 0, alpha);
    canvas.saveLayer(bounds.inflate(12), _layerPaint);
  }

  /// Screen-space overlays: white flash, wave banner and chain counter.
  void renderOverlay(
    Canvas canvas,
    Size size,
    Offset bannerCenter,
    double scale,
  ) {
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 250, 230, flash * 0.5),
      );
    }
    final text = bannerText;
    if (text != null && bannerTime > 0) {
      final elapsed = bannerDuration - bannerTime;
      final appear = (elapsed / 0.2).clamp(0.0, 1.0);
      final fade = (bannerTime / 0.35).clamp(0.0, 1.0);
      final pop = reducedMotion
          ? 1.0
          : 0.7 + 0.3 * Curves.easeOutBack.transform(appear);
      canvas.save();
      canvas.translate(bannerCenter.dx, bannerCenter.dy);
      canvas.scale(pop * scale);
      final main = _text(text, 42, bannerColor);
      final sub = bannerSub;
      final s = sub == null ? null : _text(sub, 17, Palette.text);
      final w = math.max(main.width, s?.width ?? 0);
      _fadeLayer(
        canvas,
        Rect.fromLTRB(
          -w / 2,
          -main.height / 2,
          w / 2,
          main.height / 2 + 2 + (s?.height ?? 0),
        ),
        math.min(appear, fade),
      );
      main.paint(canvas, Offset(-main.width / 2, -main.height / 2));
      if (s != null) {
        s.paint(canvas, Offset(-s.width / 2, main.height / 2 + 2));
      }
      canvas.restore();
      canvas.restore();
    }
    if (chainTime > 0 && chainShown >= 2) {
      final appear = ((1.1 - chainTime) / 0.15).clamp(0.0, 1.0);
      final pop = reducedMotion
          ? 1.0
          : 0.6 + 0.4 * Curves.easeOutBack.transform(appear);
      final alpha = (chainTime / 0.3).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(size.width / 2, size.height * 0.22);
      canvas.rotate(-0.06);
      canvas.scale(pop * scale);
      final color = chainShown >= 8
          ? Palette.coral
          : (chainShown >= 5 ? Palette.orange : Palette.yellow);
      final t = _text(
        'CHAIN x$chainShown!',
        30 + math.min(chainShown, 12) * 1.5,
        color,
      );
      final topLeft = Offset(-t.width / 2, -t.height / 2);
      _fadeLayer(canvas, topLeft & t.size, alpha);
      t.paint(canvas, topLeft);
      canvas.restore();
      canvas.restore();
    }
  }

  /// Outlined arcade text, cached by content and style.
  TextPainter _text(String text, double size, Color color) {
    final key = '$text|$size|${color.toARGB32()}';
    if (_textCache.length > 80) _textCache.clear();
    return _textCache.putIfAbsent(
      key,
      () => _OutlinedPainter(
        text,
        TextStyle(
          fontFamily: TextStyles.display,
          fontSize: size,
          letterSpacing: 1,
          height: 1,
        ),
        color,
      ),
    );
  }
}

/// TextPainter that paints a thick dark outline and drop shadow under the
/// fill, the house style for in-game text.
class _OutlinedPainter extends TextPainter {
  _OutlinedPainter(String text, TextStyle base, Color color)
    : _stroke = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (base.fontSize ?? 20) * 0.2
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF1C1830),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
      super(
        text: TextSpan(
          text: text,
          style: base.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
      ) {
    layout();
  }

  final TextPainter _stroke;

  @override
  void paint(Canvas canvas, Offset offset) {
    _stroke.paint(canvas, offset.translate(0, 2.5));
    _stroke.paint(canvas, offset);
    super.paint(canvas, offset);
  }
}

class _Particle {
  _Particle(
    this.kind,
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.size,
    this.color,
    this.angle,
    this.spin,
    this.gravity,
  ) : maxLife = life;
  final _Kind kind;
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final double size;
  final Color color;
  double angle;
  final double spin;
  final double gravity;
}

class _Ring {
  _Ring(this.x, this.y, this.radius, this.color, this.life, this.width);
  final double x;
  final double y;
  final double radius;
  final Color color;
  final double life;
  final double width;
  double age = 0;
}

class _Arc {
  _Arc(this.points, this.color, this.life);
  final List<Offset> points;
  final Color color;
  final double life;
  double age = 0;
}

class _FloatText {
  _FloatText(this.x, this.y, this.text, this.color, this.life, this.size);
  final double x;
  double y;
  final String text;
  final Color color;
  final double life;
  final double size;
  double age = 0;
}
