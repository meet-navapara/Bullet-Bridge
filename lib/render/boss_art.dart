part of 'crystal_art.dart';

/// Silhouettes of the ten campaign bosses. All are geometric crystal
/// constructs (no faces): each has its own outline, motion and colours, and
/// its plates/heads are drawn where the simulation places their hitboxes.
extension BossArt on CrystalArt {
  void boss(Canvas c, Boss b, double time) {
    final def = b.def;
    final r = def.coreRadius;
    final color = def.colorFor(b.phase);
    final flash = b.hitFlash / BallSpec.hitFlashTime;
    final center = Offset(b.x, b.y);

    // The throwing motion: rears up and tenses, then lunges down at release.
    final pose = b.throwPose;
    c.save();
    c.translate(b.x, b.y + pose * r * 0.22);
    final squash = 1 + pose * 0.1;
    c.scale(1 / squash, squash);
    c.translate(-b.x, -b.y);

    // Aura: brighter while it is not attacking (entrance / phase change).
    final aura = b.transition > 0 ? 1.0 : 0.5 + 0.15 * math.sin(time * 4);
    _fill.shader = ui.Gradient.radial(center, r * 2.3, [
      color.withValues(alpha: 0.42 * aura),
      color.withValues(alpha: 0),
    ]);
    c.drawCircle(center, r * 2.3, _fill);
    _fill.shader = null;

    c.save();
    c.translate(b.x, b.y);
    switch (def.shape) {
      case BossShape.colossus:
        _colossus(c, b, r, color, flash, time);
      case BossShape.engine:
        _engine(c, b, r, color, flash, time);
      case BossShape.titan:
        _titan(c, b, r, color, flash, time);
      case BossShape.guardian:
        _guardian(c, b, r, color, flash, time);
      case BossShape.devourer:
        _devourer(c, b, r, color, flash, time);
      case BossShape.behemoth:
        _behemoth(c, b, r, color, flash, time);
      case BossShape.hydra:
        _hydra(c, b, r, color, flash, time);
      case BossShape.gravity:
        _gravity(c, b, r, color, flash, time);
      case BossShape.architect:
        _architect(c, b, r, color, flash, time);
      case BossShape.worldbreaker:
        _worldbreaker(c, b, r, color, flash, time);
    }
    if (b.hasWeakWindows) _rift(c, b, r, time);
    c.restore();
    _plates(c, b, color, flash);
    c.restore();
  }

  // ------------------------------------------------------------- shared

  void _plates(Canvas c, Boss b, Color color, double flash) {
    for (var i = 0; i < b.plates.length; i++) {
      if (b.plates[i] <= 0) continue;
      final p = b.def.plates[i];
      final weakness = p.weakness;
      if (weakness != null) {
        // A head: an element-coloured gem with a bright ring.
        final hc = elementColor(weakness);
        c.save();
        c.translate(b.plateX(i), b.plateY(i));
        _glow(c, p.radius * 1.6, hc, 0.5);
        _gem(c, p.radius, hc, facets: 5, variant: i, flash: flash * 0.5);
        _stroke
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85)
          ..strokeWidth = 2.5;
        c.drawCircle(Offset.zero, p.radius * 1.12, _stroke);
        c.restore();
        continue;
      }
      geode(
        c,
        x: b.plateX(i),
        y: b.plateY(i),
        r: p.radius,
        coreColor: color,
        text: '',
        armorFraction: b.plates[i] / Boss.plateMax,
        variant: 7 + i,
        flash: flash,
      );
    }
  }

  /// Pulsing energy core in the middle of a body.
  void _core(Canvas c, int phase, double r, double time, {Color? tint}) {
    final coreColor =
        tint ??
        switch (phase) {
          1 => const Color(0xFFFFFFFF),
          2 => const Color(0xFFFFE07A),
          _ => const Color(0xFFFF6A4A),
        };
    final beat = 0.85 + 0.15 * math.sin(time * (3 + phase * 1.5));
    c.save();
    c.scale(beat);
    _glow(c, r * 0.7, coreColor, 0.85);
    c.restore();
    _fill.color = coreColor;
    c.drawCircle(Offset.zero, r * 0.16 * beat, _fill);
  }

  /// Weak point (Void Devourer, Worldbreaker): a four-point star crack that
  /// glows while the weak window is open and flickers just before.
  void _rift(Canvas c, Boss b, double r, double time) {
    final open = b.weak == WeakState.open;
    final warn = b.weak == WeakState.warning;
    final alpha = open
        ? 1.0
        : warn
        ? 0.4 + 0.4 * ((math.sin(time * 30) + 1) / 2)
        : 0.18;
    final s = r * (open ? 0.62 : 0.42);
    final star = Path()
      ..moveTo(0, -s)
      ..lineTo(s * 0.18, -s * 0.18)
      ..lineTo(s, 0)
      ..lineTo(s * 0.18, s * 0.18)
      ..lineTo(0, s)
      ..lineTo(-s * 0.18, s * 0.18)
      ..lineTo(-s, 0)
      ..lineTo(-s * 0.18, -s * 0.18)
      ..close();
    if (open) _glow(c, r * 0.9, const Color(0xFFFFF27A), 0.8);
    _fill.color = Color.fromRGBO(255, 248, 200, alpha);
    c.drawPath(star, _fill);
    _stroke
      ..color = _outline.withValues(alpha: alpha)
      ..strokeWidth = 2;
    c.drawPath(star, _stroke);
  }

  Path _polygon(int n, double radius, {double rotation = 0}) {
    final pts = [
      for (var k = 0; k < n; k++)
        Offset(
          math.cos(rotation + k / n * math.pi * 2) * radius,
          math.sin(rotation + k / n * math.pi * 2) * radius,
        ),
    ];
    return Path()..addPolygon(pts, true);
  }

  void _outlined(Canvas c, Path p, Color fill, {double width = 2.4}) {
    _fill.color = fill;
    c.drawPath(p, _fill);
    _stroke
      ..color = _outline
      ..strokeWidth = width;
    c.drawPath(p, _stroke);
  }

  // ------------------------------------------------------------- shapes

  void _colossus(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    for (var k = 0; k < 5; k++) {
      final a = time * (0.8 + b.phase * 0.25) + k * math.pi * 2 / 5;
      c.save();
      c.translate(math.cos(a) * r * 1.5, math.sin(a) * r * 0.55 + r * 0.1);
      c.rotate(a);
      _gem(c, r * 0.16, shade(color, 0.2), facets: 4, variant: k);
      c.restore();
    }
    for (var k = -1; k <= 1; k++) {
      final h = r * (k == 0 ? 0.75 : 0.5);
      final bx = k * r * 0.45;
      _outlined(
        c,
        Path()
          ..moveTo(bx - r * 0.17, -r * 0.8)
          ..lineTo(bx + k * r * 0.1, -r * 0.8 - h)
          ..lineTo(bx + r * 0.17, -r * 0.8)
          ..close(),
        shade(color, 0.3),
      );
    }
    _gem(c, r, color, facets: 6, variant: 2, outlineWidth: 3, flash: flash);
    _core(c, b.phase, r, time);
  }

  void _engine(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A spinning cog with sparks crackling off its teeth.
    const teeth = 12;
    final spin = time * (0.6 + b.phase * 0.35);
    final gear = Path();
    for (var k = 0; k < teeth * 2; k++) {
      final a = spin + k / (teeth * 2) * math.pi * 2;
      final rr = k.isEven ? r * 1.18 : r * 0.98;
      final p = Offset(math.cos(a) * rr, math.sin(a) * rr);
      k == 0 ? gear.moveTo(p.dx, p.dy) : gear.lineTo(p.dx, p.dy);
    }
    gear.close();
    _outlined(c, gear, shade(color, -0.3), width: 3);
    final rng = math.Random((time * 12).floor());
    _stroke
      ..color = const Color(0xFFFFF27A)
      ..strokeWidth = 2.2;
    for (var k = 0; k < 3; k++) {
      final a = rng.nextDouble() * math.pi * 2;
      var p = Offset(math.cos(a) * r * 1.15, math.sin(a) * r * 1.15);
      final path = Path()..moveTo(p.dx, p.dy);
      for (var j = 0; j < 3; j++) {
        p += Offset(
          math.cos(a) * r * 0.16 + rng.nextDouble() * 10 - 5,
          math.sin(a) * r * 0.16 + rng.nextDouble() * 10 - 5,
        );
        path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, _stroke);
    }
    _gem(c, r * 0.8, color, facets: 8, variant: 1, flash: flash);
    _core(c, b.phase, r * 0.9, time, tint: const Color(0xFFFFF27A));
  }

  void _titan(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A lumpy rock body split by glowing lava seams.
    final rng = math.Random(31);
    final pts = [
      for (var k = 0; k < 13; k++)
        Offset(
          math.cos(k / 13 * math.pi * 2) * r * (1.0 + rng.nextDouble() * 0.16),
          math.sin(k / 13 * math.pi * 2) * r * (0.92 + rng.nextDouble() * 0.14),
        ),
    ];
    final rock = Path()..addPolygon(pts, true);
    _fill.shader = ui.Gradient.radial(
      Offset(-r * 0.3, -r * 0.4),
      r * 1.6,
      [
        const Color(0xFF9A7A66),
        const Color(0xFF5A4438),
        const Color(0xFF2E221C),
      ],
      const [0, 0.5, 1],
    );
    c.drawPath(rock, _fill);
    _fill.shader = null;
    final glow = 0.6 + 0.4 * math.sin(time * 3);
    _stroke
      ..color = Color.lerp(color, const Color(0xFFFFE07A), glow)!
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 5; k++) {
      final a = k * 1.26 + 0.3;
      c.drawPath(
        Path()
          ..moveTo(math.cos(a) * r * 0.3, math.sin(a) * r * 0.3)
          ..lineTo(math.cos(a + 0.2) * r * 0.65, math.sin(a + 0.2) * r * 0.65)
          ..lineTo(math.cos(a - 0.1) * r * 0.95, math.sin(a - 0.1) * r * 0.95),
        _stroke,
      );
    }
    _stroke
      ..color = _outline
      ..strokeWidth = 3;
    c.drawPath(rock, _stroke);
    _gem(c, r * 0.45, color, facets: 6, variant: 0, flash: flash);
    _core(c, b.phase, r * 0.6, time, tint: const Color(0xFFFFD23F));
  }

  void _guardian(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A slowly turning snowflake of ice spikes around a hexagonal gem.
    final spin = time * 0.35;
    for (var k = 0; k < 6; k++) {
      final a = spin + k * math.pi / 3;
      c.save();
      c.rotate(a);
      _outlined(
        c,
        Path()
          ..moveTo(0, -r * 0.6)
          ..lineTo(r * 0.16, -r * 1.0)
          ..lineTo(0, -r * 1.42)
          ..lineTo(-r * 0.16, -r * 1.0)
          ..close(),
        shade(color, 0.35),
        width: 2,
      );
      c.restore();
    }
    _gem(c, r * 0.85, color, facets: 6, variant: 0, flash: flash);
    _core(c, b.phase, r * 0.8, time, tint: const Color(0xFFE8FBFF));
  }

  void _devourer(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A dark disc ringed by orbiting fragments.
    for (var k = 0; k < 8; k++) {
      final a = -time * 0.9 + k * math.pi / 4;
      c.save();
      c.translate(math.cos(a) * r * 1.45, math.sin(a) * r * 1.45);
      c.rotate(a);
      _gem(c, r * 0.13, shade(color, 0.25), facets: 4, variant: k);
      c.restore();
    }
    _fill.shader = ui.Gradient.radial(
      Offset.zero,
      r,
      [const Color(0xFF05020E), shade(color, -0.5), color],
      const [0, 0.7, 1],
    );
    c.drawCircle(Offset.zero, r, _fill);
    _fill.shader = null;
    if (flash > 0) {
      _fill.color = const Color(0xFFFFFFFF).withValues(alpha: flash * 0.25);
      c.drawCircle(Offset.zero, r, _fill);
    }
    _stroke
      ..color = shade(color, 0.3)
      ..strokeWidth = 6;
    c.drawCircle(Offset.zero, r * 1.18, _stroke);
    _stroke
      ..color = _outline
      ..strokeWidth = 3;
    c.drawCircle(Offset.zero, r, _stroke);
  }

  void _behemoth(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A riveted iron hull with a gem viewport.
    final hull = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 2.2, height: r * 1.7),
      Radius.circular(r * 0.35),
    );
    _fill.shader = ui.Gradient.linear(Offset(0, -r), Offset(0, r), [
      shade(color, 0.3),
      shade(color, -0.35),
    ]);
    c.drawRRect(hull, _fill);
    _fill.shader = null;
    _fill.color = shade(color, -0.45);
    for (var k = -1; k <= 1; k += 2) {
      c.drawRect(
        Rect.fromCenter(
          center: Offset(k * r * 0.62, r * 0.45),
          width: r * 0.36,
          height: r * 0.12,
        ),
        _fill,
      );
    }
    _fill.color = shade(color, 0.5);
    for (var k = 0; k < 8; k++) {
      final x = -r * 0.9 + k * r * 1.8 / 7;
      c.drawCircle(Offset(x, -r * 0.68), 3, _fill);
      c.drawCircle(Offset(x, r * 0.68), 3, _fill);
    }
    _stroke
      ..color = _outline
      ..strokeWidth = 3;
    c.drawRRect(hull, _stroke);
    if (flash > 0) {
      _fill.color = const Color(0xFFFFFFFF).withValues(alpha: flash * 0.2);
      c.drawRRect(hull, _fill);
    }
    _gem(c, r * 0.5, const Color(0xFFFF8A3D), facets: 8, variant: 1);
    _core(c, b.phase, r * 0.55, time);
  }

  void _hydra(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // Necks to every head (broken heads leave a stump).
    for (var i = 0; i < b.plates.length; i++) {
      final p = b.def.plates[i];
      final alive = b.plates[i] > 0;
      final sway = math.sin(time * 2 + i) * 6;
      final end = Offset(p.dx + sway * 0.3, p.dy) * (alive ? 1 : 0.55);
      final neck = Path()
        ..moveTo(0, -r * 0.3)
        ..quadraticBezierTo(end.dx * 0.2 + sway, end.dy * 0.6, end.dx, end.dy);
      _stroke
        ..color = _outline
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round;
      c.drawPath(neck, _stroke);
      _stroke
        ..color = shade(color, -0.1)
        ..strokeWidth = 10;
      c.drawPath(neck, _stroke);
    }
    _gem(c, r, color, facets: 7, variant: 2, outlineWidth: 3, flash: flash);
    _core(c, b.phase, r, time);
  }

  void _gravity(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A sphere inside two tilted orbit rings with beads riding them.
    void ring(double tilt, double phase) {
      c.save();
      c.rotate(tilt);
      _stroke
        ..color = shade(color, 0.35).withValues(alpha: 0.85)
        ..strokeWidth = 4;
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r * 3.0,
        height: r * 0.9,
      );
      c.drawOval(rect, _stroke);
      _fill.color = const Color(0xFFE8F0FF);
      for (var k = 0; k < 3; k++) {
        final a = phase + k * math.pi * 2 / 3;
        c.drawCircle(
          Offset(math.cos(a) * r * 1.5, math.sin(a) * r * 0.45),
          5,
          _fill,
        );
      }
      c.restore();
    }

    ring(0.35, time * 1.4);
    ring(-0.35, -time * 1.1);
    _gem(c, r, color, facets: 10, variant: 0, outlineWidth: 3, flash: flash);
    _core(c, b.phase, r, time, tint: const Color(0xFFDDE6FF));
  }

  void _architect(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // Counter-rotating triangle and square frames around a diamond.
    final tri = _polygon(3, r * 1.55, rotation: time * 0.7);
    final sq = _polygon(4, r * 1.3, rotation: -time * 0.5);
    _fill.color = color.withValues(alpha: 0.25);
    c.drawPath(tri, _fill);
    _stroke
      ..color = shade(color, 0.3)
      ..strokeWidth = 4;
    c.drawPath(tri, _stroke);
    _stroke.color = shade(color, -0.2);
    c.drawPath(sq, _stroke);
    _gem(c, r * 0.85, color, facets: 4, variant: 1, flash: flash);
    _core(c, b.phase, r * 0.85, time);
  }

  void _worldbreaker(
    Canvas c,
    Boss b,
    double r,
    Color color,
    double flash,
    double time,
  ) {
    // A broken planet with a ring of debris; cracks spread each phase.
    for (var k = 0; k < 10; k++) {
      final a = time * 0.5 + k * math.pi / 5;
      c.save();
      c.translate(math.cos(a) * r * 1.5, math.sin(a) * r * 0.5);
      c.rotate(a * 2);
      _gem(c, r * 0.12, shade(color, 0.2), facets: 4, variant: k);
      c.restore();
    }
    _fill.shader = ui.Gradient.radial(
      Offset(-r * 0.3, -r * 0.3),
      r * 1.4,
      [shade(color, 0.25), shade(color, -0.35), const Color(0xFF1A0A10)],
      const [0, 0.6, 1],
    );
    c.drawCircle(Offset.zero, r, _fill);
    _fill.shader = null;
    _stroke
      ..color = const Color(0xFFFFD27A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < b.phase + 2; k++) {
      final a = k * 2.1 + 0.5;
      c.drawPath(
        Path()
          ..moveTo(math.cos(a) * r * 0.2, math.sin(a) * r * 0.2)
          ..lineTo(math.cos(a + 0.3) * r * 0.6, math.sin(a + 0.3) * r * 0.6)
          ..lineTo(math.cos(a) * r * 0.96, math.sin(a) * r * 0.96),
        _stroke,
      );
    }
    if (flash > 0) {
      _fill.color = const Color(0xFFFFFFFF).withValues(alpha: flash * 0.25);
      c.drawCircle(Offset.zero, r, _fill);
    }
    _stroke
      ..color = _outline
      ..strokeWidth = 3.5;
    c.drawCircle(Offset.zero, r, _stroke);
  }
}
