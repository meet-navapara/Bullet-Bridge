import '../config/balance.dart';
import '../economy/catalog.dart';
import '../economy/upgrades.dart';

/// How the player chose to play on this device.
enum AccountMode {
  /// Has not chosen yet: the welcome screen is shown.
  undecided,

  /// No account: progress stays on this device and nothing is uploaded.
  guest,

  /// Signed in with Google: progress is kept in the cloud.
  google,
}

/// Player settings. Persisted inside [SaveData].
class GameSettings {
  GameSettings({
    this.music = true,
    this.sfx = true,
    this.vibration = true,
    this.musicVolume = 0.6,
    this.sfxVolume = 0.8,
    this.reducedMotion = false,
    this.shareUsageData = true,
    this.accountMode = AccountMode.undecided,
  });

  bool music;
  bool sfx;
  bool vibration;
  double musicVolume;
  double sfxVolume;
  bool reducedMotion;

  /// Anonymous analytics and crash reports (Firebase). Players can opt out.
  bool shareUsageData;

  /// Per device, like every setting: merging saves never changes it.
  AccountMode accountMode;

  Map<String, Object?> toJson() => {
    'music': music,
    'sfx': sfx,
    'vibration': vibration,
    'musicVolume': musicVolume,
    'sfxVolume': sfxVolume,
    'reducedMotion': reducedMotion,
    'shareUsageData': shareUsageData,
    'accountMode': accountMode.name,
  };

  factory GameSettings.fromJson(Map<String, Object?> json) => GameSettings(
    music: _bool(json['music'], true),
    sfx: _bool(json['sfx'], true),
    vibration: _bool(json['vibration'], true),
    musicVolume: _unit(json['musicVolume'], 0.6),
    sfxVolume: _unit(json['sfxVolume'], 0.8),
    reducedMotion: _bool(json['reducedMotion'], false),
    shareUsageData: _bool(json['shareUsageData'], true),
    accountMode: AccountMode.values.firstWhere(
      (m) => m.name == json['accountMode'],
      orElse: () => AccountMode.undecided,
    ),
  );
}

/// Lifetime counters used by achievements.
class LifetimeStats {
  LifetimeStats({
    this.ballsDestroyed = 0,
    this.coinsEarned = 0,
    this.gamesPlayed = 0,
    this.upgradesBought = 0,
    this.powerUpsUsed = 0,
    this.wavesCleared = 0,
  });

  int ballsDestroyed;
  int coinsEarned;
  int gamesPlayed;
  int upgradesBought;
  int powerUpsUsed;
  int wavesCleared;

  Map<String, Object?> toJson() => {
    'ballsDestroyed': ballsDestroyed,
    'coinsEarned': coinsEarned,
    'gamesPlayed': gamesPlayed,
    'upgradesBought': upgradesBought,
    'powerUpsUsed': powerUpsUsed,
    'wavesCleared': wavesCleared,
  };

  factory LifetimeStats.fromJson(Map<String, Object?> json) => LifetimeStats(
    ballsDestroyed: _int(json['ballsDestroyed']),
    coinsEarned: _int(json['coinsEarned']),
    gamesPlayed: _int(json['gamesPlayed']),
    upgradesBought: _int(json['upgradesBought']),
    powerUpsUsed: _int(json['powerUpsUsed']),
    wavesCleared: _int(json['wavesCleared']),
  );
}

/// Daily reward / challenge / ad-limit bookkeeping. Dates are local
/// calendar days in `yyyy-MM-dd` form.
class DailyState {
  DailyState({
    this.lastRewardDate,
    this.lastRewardEpochMs = 0,
    this.streakDay = 0,
    this.bonusPowerUpsPending = 0,
    this.challengeDate,
    this.challengeBest = 0,
    this.challengeClaimedDate,
    this.adCoinsDate,
    this.adCoinsCount = 0,
  });

  String? lastRewardDate;
  int lastRewardEpochMs;

  /// 1-based day of the streak that was last claimed (0 = never).
  int streakDay;

  /// Power-ups granted by the daily reward, added to the next run.
  int bonusPowerUpsPending;

  String? challengeDate;
  int challengeBest;
  String? challengeClaimedDate;
  String? adCoinsDate;
  int adCoinsCount;

  Map<String, Object?> toJson() => {
    'lastRewardDate': lastRewardDate,
    'lastRewardEpochMs': lastRewardEpochMs,
    'streakDay': streakDay,
    'bonusPowerUpsPending': bonusPowerUpsPending,
    'challengeDate': challengeDate,
    'challengeBest': challengeBest,
    'challengeClaimedDate': challengeClaimedDate,
    'adCoinsDate': adCoinsDate,
    'adCoinsCount': adCoinsCount,
  };

  factory DailyState.fromJson(Map<String, Object?> json) => DailyState(
    lastRewardDate: _date(json['lastRewardDate']),
    lastRewardEpochMs: _int(json['lastRewardEpochMs']),
    streakDay: _int(json['streakDay']).clamp(0, 7),
    bonusPowerUpsPending: _int(json['bonusPowerUpsPending']).clamp(0, 10),
    challengeDate: _date(json['challengeDate']),
    challengeBest: _int(json['challengeBest']),
    challengeClaimedDate: _date(json['challengeClaimedDate']),
    adCoinsDate: _date(json['adCoinsDate']),
    adCoinsCount: _int(json['adCoinsCount']),
  );
}

/// Everything persisted for the player. Versioned JSON document.
class SaveData {
  SaveData({
    this.coins = 0,
    this.bestScore = 0,
    this.bestWave = 0,
    Map<UpgradeType, int>? upgrades,
    Set<String>? ownedSkins,
    this.selectedSkin = Catalog.defaultSkinId,
    Set<String>? ownedThemes,
    this.selectedTheme = Catalog.defaultThemeId,
    GameSettings? settings,
    this.tutorialDone = false,
    LifetimeStats? stats,
    Set<String>? claimedAchievements,
    DailyState? daily,
    Set<String>? committedRuns,
    this.gamesSinceInterstitial = 0,
    this.highestStageCleared = 0,
    Map<int, int>? stageStars,
    this.bestChain = 0,
    Map<int, int>? levelBest,
    Set<int>? chapterRewards,
    this.updatedAtMs = 0,
  }) : upgrades = upgrades ?? defaultUpgrades(),
       ownedSkins = ownedSkins ?? {Catalog.defaultSkinId},
       ownedThemes = ownedThemes ?? {Catalog.defaultThemeId},
       settings = settings ?? GameSettings(),
       stats = stats ?? LifetimeStats(),
       claimedAchievements = claimedAchievements ?? {},
       daily = daily ?? DailyState(),
       committedRuns = committedRuns ?? {},
       stageStars = stageStars ?? {},
       levelBest = levelBest ?? {},
       chapterRewards = chapterRewards ?? {};

  static const int schemaVersion = 3;

  /// How many recent run ids are remembered to reject duplicate commits.
  static const int committedRunHistory = 20;

  int coins;
  int bestScore;
  int bestWave;
  final Map<UpgradeType, int> upgrades;
  final Set<String> ownedSkins;
  String selectedSkin;
  final Set<String> ownedThemes;
  String selectedTheme;
  final GameSettings settings;
  bool tutorialDone;
  final LifetimeStats stats;
  final Set<String> claimedAchievements;
  final DailyState daily;
  final Set<String> committedRuns;
  int gamesSinceInterstitial;

  /// Campaign progress (schema 2+).
  int highestStageCleared;
  final Map<int, int> stageStars;
  int bestChain;

  /// Best score per campaign level (schema 3+).
  final Map<int, int> levelBest;

  /// Chapters whose boss reward has been paid (schema 3+). A boss reward is
  /// paid once, ever.
  final Set<int> chapterRewards;

  /// When this document was last changed (epoch ms, device clock). Cloud
  /// sync uses it to pick the newer value of fields that cannot be merged,
  /// such as coins.
  int updatedAtMs;

  int get totalStars => stageStars.values.fold(0, (a, b) => a + b);

  static Map<UpgradeType, int> defaultUpgrades() => {
    for (final def in Upgrades.all) def.type: def.minLevel,
  };

  int level(UpgradeType type) =>
      upgrades[type] ?? Upgrades.byType(type).minLevel;

  SaveData copy() => SaveData.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'coins': coins,
    'bestScore': bestScore,
    'bestWave': bestWave,
    'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
    'ownedSkins': ownedSkins.toList()..sort(),
    'selectedSkin': selectedSkin,
    'ownedThemes': ownedThemes.toList()..sort(),
    'selectedTheme': selectedTheme,
    'settings': settings.toJson(),
    'tutorialDone': tutorialDone,
    'stats': stats.toJson(),
    'claimedAchievements': claimedAchievements.toList()..sort(),
    'daily': daily.toJson(),
    'committedRuns': committedRuns.toList(),
    'gamesSinceInterstitial': gamesSinceInterstitial,
    'highestStageCleared': highestStageCleared,
    'stageStars': {for (final e in stageStars.entries) '${e.key}': e.value},
    'bestChain': bestChain,
    'levelBest': {for (final e in levelBest.entries) '${e.key}': e.value},
    'chapterRewards': chapterRewards.toList()..sort(),
    'updatedAtMs': updatedAtMs,
  };

  /// Tolerant parser: unknown keys are ignored, bad values fall back to
  /// defaults, and values are clamped to legal ranges.
  factory SaveData.fromJson(Map<String, Object?> json) {
    final upgrades = defaultUpgrades();
    final rawUpgrades = json['upgrades'];
    if (rawUpgrades is Map) {
      for (final def in Upgrades.all) {
        final value = rawUpgrades[def.type.name];
        if (value is num) {
          upgrades[def.type] = value.toInt().clamp(def.minLevel, def.maxLevel);
        }
      }
    }

    final ownedSkins = _stringSet(
      json['ownedSkins'],
    ).where(Catalog.isSkin).toSet()..add(Catalog.defaultSkinId);
    final ownedThemes = _stringSet(
      json['ownedThemes'],
    ).where(Catalog.isTheme).toSet()..add(Catalog.defaultThemeId);
    var selectedSkin = json['selectedSkin'] is String
        ? json['selectedSkin']! as String
        : Catalog.defaultSkinId;
    if (!ownedSkins.contains(selectedSkin)) {
      selectedSkin = Catalog.defaultSkinId;
    }
    var selectedTheme = json['selectedTheme'] is String
        ? json['selectedTheme']! as String
        : Catalog.defaultThemeId;
    if (!ownedThemes.contains(selectedTheme)) {
      selectedTheme = Catalog.defaultThemeId;
    }

    final runs = json['committedRuns'];
    return SaveData(
      coins: _int(json['coins']),
      bestScore: _int(json['bestScore']),
      bestWave: _int(json['bestWave']),
      upgrades: upgrades,
      ownedSkins: ownedSkins,
      selectedSkin: selectedSkin,
      ownedThemes: ownedThemes,
      selectedTheme: selectedTheme,
      settings: GameSettings.fromJson(_map(json['settings'])),
      tutorialDone: _bool(json['tutorialDone'], false),
      stats: LifetimeStats.fromJson(_map(json['stats'])),
      claimedAchievements: _stringSet(json['claimedAchievements']),
      daily: DailyState.fromJson(_map(json['daily'])),
      committedRuns: runs is List ? runs.whereType<String>().toSet() : {},
      gamesSinceInterstitial: _int(json['gamesSinceInterstitial']),
      highestStageCleared: _int(json['highestStageCleared'])
          .clamp(0, StageSpec.levelCount),
      stageStars: _stars(json['stageStars']),
      bestChain: _int(json['bestChain']),
      levelBest: _levelBest(json['levelBest']),
      chapterRewards: _chapters(json['chapterRewards']),
      updatedAtMs: _int(json['updatedAtMs']),
    );
  }
}

int _int(Object? v) => v is num && v.isFinite ? v.toInt().clamp(0, 1 << 52) : 0;

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

double _unit(Object? v, double fallback) =>
    v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : fallback;

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry('$k', value)) : const {};

Set<String> _stringSet(Object? v) =>
    v is List ? v.whereType<String>().toSet() : <String>{};

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
String? _date(Object? v) => v is String && _datePattern.hasMatch(v) ? v : null;

Map<int, int> _levelBest(Object? v) {
  final out = <int, int>{};
  if (v is Map) {
    v.forEach((k, value) {
      final level = int.tryParse('$k');
      if (level != null && level > 0 && value is num && value.isFinite) {
        out[level] = value.toInt().clamp(0, 1 << 52);
      }
    });
  }
  return out;
}

Set<int> _chapters(Object? v) => v is List
    ? v.whereType<num>().map((n) => n.toInt()).where((n) => n > 0).toSet()
    : <int>{};

Map<int, int> _stars(Object? v) {
  final out = <int, int>{};
  if (v is Map) {
    v.forEach((k, value) {
      final stage = int.tryParse('$k');
      if (stage != null && stage > 0 && value is num) {
        out[stage] = value.toInt().clamp(0, 3);
      }
    });
  }
  return out;
}
