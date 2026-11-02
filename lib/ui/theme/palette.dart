import 'package:flutter/material.dart';

/// Design tokens for the whole game: the "Forge" look. Deep iron-indigo
/// glass panels, molten ember and brass accents, soft shadows instead of
/// hard cartoon outlines.
abstract final class Palette {
  static const background = Color(0xFF0F1428);
  static const backgroundTop = Color(0xFF1B2246);

  // Iron-glass panels with a light rim.
  static const panel = Color(0xFF1A2042);
  static const panelLight = Color(0xFF29315E);
  static const panelBorder = Color(0xFF414C86);
  static const panelInset = Color(0xFF111633);

  /// Deep ink used for strokes, text shadows and recessed wells.
  static const outline = Color(0xFF0A0D1F);

  // Warm "forge" panels for results and rewards (names kept from the
  // earlier wood style).
  static const wood = Color(0xFF261C3A);
  static const woodLight = Color(0xFF3A2B52);
  static const woodDark = Color(0xFFB8803A);

  static const cyan = Color(0xFF3FD8E8);
  static const blue = Color(0xFF4C7DFF);
  static const yellow = Color(0xFFFFD15C);
  static const orange = Color(0xFFFF8A3D);
  static const coral = Color(0xFFFF5D6C);
  static const purple = Color(0xFFA46BFF);
  static const green = Color(0xFF3EDB8A);
  static const gold = Color(0xFFFFC24A);

  /// Molten accent: the forge glow behind the brand.
  static const ember = Color(0xFFFF7A2B);

  /// Polished brass trim on panels and frames.
  static const brass = Color(0xFFE2B15C);

  static const text = Colors.white;
  static const textMuted = Color(0xFFB8BFE6);
  static const textDim = Color(0xFF6D76A8);

  /// Ball colours by size tier (0 = smallest). These tell the player how big
  /// a crystal is, so they stay fixed.
  static const ballTiers = [
    Color(0xFF3DA9FF), // sapphire
    Color(0xFF34D27A), // emerald
    Color(0xFFFFA22E), // amber
    Color(0xFFA766FF), // amethyst
    Color(0xFFFF4D6A), // ruby
  ];
}

abstract final class Gaps {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
}

/// Shadows shared by every raised surface.
abstract final class Elevation {
  static const panel = [
    BoxShadow(
      color: Color(0x73000000),
      offset: Offset(0, 10),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];

  static const control = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 5), blurRadius: 12),
  ];

  /// Coloured under-glow for a raised control of [color].
  static List<BoxShadow> glow(Color color, {double strength = 0.45}) => [
    BoxShadow(
      color: color.withValues(alpha: strength),
      offset: const Offset(0, 6),
      blurRadius: 18,
      spreadRadius: -4,
    ),
  ];
}

abstract final class TextStyles {
  static const display = 'RussoOne';

  /// Soft ink shadow that keeps white text readable over the world art
  /// without a hard cartoon outline.
  static const outlined = [
    Shadow(color: Color(0xCC0A0D1F), offset: Offset(0, 1.5)),
    Shadow(color: Color(0x800A0D1F), offset: Offset(0, 3), blurRadius: 8),
  ];

  static const title = TextStyle(
    fontFamily: display,
    fontSize: 26,
    color: Palette.text,
    letterSpacing: 0.6,
    shadows: outlined,
  );

  static const heading = TextStyle(
    fontFamily: display,
    fontSize: 19,
    color: Palette.text,
    letterSpacing: 0.4,
    shadows: outlined,
  );

  static const button = TextStyle(
    fontFamily: display,
    fontSize: 19,
    color: Palette.text,
    letterSpacing: 0.6,
    shadows: outlined,
  );

  static const number = TextStyle(
    fontFamily: display,
    fontSize: 18,
    color: Palette.text,
    letterSpacing: 0.3,
    shadows: outlined,
  );

  /// Small spaced capitals for labels above values.
  static const eyebrow = TextStyle(
    fontFamily: display,
    fontSize: 11,
    color: Palette.brass,
    letterSpacing: 2,
  );

  static const body = TextStyle(
    fontSize: 15,
    color: Palette.text,
    fontWeight: FontWeight.w600,
  );

  static const caption = TextStyle(
    fontSize: 12.5,
    color: Palette.textMuted,
    fontWeight: FontWeight.w600,
  );
}

String formatInt(int value) {
  final s = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}

/// Compact form used on balls: 999, 1.2K, 15K, 2.4M.
String formatCompact(int value) {
  if (value < 1000) return '$value';
  if (value < 10000) {
    final k = (value / 100).floor() / 10;
    return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)}K';
  }
  if (value < 1000000) return '${value ~/ 1000}K';
  final m = (value / 100000).floor() / 10;
  return '${m.toStringAsFixed(1)}M';
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.ember,
      brightness: Brightness.dark,
      surface: Palette.panel,
      primary: Palette.gold,
    ),
    scaffoldBackgroundColor: Palette.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        side: BorderSide(color: Palette.panelBorder),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.panelLight,
      contentTextStyle: TextStyles.body,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.ember
            : const Color(0xFF2C3361),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.gold,
      thumbColor: Colors.white,
      inactiveTrackColor: Color(0xFF2C3361),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.gold,
    ),
  );
}
