/// The animated sky of each campaign level as data. The painter is
/// lib/render/ambient_art.dart.
///
/// A level's animation combines two [AmbientKind]s with a [AmbientWind] and an
/// [AmbientTempo]. [LevelAnimation.forLevel] walks those combinations so no
/// two levels share one and neighbouring levels never share a main effect.
library;

/// Background effects. Each has its own shape and way of moving.
enum AmbientKind {
  snowfall('Snowfall'),
  rain('Rain'),
  embers('Embers'),
  fireflies('Fireflies'),
  bubbles('Bubbles'),
  petals('Petals'),
  leaves('Leaves'),
  sandstorm('Sandstorm'),
  twinkles('Twinkles'),
  meteors('Meteors'),
  comets('Comets'),
  lightning('Lightning'),
  aurora('Aurora'),
  ribbons('Ribbons'),
  ripples('Ripples'),
  orbs('Orbs'),
  spores('Spores'),
  shards('Shards'),
  confetti('Confetti'),
  sunbeams('Sunbeams'),
  fog('Fog'),
  swirl('Swirl'),
  birds('Birds'),
  heatWaves('Heat Waves');

  const AmbientKind(this.label);

  /// Name shown on the level card.
  final String label;
}

/// How the whole sky drifts sideways.
enum AmbientWind { still, left, right, gusty }

/// Overall animation speed.
enum AmbientTempo {
  slow(0.7),
  normal(1),
  brisk(1.35);

  const AmbientTempo(this.scale);
  final double scale;
}

/// Time of day washed over the sky. Still, so it stays on with reduced motion.
enum AmbientMood { clear, dawn, dusk, twilight, mist }

class LevelAnimation {
  const LevelAnimation({
    required this.level,
    required this.main,
    required this.accent,
    required this.wind,
    required this.tempo,
  });

  /// The animation of campaign level [level].
  factory LevelAnimation.forLevel(int level) {
    final i = level - 1;
    final kinds = AmbientKind.values.length;
    final main = i % kinds;
    // (main, offset) pairs repeat only after kinds * (kinds - 1) levels.
    final offset = 1 + (i ~/ kinds) % (kinds - 1);
    final cycle = i ~/ (kinds * (kinds - 1));
    return LevelAnimation(
      level: level,
      main: AmbientKind.values[main],
      accent: AmbientKind.values[(main + offset) % kinds],
      // The cycle shifts the wind, so a repeated pair still looks different.
      wind: AmbientWind.values[(i + cycle) % AmbientWind.values.length],
      tempo: AmbientTempo.values[(i ~/ 4 + i) % AmbientTempo.values.length],
    );
  }

  final int level;
  final AmbientKind main;
  final AmbientKind accent;
  final AmbientWind wind;
  final AmbientTempo tempo;

  AmbientMood get mood =>
      AmbientMood.values[(level - 1) % AmbientMood.values.length];

  /// Identifies the combination; distinct for every campaign level.
  String get key =>
      '${main.index}|${accent.index}|${wind.index}|${tempo.index}';

  /// Level card caption.
  String get label => '${main.label} & ${accent.label}';
}
