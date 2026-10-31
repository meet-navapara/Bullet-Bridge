import 'dart:math' as math;
import 'dart:ui';

import '../ui/theme/palette.dart';

enum MenuIcon { upgrade, shop, daily, goals }

/// The main menu's feature icons, in the game's thick-outlined cartoon style.
/// Coordinates are fractions of a square of side `s`, with its corner at the
/// origin.
abstract final class MenuIconArt {
  static const _gold = (Color(0xFFFFF0A0), Color(0xFFFFA91F));

  static void draw(Canvas c, MenuIcon icon, double s) {
    switch (icon) {
      case MenuIcon.upgrade:
        _upgrade(c, s);
      case MenuIcon.shop:
        _shop(c, s);
      case MenuIcon.daily:
        _daily(c, s);
      case MenuIcon.goals:
        _goals(c, s);
    }
  }

  static Path _poly(double s, List<(double, double)> points) =>
      Path()
        ..addPolygon([for (final (x, y) in points) Offset(x * s, y * s)], true);

  static Path _box(
    double s,
    double l,
    double t,
    double r,
    double b,
    double k,
  ) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(l * s, t * s, r * s, b * s),
        Radius.circular(k * s),
      ),
    );

  static void _outline(Canvas c, Path path, double s) => c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s * 0.075
      ..color = Palette.outline,
  );

  static void _fill(Canvas c, Path path, (Color, Color) colors) {
    final b = path.getBounds();
    c.drawPath(
      path,
      Paint()
        ..shader = Gradient.linear(b.topCenter, b.bottomCenter, [
          colors.$1,
          colors.$2,
        ]),
    );
  }

  static void _shape(Canvas c, Path path, (Color, Color) colors, double s) {
    _outline(c, path, s);
    _fill(c, path, colors);
  }

  /// A thick upward arrow on two level bars.
  static void _upgrade(Canvas c, double s) {
    _shape(c, _box(s, 0.32, 0.8, 0.68, 0.93, 0.03), _gold, s);
    _shape(c, _box(s, 0.32, 0.65, 0.68, 0.76, 0.03), _gold, s);
    final arrow = _poly(s, const [
      (0.5, 0.05),
      (0.9, 0.42),
      (0.68, 0.42),
      (0.68, 0.6),
      (0.32, 0.6),
      (0.32, 0.42),
      (0.1, 0.42),
    ]);
    _shape(c, arrow, _gold, s);
    // Light catching the arrow's left side.
    c.drawPath(
      _poly(s, const [
        (0.5, 0.11),
        (0.5, 0.56),
        (0.36, 0.56),
        (0.36, 0.38),
        (0.2, 0.38),
      ]),
      Paint()..color = const Color(0x55FFFFFF),
    );
  }

  /// A little storefront under a striped awning.
  static void _shop(Canvas c, double s) {
    _shape(c, _box(s, 0.14, 0.34, 0.86, 0.93, 0.03), const (
      Color(0xFFFFE9C7),
      Color(0xFFEDBE85),
    ), s);
    // Window and door.
    final window = _box(s, 0.22, 0.56, 0.47, 0.76, 0.02);
    _outline(c, window, s * 0.6);
    _fill(c, window, const (Color(0xFFB6F0FF), Color(0xFF4FBDF0)));
    final door = _box(s, 0.56, 0.56, 0.78, 0.93, 0.02);
    _outline(c, door, s * 0.6);
    _fill(c, door, const (Color(0xFF8A5A33), Color(0xFF5C3A1E)));
    c.drawCircle(
      Offset(0.73 * s, 0.75 * s),
      0.025 * s,
      Paint()..color = Palette.yellow,
    );

    // Awning: scalloped stripes, widening towards the bottom.
    const stripes = 5;
    const top = 0.08;
    const bottom = 0.38;
    double topX(int i) => 0.2 + 0.6 * i / stripes;
    double bottomX(int i) => 0.05 + 0.9 * i / stripes;
    Path stripe(int i) {
      final r = (bottomX(i + 1) - bottomX(i)) / 2 * s;
      return Path()
        ..moveTo(topX(i) * s, top * s)
        ..lineTo(topX(i + 1) * s, top * s)
        ..lineTo(bottomX(i + 1) * s, bottom * s)
        ..arcToPoint(
          Offset(bottomX(i) * s, bottom * s),
          radius: Radius.circular(r),
        )
        ..close();
    }

    final awning = Path();
    for (var i = 0; i < stripes; i++) {
      awning.addPath(stripe(i), Offset.zero);
    }
    _outline(c, awning, s);
    for (var i = 0; i < stripes; i++) {
      _fill(
        c,
        stripe(i),
        i.isEven
            ? const (Color(0xFFFF7A7E), Color(0xFFE5394B))
            : const (Color(0xFFFFFFFF), Color(0xFFE9ECF4)),
      );
    }
  }

  /// A gift box with a gold ribbon and bow.
  static void _daily(Canvas c, double s) {
    void loop(double x, double angle) {
      c.save();
      c.translate(x * s, 0.2 * s);
      c.rotate(angle);
      final bow = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 0.32 * s,
            height: 0.19 * s,
          ),
        );
      _shape(c, bow, _gold, s);
      c.restore();
    }

    loop(0.33, 0.45);
    loop(0.67, -0.45);

    const box = (Color(0xFF7FE3FF), Color(0xFF2A8FE8));
    _shape(c, _box(s, 0.15, 0.46, 0.85, 0.93, 0.05), box, s);
    _fill(c, _box(s, 0.41, 0.46, 0.59, 0.93, 0), _gold);
    _shape(c, _box(s, 0.08, 0.3, 0.92, 0.5, 0.05), box, s);
    _fill(c, _box(s, 0.41, 0.3, 0.59, 0.5, 0), _gold);
    final knot = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(0.5 * s, 0.26 * s), radius: 0.08 * s),
      );
    _shape(c, knot, _gold, s);
  }

  /// A gold trophy with a star on the cup.
  static void _goals(Canvas c, double s) {
    Path handle(double side) => Path()
      ..moveTo((0.5 + side * 0.26) * s, 0.16 * s)
      ..cubicTo(
        (0.5 + side * 0.52) * s,
        0.14 * s,
        (0.5 + side * 0.5) * s,
        0.46 * s,
        (0.5 + side * 0.18) * s,
        0.5 * s,
      );
    for (final side in const [-1.0, 1.0]) {
      c.drawPath(
        handle(side),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.15
          ..color = Palette.outline,
      );
      c.drawPath(
        handle(side),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.075
          ..color = const Color(0xFFFFC233),
      );
    }

    _shape(c, _box(s, 0.25, 0.8, 0.75, 0.94, 0.03), const (
      Color(0xFF8A5A33),
      Color(0xFF5C3A1E),
    ), s);
    _shape(c, _box(s, 0.42, 0.56, 0.58, 0.82, 0), _gold, s);
    final cup = Path()
      ..moveTo(0.23 * s, 0.06 * s)
      ..lineTo(0.77 * s, 0.06 * s)
      ..cubicTo(0.79 * s, 0.38 * s, 0.68 * s, 0.62 * s, 0.5 * s, 0.63 * s)
      ..cubicTo(0.32 * s, 0.62 * s, 0.21 * s, 0.38 * s, 0.23 * s, 0.06 * s)
      ..close();
    _shape(c, cup, _gold, s);

    final star = Path();
    const center = Offset(0.5, 0.31);
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 0.15 : 0.065;
      final p = (center + Offset(math.cos(a), math.sin(a)) * r) * s;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    c.drawPath(star, Paint()..color = const Color(0xFFE8820C));
  }
}
