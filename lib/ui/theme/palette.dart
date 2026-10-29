import 'package:flutter/material.dart';

/// Design tokens for the whole game. Colours, spacing, radii and type.
abstract final class Palette {
  static const background = Color(0xFF1B2D5C);
  static const backgroundTop = Color(0xFF24407A);

  // Cartoon slate-blue panels with a thick dark outline.
  static const panel = Color(0xFF1F3466);
  static const panelLight = Color(0xFF2C4A8C);
  static const panelBorder = Color(0xFF15172E);
  static const panelInset = Color(0xFF162650);
  static const outline = Color(0xFF15172E);

  // Warm "wood" panels for lists and rewards.
  static const wood = Color(0xFFB8733C);
  static const woodLight = Color(0xFFD9944F);
  static const woodDark = Color(0xFF7A4520);

  static const cyan = Color(0xFF3DC8FF);
  static const blue = Color(0xFF2F7BFF);
  static const yellow = Color(0xFFFFCF2E);
  static const orange = Color(0xFFFF8A3D);
  static const coral = Color(0xFFFF5A5F);
  static const purple = Color(0xFFA35CFF);
  static const green = Color(0xFF3FD96B);
  static const gold = Color(0xFFFFC43D);

  static const text = Colors.white;
  static const textMuted = Color(0xFFC9D6FF);
  static const textDim = Color(0xFF6B78B3);

  /// Ball colours by size tier (0 = smallest).
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
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
}

abstract final class TextStyles {
  static const display = 'LilitaOne';

  /// Cartoon outline: eight hard dark shadows around the glyphs plus a
  /// drop shadow. Keeps white text readable over the bright world.
  static const outlined = [
    Shadow(color: Palette.outline, offset: Offset(1.6, 0)),
    Shadow(color: Palette.outline, offset: Offset(-1.6, 0)),
    Shadow(color: Palette.outline, offset: Offset(0, 1.6)),
    Shadow(color: Palette.outline, offset: Offset(0, -1.6)),
    Shadow(color: Palette.outline, offset: Offset(1.2, 1.2)),
    Shadow(color: Palette.outline, offset: Offset(-1.2, 1.2)),
    Shadow(color: Palette.outline, offset: Offset(1.2, -1.2)),
    Shadow(color: Palette.outline, offset: Offset(-1.2, -1.2)),
    Shadow(color: Palette.outline, offset: Offset(0, 3.2)),
  ];

  static const title = TextStyle(
    fontFamily: display,
    fontSize: 30,
    color: Palette.text,
    letterSpacing: 0.5,
    shadows: outlined,
  );

  static const heading = TextStyle(
    fontFamily: display,
    fontSize: 22,
    color: Palette.text,
    letterSpacing: 0.3,
    shadows: outlined,
  );

  static const button = TextStyle(
    fontFamily: display,
    fontSize: 22,
    color: Palette.text,
    letterSpacing: 0.4,
    shadows: outlined,
  );

  static const number = TextStyle(
    fontFamily: display,
    fontSize: 20,
    color: Palette.text,
    shadows: outlined,
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
      seedColor: Palette.blue,
      brightness: Brightness.dark,
      surface: Palette.panel,
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
        side: BorderSide(color: Palette.panelBorder, width: 2),
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
            ? Palette.green
            : const Color(0xFF3A4475),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.cyan,
      thumbColor: Colors.white,
      inactiveTrackColor: Color(0xFF2A3570),
    ),
  );
}
