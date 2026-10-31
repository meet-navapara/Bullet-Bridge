import 'dart:math' as math;
import 'dart:ui';

import '../config/level_animation.dart';
import '../economy/catalog.dart';

enum _Motion { fall, rise, hover, cross, dive, spiral }

enum _Shape {
  dot,
  glow,
  streak,
  ring,
  petal,
  diamond,
  shard,
  paper,
  star,
  bird,
  tail,
}

class _Particles {
  const _Particles(
    this.motion,
    this.shape,
    this.color,
    this.count,
    this.speed,
    this.size,
    this.alpha,
  );
  final _Motion motion;
  final _Shape shape;
  final Color color;
  final int count;

  /// Screen heights (or widths) travelled per second.
  final double speed;
  final double size;
  final double alpha;
}

/// Animated sky effects drawn between the backdrop and the ground.
///
/// Everything is a pure function of (level, time), so there is no particle
/// state to update or allocate. Effects stay small and translucent, and sit
/// behind every gameplay object, so they never hide what can hurt the player.
abstract final class AmbientArt {
  static final Paint _fill = Paint();
  static final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Share of the main effect's particles and opacity used by the accent.
  static const double _accentCount = 0.6;
  static const double _accentAlpha = 0.7;

  /// Soft colours, with a hint of the world's sun colour mixed in.
  static const double _themeTint = 0.25;

  /// Particle sizes and opacity on a phone-sized arena. Enemy shots stay the
  /// boldest thing on screen: they are larger and fully opaque.
  static const double _sizeBoost = 1.5;
  static const double _alphaBoost = 1.25;

  /// Washes the sky with the level's time of day.
  static void paintMood(
    Canvas canvas,
    Size size,
    double groundTop,
    LevelAnimation a,
  ) {
    final (Color top, Color bottom) = switch (a.mood) {
      AmbientMood.clear => (const Color(0x00000000), const Color(0x00000000)),
      AmbientMood.dawn => (const Color(0x38FF7AA8), const Color(0x30FFC98A)),
      AmbientMood.dusk => (const Color(0x48C2410C), const Color(0x38FF9A3D)),
      AmbientMood.twilight => (
        const Color(0x70101048),
        const Color(0x38503C96),
      ),
      AmbientMood.mist => (const Color(0x30D8F0F0), const Color(0x48E8FFF4)),
    };
    if (a.mood == AmbientMood.clear) return;
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, groundTop),
      _fill
        ..shader = Gradient.linear(Offset.zero, Offset(0, groundTop), [
          top,
          bottom,
        ]),
    );
    _fill.shader = null;
  }

  static void paint(
    Canvas canvas,
    Size size,
    double groundTop,
    LevelAnimation a,
    ArenaTheme theme,
    double time,
  ) {
    final t = time * a.tempo.scale;
    final seed = a.level * 0.6180339;
    final sky = Size(size.width, groundTop);
    _layer(canvas, sky, a.main, a.wind, theme, t, seed, 1, 1);
    _layer(
      canvas,
      sky,
      a.accent,
      a.wind,
      theme,
      t,
      seed + 0.37,
      _accentCount,
      _accentAlpha,
    );
  }

  static void _layer(
    Canvas c,
    Size s,
    AmbientKind kind,
    AmbientWind wind,
    ArenaTheme theme,
    double t,
    double seed,
    double countScale,
    double alpha,
  ) {
    final tint = Color.lerp(_tintOf(kind), theme.sun, _themeTint)!;
    switch (kind) {
      case AmbientKind.lightning:
        _lightning(c, s, tint, t, seed, alpha);
      case AmbientKind.aurora:
        _aurora(c, s, tint, t, seed, alpha);
      case AmbientKind.ribbons:
        _ribbons(c, s, tint, t, seed, alpha);
      case AmbientKind.ripples:
        _ripples(c, s, tint, t, seed, alpha);
      case AmbientKind.sunbeams:
        _sunbeams(c, s, tint, t, seed, alpha);
      case AmbientKind.fog:
        _fog(c, s, tint, t, seed, alpha);
      case AmbientKind.heatWaves:
        _heatWaves(c, s, tint, t, seed, alpha);
      default:
        _particles(c, s, _spec(kind), tint, wind, t, seed, countScale, alpha);
    }
  }

  static Color _tintOf(AmbientKind k) => switch (k) {
    AmbientKind.lightning => const Color(0xFFE8F0FF),
    AmbientKind.aurora => const Color(0xFF5CFFB0),
    AmbientKind.ribbons => const Color(0xFFFF9AD8),
    AmbientKind.ripples => const Color(0xFF9CE8FF),
    AmbientKind.sunbeams => const Color(0xFFFFF0B8),
    AmbientKind.fog => const Color(0xFFE6ECF4),
    AmbientKind.heatWaves => const Color(0xFFFFC08A),
    _ => _spec(k).color,
  };

  static _Particles _spec(AmbientKind k) => switch (k) {
    AmbientKind.snowfall => const _Particles(
      _Motion.fall,
      _Shape.dot,
      Color(0xFFFFFFFF),
      30,
      0.07,
      2.6,
      0.75,
    ),
    AmbientKind.rain => const _Particles(
      _Motion.fall,
      _Shape.streak,
      Color(0xFF9CC8FF),
      30,
      0.55,
      13,
      0.45,
    ),
    AmbientKind.embers => const _Particles(
      _Motion.rise,
      _Shape.glow,
      Color(0xFFFF9A4A),
      24,
      0.1,
      2.2,
      0.8,
    ),
    AmbientKind.fireflies => const _Particles(
      _Motion.hover,
      _Shape.glow,
      Color(0xFFD8FF7A),
      16,
      0.2,
      2.6,
      0.85,
    ),
    AmbientKind.bubbles => const _Particles(
      _Motion.rise,
      _Shape.ring,
      Color(0xFFA8F0FF),
      16,
      0.08,
      6,
      0.55,
    ),
    AmbientKind.petals => const _Particles(
      _Motion.fall,
      _Shape.petal,
      Color(0xFFFFB0D0),
      20,
      0.08,
      4.5,
      0.7,
    ),
    AmbientKind.leaves => const _Particles(
      _Motion.fall,
      _Shape.diamond,
      Color(0xFF9AD86A),
      18,
      0.1,
      5,
      0.65,
    ),
    AmbientKind.sandstorm => const _Particles(
      _Motion.cross,
      _Shape.streak,
      Color(0xFFE8CFA0),
      28,
      0.32,
      12,
      0.35,
    ),
    AmbientKind.twinkles => const _Particles(
      _Motion.hover,
      _Shape.star,
      Color(0xFFFFFFFF),
      22,
      0.06,
      4,
      0.85,
    ),
    AmbientKind.meteors => const _Particles(
      _Motion.dive,
      _Shape.tail,
      Color(0xFFFFE0B0),
      5,
      0.32,
      42,
      0.7,
    ),
    AmbientKind.comets => const _Particles(
      _Motion.cross,
      _Shape.tail,
      Color(0xFF9CF0FF),
      3,
      0.07,
      64,
      0.7,
    ),
    AmbientKind.orbs => const _Particles(
      _Motion.hover,
      _Shape.dot,
      Color(0xFFC8B8FF),
      9,
      0.12,
      15,
      0.16,
    ),
    AmbientKind.spores => const _Particles(
      _Motion.rise,
      _Shape.dot,
      Color(0xFFD8F0A0),
      32,
      0.035,
      1.6,
      0.7,
    ),
    AmbientKind.shards => const _Particles(
      _Motion.fall,
      _Shape.shard,
      Color(0xFFE8F6FF),
      12,
      0.13,
      3.2,
      0.4,
    ),
    AmbientKind.confetti => const _Particles(
      _Motion.fall,
      _Shape.paper,
      Color(0xFFFFFFFF),
      24,
      0.12,
      3.4,
      0.75,
    ),
    AmbientKind.swirl => const _Particles(
      _Motion.spiral,
      _Shape.dot,
      Color(0xFFD0C0FF),
      26,
      0.05,
      2.2,
      0.7,
    ),
    AmbientKind.birds => const _Particles(
      _Motion.cross,
      _Shape.bird,
      Color(0xFF2A3350),
      7,
      0.045,
      7,
      0.6,
    ),
    _ => throw ArgumentError.value(k, 'kind', 'not a particle effect'),
  };

  static const List<Color> _confetti = [
    Color(0xFFFF7AA8),
    Color(0xFF7AD8FF),
    Color(0xFFB8FF7A),
    Color(0xFFD8A8FF),
    Color(0xFFFFB87A),
  ];

  static double _frac(double v) => v - v.floorToDouble();

  /// Sideways drift (fraction of the width) after [t] seconds.
  static double _windAt(AmbientWind wind, double t) => switch (wind) {
    AmbientWind.still => 0,
    AmbientWind.left => -0.025 * t,
    AmbientWind.right => 0.025 * t,
    AmbientWind.gusty => 0.14 * math.sin(t * 0.33),
  };

  static void _particles(
    Canvas c,
    Size s,
    _Particles p,
    Color tint,
    AmbientWind wind,
    double t,
    double seed,
    double countScale,
    double alpha,
  ) {
    final unit = s.width / 360;
    final count = math.max(2, (p.count * countScale).round());
    final drift = _windAt(wind, t);
    final size = p.size * unit * _sizeBoost;
    for (var i = 0; i < count; i++) {
      // Low-discrepancy values spread particles evenly with no stored state.
      final u = _frac(seed + i * 0.6180339);
      final v = _frac(seed * 1.7 + i * 0.7548777);
      final w = _frac(seed * 2.3 + i * 0.5698403);
      final speed = p.speed * (0.7 + 0.6 * w);
      double x;
      double y;
      var heading = math.pi / 2;
      switch (p.motion) {
        case _Motion.fall:
          y = _frac(v + t * speed);
          x = u + drift + 0.02 * math.sin(t * 1.3 + u * 6.28);
          heading = math.pi / 2 - drift.sign * 0.14;
        case _Motion.rise:
          y = 1 - _frac(v + t * speed);
          x = u + drift + 0.025 * math.sin(t * 0.9 + w * 6.28);
        case _Motion.hover:
          x = u + 0.03 * math.sin(t * speed * 6 + w * 6.28) + drift * 0.3;
          y = v + 0.03 * math.cos(t * speed * 5 + u * 6.28);
        case _Motion.cross:
          // Each particle crosses one way, picked by its own value.
          final dir =
              wind == AmbientWind.left || (wind != AmbientWind.right && w < 0.5)
              ? -1.0
              : 1.0;
          x = _frac(u + dir * t * speed);
          y = v * 0.62 + 0.012 * math.sin(t * 2 + u * 6.28);
          heading = dir > 0 ? 0 : math.pi;
        case _Motion.dive:
          final along = _frac(v + t * speed);
          x = u + along * 0.45 + drift;
          // Meteors burn out high in the sky, so they never read as attacks.
          y = along * 0.45 - 0.05;
          heading = math.atan2(0.45 * s.height, 0.45 * s.width);
        case _Motion.spiral:
          final angle = t * 0.7 + i * 2.399963;
          final radius = 0.1 + 0.36 * _frac(w + t * speed);
          x = 0.5 + drift + radius * math.cos(angle);
          y = 0.42 + radius * 0.8 * math.sin(angle);
      }
      final px = _frac(x) * s.width;
      final py = y * s.height;
      var a = math.min(1.0, p.alpha * alpha * _alphaBoost);
      if (p.shape == _Shape.glow || p.shape == _Shape.star) {
        // Fireflies, embers and stars pulse gently at their own rate.
        a *=
            0.45 +
            0.55 * (0.5 + 0.5 * math.sin(t * (1.4 + w * 1.6) + u * 6.28));
      }
      final color = p.shape == _Shape.paper
          ? _confetti[i % _confetti.length]
          : tint;
      _draw(c, p.shape, Offset(px, py), size, color, a, heading, t, u);
    }
  }

  static void _draw(
    Canvas c,
    _Shape shape,
    Offset at,
    double size,
    Color color,
    double alpha,
    double heading,
    double t,
    double phase,
  ) {
    final paint = _fill..color = color.withValues(alpha: alpha);
    switch (shape) {
      case _Shape.dot:
        c.drawCircle(at, size, paint);
      case _Shape.glow:
        c.drawCircle(
          at,
          size * 2.6,
          _fill..color = color.withValues(alpha: alpha * 0.22),
        );
        c.drawCircle(at, size, _fill..color = color.withValues(alpha: alpha));
      case _Shape.streak:
        _line
          ..strokeWidth = math.max(1, size * 0.13)
          ..color = color.withValues(alpha: alpha);
        c.drawLine(
          at,
          at + Offset(math.cos(heading), math.sin(heading)) * size,
          _line,
        );
      case _Shape.ring:
        _line
          ..strokeWidth = math.max(1, size * 0.22)
          ..color = color.withValues(alpha: alpha);
        c.drawCircle(at, size, _line);
      case _Shape.petal || _Shape.diamond || _Shape.shard || _Shape.paper:
        c.save();
        c.translate(at.dx, at.dy);
        c.rotate(t * (0.8 + phase) + phase * 6.28);
        switch (shape) {
          case _Shape.petal:
            c.drawOval(
              Rect.fromCenter(
                center: Offset.zero,
                width: size * 2.2,
                height: size,
              ),
              paint,
            );
          case _Shape.diamond:
            c.drawPath(
              Path()..addPolygon([
                Offset(-size, 0),
                Offset(0, -size * 0.55),
                Offset(size, 0),
                Offset(0, size * 0.55),
              ], true),
              paint,
            );
          case _Shape.shard:
            c.drawPath(
              Path()..addPolygon([
                Offset(0, -size),
                Offset(size * 0.6, size * 0.7),
                Offset(-size * 0.6, size * 0.7),
              ], true),
              paint,
            );
          default:
            // Paper flutters by narrowing as it turns.
            c.drawRect(
              Rect.fromCenter(
                center: Offset.zero,
                width: size * 1.6,
                height:
                    size * (0.35 + 0.65 * math.sin(t * 3 + phase * 6.28).abs()),
              ),
              paint,
            );
        }
        c.restore();
      case _Shape.star:
        _line
          ..strokeWidth = math.max(1, size * 0.22)
          ..color = color.withValues(alpha: alpha);
        c.drawLine(at - Offset(size, 0), at + Offset(size, 0), _line);
        c.drawLine(at - Offset(0, size), at + Offset(0, size), _line);
      case _Shape.bird:
        final flap = math.sin(t * 5 + phase * 6.28) * size * 0.55;
        _line
          ..strokeWidth = math.max(1, size * 0.22)
          ..color = color.withValues(alpha: alpha);
        c.drawLine(at, at + Offset(-size, -flap), _line);
        c.drawLine(at, at + Offset(size, -flap), _line);
      case _Shape.tail:
        final back = at - Offset(math.cos(heading), math.sin(heading)) * size;
        _line
          ..strokeWidth = math.max(1, size * 0.045)
          ..color = color.withValues(alpha: alpha * 0.45);
        c.drawLine(back, at, _line);
        c.drawCircle(
          at,
          math.max(1.5, size * 0.055),
          _fill..color = color.withValues(alpha: alpha),
        );
    }
  }

  /// A distant bolt every few seconds. Deliberately never a full-screen
  /// flash: strobing light is unpleasant and a photosensitivity risk.
  static void _lightning(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    const period = 5.0;
    const visible = 0.28;
    final strike = (t / period + seed).floorToDouble();
    final since = (t / period + seed - strike) * period;
    if (since > visible) return;
    final fade = 1 - since / visible;
    var x = s.width * _frac(strike * 0.6180339);
    var y = 0.0;
    final path = Path()..moveTo(x, y);
    const segments = 7;
    for (var i = 1; i <= segments; i++) {
      y += s.height * 0.055;
      x += s.width * (_frac(strike * 0.31 + i * 0.7548777) - 0.5) * 0.09;
      path.lineTo(x, y);
    }
    _line
      ..strokeWidth = 2.2
      ..color = tint.withValues(alpha: 0.65 * alpha * fade);
    c.drawPath(path, _line);
  }

  static Path _wave(
    Size s,
    double y0,
    double amplitude,
    double frequency,
    double phase,
  ) {
    const steps = 18;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = s.width * i / steps;
      final y = y0 + amplitude * math.sin(i / steps * frequency + phase);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  static void _aurora(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    for (var band = 0; band < 3; band++) {
      final color = Color.lerp(tint, const Color(0xFF7A9CFF), band / 2)!;
      _line
        ..strokeWidth = s.height * 0.05
        ..color = color.withValues(alpha: 0.2 * alpha);
      c.drawPath(
        _wave(
          s,
          s.height * (0.14 + band * 0.07),
          s.height * 0.03,
          4.0 + band,
          t * (0.35 + band * 0.1) + seed * 6.28,
        ),
        _line,
      );
    }
  }

  static void _ribbons(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    for (var i = 0; i < 4; i++) {
      _line
        ..strokeWidth = 2.5
        ..color = tint.withValues(alpha: 0.45 * alpha);
      c.drawPath(
        _wave(
          s,
          s.height * (0.12 + i * 0.13 + 0.03 * math.sin(t * 0.4 + i)),
          s.height * 0.025,
          7 + i * 1.5,
          t * (i.isEven ? 0.8 : -0.8) + seed * 6.28 + i,
        ),
        _line,
      );
    }
  }

  static void _ripples(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    const period = 4.5;
    for (var i = 0; i < 4; i++) {
      final cycle = t / period + i / 4 + seed;
      final n = cycle.floorToDouble();
      final age = cycle - n;
      final center = Offset(
        s.width * _frac(n * 0.6180339 + i * 0.29),
        s.height * (0.08 + 0.5 * _frac(n * 0.7548777 + i * 0.41)),
      );
      _line
        ..strokeWidth = 2
        ..color = tint.withValues(alpha: 0.55 * alpha * (1 - age));
      c.drawCircle(center, s.width * (0.02 + 0.16 * age), _line);
    }
  }

  static void _sunbeams(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    // Starts at the sun painted by WorldArt.
    final sun = Offset(s.width * 0.8, s.height * 0.16);
    final reach = s.height * 0.95;
    _fill.color = tint.withValues(alpha: 0.11 * alpha);
    const beams = 6;
    for (var i = 0; i < beams; i++) {
      final angle =
          math.pi * 0.52 +
          i * 0.26 +
          0.09 * math.sin(t * 0.22 + i + seed * 6.28);
      const half = 0.045;
      c.drawPath(
        Path()..addPolygon([
          sun,
          sun + Offset(math.cos(angle - half), math.sin(angle - half)) * reach,
          sun + Offset(math.cos(angle + half), math.sin(angle + half)) * reach,
        ], true),
        _fill,
      );
    }
  }

  static void _fog(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    _fill.color = tint.withValues(alpha: 0.11 * alpha);
    const banks = 5;
    for (var i = 0; i < banks; i++) {
      final w = s.width * (0.7 + 0.25 * _frac(seed + i * 0.57));
      final h = s.height * (0.035 + 0.02 * i / banks);
      final span = s.width + w;
      final x = _frac(seed + i * 0.31 + t * (0.012 + i * 0.004)) * span - w;
      final y = s.height * (0.5 + i * 0.1);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(h / 2),
        ),
        _fill,
      );
    }
  }

  static void _heatWaves(
    Canvas c,
    Size s,
    Color tint,
    double t,
    double seed,
    double alpha,
  ) {
    const lines = 5;
    for (var i = 0; i < lines; i++) {
      final age = _frac(i / lines + t * 0.06 + seed);
      _line
        ..strokeWidth = 2
        ..color = tint.withValues(
          alpha: 0.42 * alpha * math.sin(age * math.pi),
        );
      c.drawPath(
        _wave(
          s,
          s.height * (1 - age * 0.55),
          s.height * 0.012,
          16,
          t * 2.2 + i,
        ),
        _line,
      );
    }
  }
}
