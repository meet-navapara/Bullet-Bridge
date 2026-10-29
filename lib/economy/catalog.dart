import 'dart:ui';

/// A cannon colour scheme. Purely cosmetic.
class CannonSkin {
  const CannonSkin({
    required this.id,
    required this.name,
    required this.price,
    required this.body,
    required this.bodyDark,
    required this.accent,
    required this.glow,
    required this.carriage,
    this.rewardChapter,
  });

  final String id;
  final String name;
  final int price;

  /// Reward-only skins are earned by beating this chapter's boss and
  /// cannot be bought.
  final int? rewardChapter;
  bool get rewardOnly => rewardChapter != null;

  /// Barrel metal.
  final Color body;
  final Color bodyDark;

  /// Bands, wheel hubs and trim.
  final Color accent;
  final Color glow;

  /// Wooden/painted carriage between the wheels.
  final Color carriage;
}

/// A sky/time-of-day palette for the World 1 backdrop. Purely cosmetic.
/// (Ids are kept from earlier versions so owned themes stay owned.)
class ArenaTheme {
  const ArenaTheme({
    required this.id,
    required this.name,
    required this.price,
    required this.skyTop,
    required this.skyBottom,
    required this.sun,
    required this.cloud,
    required this.farMountain,
    required this.midMountain,
    required this.snow,
    required this.hill,
    required this.ground,
    required this.groundDark,
    this.stars = false,
  });

  final String id;
  final String name;
  final int price;
  final Color skyTop;
  final Color skyBottom;
  final Color sun;
  final Color cloud;
  final Color farMountain;
  final Color midMountain;
  final Color snow;
  final Color hill;
  final Color ground;
  final Color groundDark;
  final bool stars;
}

abstract final class Catalog {
  static const defaultSkinId = 'cobalt';
  static const defaultThemeId = 'deep_space';

  static const List<CannonSkin> skins = [
    CannonSkin(
      id: 'cobalt',
      name: 'Ironhide',
      price: 0,
      body: Color(0xFF7D8AA3),
      bodyDark: Color(0xFF3E465A),
      accent: Color(0xFFFF8A1F),
      glow: Color(0xFF7FD8FF),
      carriage: Color(0xFFD9692A),
    ),
    CannonSkin(
      id: 'ember',
      name: 'Ember',
      price: 500,
      body: Color(0xFFE5533D),
      bodyDark: Color(0xFF7E1F22),
      accent: Color(0xFFFFD23F),
      glow: Color(0xFFFF9A3D),
      carriage: Color(0xFF5A2E1E),
    ),
    CannonSkin(
      id: 'nebula',
      name: 'Amethyst',
      price: 1000,
      body: Color(0xFFA066F0),
      bodyDark: Color(0xFF4B2490),
      accent: Color(0xFF5CF2FF),
      glow: Color(0xFFD27BFF),
      carriage: Color(0xFF2E2A5C),
    ),
    CannonSkin(
      id: 'viper',
      name: 'Jungle',
      price: 2500,
      body: Color(0xFF3DBE6E),
      bodyDark: Color(0xFF175E37),
      accent: Color(0xFFFFE15C),
      glow: Color(0xFF7CFFB2),
      carriage: Color(0xFF7A4B26),
    ),
    CannonSkin(
      id: 'blossom',
      name: 'Bubblegum',
      price: 2500,
      body: Color(0xFFFF7CC4),
      bodyDark: Color(0xFF9A2E6E),
      accent: Color(0xFF7FE9FF),
      glow: Color(0xFFFF9AD6),
      carriage: Color(0xFF6A3FA0),
    ),
    CannonSkin(
      id: 'solar',
      name: 'Royal Gold',
      price: 5000,
      body: Color(0xFFFFC23A),
      bodyDark: Color(0xFF9A5E00),
      accent: Color(0xFFFFFFFF),
      glow: Color(0xFFFFE07A),
      carriage: Color(0xFF8E1F3A),
    ),
    // Boss rewards (see lib/config/bosses.dart).
    CannonSkin(
      id: 'storm',
      name: 'Storm Engine',
      price: 0,
      rewardChapter: 2,
      body: Color(0xFF4A7BD0),
      bodyDark: Color(0xFF1E2E66),
      accent: Color(0xFFFFE14A),
      glow: Color(0xFF8FD0FF),
      carriage: Color(0xFF2A3A5A),
    ),
    CannonSkin(
      id: 'glacier',
      name: 'Glacier',
      price: 0,
      rewardChapter: 4,
      body: Color(0xFFBDEBFF),
      bodyDark: Color(0xFF4A8AB8),
      accent: Color(0xFFFFFFFF),
      glow: Color(0xFF7FE6FF),
      carriage: Color(0xFF3A6A9A),
    ),
    CannonSkin(
      id: 'forge',
      name: 'Iron Forge',
      price: 0,
      rewardChapter: 6,
      body: Color(0xFF6A6E78),
      bodyDark: Color(0xFF2A2C32),
      accent: Color(0xFFFF7A2B),
      glow: Color(0xFFFFB066),
      carriage: Color(0xFF5A3A2A),
    ),
    CannonSkin(
      id: 'gravity',
      name: 'Event Horizon',
      price: 0,
      rewardChapter: 8,
      body: Color(0xFF3A3AA0),
      bodyDark: Color(0xFF14143A),
      accent: Color(0xFFE05CFF),
      glow: Color(0xFF8A9BFF),
      carriage: Color(0xFF241A4A),
    ),
    CannonSkin(
      id: 'worldbreaker',
      name: 'Worldbreaker',
      price: 0,
      rewardChapter: 10,
      body: Color(0xFFE0402A),
      bodyDark: Color(0xFF5A0E10),
      accent: Color(0xFFFFE04D),
      glow: Color(0xFFFF9A3D),
      carriage: Color(0xFF1A0A10),
    ),
  ];

  static const List<ArenaTheme> themes = [
    ArenaTheme(
      id: 'deep_space',
      name: 'Highland Day',
      price: 0,
      skyTop: Color(0xFF5FB4F5),
      skyBottom: Color(0xFFC9EBFF),
      sun: Color(0xFFFFF6C9),
      cloud: Color(0xFFFFFFFF),
      farMountain: Color(0xFF9CC4E4),
      midMountain: Color(0xFF5F98C2),
      snow: Color(0xFFF4FBFF),
      hill: Color(0xFF8ED36F),
      ground: Color(0xFF3FC54B),
      groundDark: Color(0xFF239A35),
    ),
    ArenaTheme(
      id: 'crimson_nebula',
      name: 'Ember Sunset',
      price: 800,
      skyTop: Color(0xFFF2785C),
      skyBottom: Color(0xFFFFD39A),
      sun: Color(0xFFFFF0B8),
      cloud: Color(0xFFFFE2D2),
      farMountain: Color(0xFFD08A8C),
      midMountain: Color(0xFF9C5A74),
      snow: Color(0xFFFFE9E0),
      hill: Color(0xFFC0A05A),
      ground: Color(0xFFD99A3A),
      groundDark: Color(0xFF9E5F22),
    ),
    ArenaTheme(
      id: 'aurora',
      name: 'Aurora Night',
      price: 1500,
      skyTop: Color(0xFF0E1A46),
      skyBottom: Color(0xFF2A6C8C),
      sun: Color(0xFFE8F6FF),
      cloud: Color(0xFF6FA8C8),
      farMountain: Color(0xFF3C5F8A),
      midMountain: Color(0xFF26446A),
      snow: Color(0xFFCDEBFF),
      hill: Color(0xFF2E7A6A),
      ground: Color(0xFF2E9C74),
      groundDark: Color(0xFF17614A),
      stars: true,
    ),
    ArenaTheme(
      id: 'sunset_rift',
      name: 'Golden Hour',
      price: 3000,
      skyTop: Color(0xFFFFA94D),
      skyBottom: Color(0xFFFFE7A8),
      sun: Color(0xFFFFFFFF),
      cloud: Color(0xFFFFF4DC),
      farMountain: Color(0xFFE0A77A),
      midMountain: Color(0xFFB4705A),
      snow: Color(0xFFFFF6EA),
      hill: Color(0xFFA9C95A),
      ground: Color(0xFF6BBE3E),
      groundDark: Color(0xFF3E8A2A),
    ),
  ];

  static CannonSkin skin(String id) =>
      skins.firstWhere((s) => s.id == id, orElse: () => skins.first);

  static ArenaTheme theme(String id) =>
      themes.firstWhere((t) => t.id == id, orElse: () => themes.first);

  static bool isSkin(String id) => skins.any((s) => s.id == id);
  static bool isTheme(String id) => themes.any((t) => t.id == id);
}
