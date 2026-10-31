import 'package:flutter/material.dart' hide Element;

import '../../economy/catalog.dart';
import '../../game/sim/entities.dart';
import '../../render/ball_art.dart';
import '../../render/cannon_art.dart';
import '../../render/crystal_art.dart';
import '../../render/hud_art.dart';
import '../../render/icon_art.dart';
import '../../render/menu_icon_art.dart';
import '../../render/world_art.dart';

/// The illustrated world (sky, mountains, hills, ground) behind menus.
/// [groundFraction] is the share of the height covered by the ground band.
class WorldBackground extends StatelessWidget {
  const WorldBackground({
    super.key,
    required this.theme,
    this.child,
    this.groundFraction = 0.18,
    this.dim = 0,
  });

  final ArenaTheme theme;
  final Widget? child;
  final double groundFraction;

  /// 0..1 darkening of the upper area for text-heavy screens.
  final double dim;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WorldPainter(theme, groundFraction, dim),
      isComplex: true,
      willChange: false,
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter(this.theme, this.groundFraction, this.dim);
  final ArenaTheme theme;
  final double groundFraction;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    WorldArt.paintScene(
      canvas,
      size,
      theme,
      groundTop: size.height * (1 - groundFraction),
    );
    if (dim > 0) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0E1838).withValues(alpha: dim),
              const Color(0xFF0E1838).withValues(alpha: dim * 0.55),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) =>
      old.theme != theme ||
      old.groundFraction != groundFraction ||
      old.dim != dim;
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) => IconArt.coin(c, s.center(Offset.zero), s.shortestSide),
      size,
    ),
  );
}

class PowerUpIcon extends StatelessWidget {
  const PowerUpIcon({super.key, required this.type, this.size = 32});
  final PowerUpType type;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) => IconArt.powerUp(c, type, s.center(Offset.zero), s.shortestSide),
      Object.hash(type, size),
    ),
  );
}

class ElementIcon extends StatelessWidget {
  const ElementIcon({super.key, required this.element, this.size = 28});
  final Element element;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) =>
          HudArt.element(c, element, s.center(Offset.zero), s.shortestSide),
      Object.hash(element, size),
    ),
  );
}

class HeartIcon extends StatelessWidget {
  const HeartIcon({super.key, required this.filled, this.size = 22});
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) => HudArt.heart(
        c,
        s.center(Offset.zero),
        s.shortestSide,
        filled: filled,
      ),
      Object.hash(filled, size),
    ),
  );
}

class MenuIconView extends StatelessWidget {
  const MenuIconView({super.key, required this.icon, this.size = 44});
  final MenuIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) => MenuIconArt.draw(c, icon, s.shortestSide),
      Object.hash(icon, size),
    ),
  );
}

/// A crystal creature for menus and the tutorial.
class CrystalBadge extends StatelessWidget {
  const CrystalBadge({
    super.key,
    required this.tier,
    required this.label,
    this.size = 48,
    this.kind = EnemyKind.shard,
  });
  final int tier;
  final String label;
  final double size;
  final EnemyKind kind;

  static final _art = CrystalArt();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter((c, s) {
      final r = s.shortestSide * 0.36;
      final x = s.width / 2;
      final y = s.height / 2;
      switch (kind) {
        case EnemyKind.geode:
          _art.geode(
            c,
            x: x,
            y: y,
            r: r,
            coreColor: BallArt.colorForTier(tier),
            text: label,
            armorFraction: 0.6,
            variant: tier,
          );
        case EnemyKind.skyray:
          _art.skyray(
            c,
            x: x,
            y: y,
            r: r * 0.7,
            text: label,
            phase: 0.4,
            dropWarning: 0,
          );
        case EnemyKind.treasure:
          _art.treasure(c, x: x, y: y, r: r * 0.85, text: label, time: 0.4);
        case EnemyKind.shard:
          _art.shard(
            c,
            x: x,
            y: y,
            r: r,
            color: BallArt.colorForTier(tier),
            text: label,
            variant: tier,
          );
      }
    }, Object.hash(tier, label, size, kind)),
  );
}

/// A volatile hazard crystal for menus and the tutorial.
class HazardBadge extends StatelessWidget {
  const HazardBadge({super.key, required this.kind, this.size = 60});
  final HazardKind kind;
  final double size;

  static final _art = CrystalArt();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter((c, s) {
      c.save();
      c.translate(s.width / 2, s.height * 0.62);
      final scale = s.shortestSide / 70;
      c.scale(scale);
      _art.hazard(
        c,
        Hazard(id: kind.index, kind: kind, x: 0, y: 0, maxHp: 1),
        0.3,
      );
      c.restore();
    }, Object.hash(kind, size)),
  );
}

/// Cannon preview; the art is ~66x60 world units, scaled to [size].
class CannonPreview extends StatelessWidget {
  const CannonPreview({
    super.key,
    required this.skin,
    this.level = 1,
    this.size = 64,
    this.element = Element.kinetic,
  });
  final CannonSkin skin;
  final int level;
  final double size;
  final Element element;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FnPainter(
      (c, s) => CannonArt.draw(
        c,
        x: s.width / 2,
        baseY: s.height * 0.95,
        skin: skin,
        level: level,
        scale: s.shortestSide / 72,
        glowPulse: 0.6,
        wheelAngle: 0.3,
        core: element == Element.kinetic ? null : elementColor(element),
      ),
      Object.hash(skin.id, level, size, element),
    ),
  );
}

class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.theme});
  final ArenaTheme theme;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: CustomPaint(
      painter: _FnPainter(
        (c, s) => WorldArt.paintScene(c, s, theme, groundTop: s.height * 0.82),
        theme.id,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _FnPainter extends CustomPainter {
  _FnPainter(this.fn, this.key);
  final void Function(Canvas, Size) fn;
  final Object key;

  @override
  void paint(Canvas canvas, Size size) => fn(canvas, size);

  @override
  bool shouldRepaint(_FnPainter old) => old.key != key;
}
