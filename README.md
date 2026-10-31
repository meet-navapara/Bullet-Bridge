# BOOMFORGE — Break the World

An original 2.5D cartoon arcade shooter built with Flutter and Flame. Drag a
wheeled field cannon along the grass, blast large faceted crystals that
split as they break, and set off **chain reactions** by shooting volatile
crystals floating in the sky.

Everything works offline. Ads are optional (Google AdMob, test IDs in
development builds).

> The project started as "ORBIT BLAST" and was rebuilt into BOOMFORGE. The
> Dart package is still named `orbit_blast` (renaming it would touch every
> import); the player-facing name is BOOMFORGE everywhere.

## The game

- **Signature mechanic: chain reactions.** Blaze crystals explode, Frost
  crystals freeze everything nearby, Storm crystals arc lightning. Each
  detonation can break other volatile crystals; kills caused by blasts,
  arcs and splashes build a `CHAIN xN` combo that pays bonus coins.
- **Elements:** Kinetic (default), Fire (splash, x2 vs rock armour), Ice
  (chills, then freezes; frozen enemies shatter for +50%), Shock (each hit
  arcs to two nearby targets). Unlocked by clearing stages 2, 4 and 6;
  switch any time from the bottom bar.
- **Enemies:**
  - splitting crystal Shards in 5 sizes;
  - armoured Geodes;
  - Skyrays that glide and drop shards;
  - gold Treasure crystals;
  - elemental-affinity crystals that resist one element and are weak to
    another.
- **Campaign:** 1000 levels in 100 chapters across 10 worlds, from Crystal Highlands to World's
  Edge, each with its own environment.
  - Every chapter alternates easy, challenge and recovery levels and ends
    with its own boss on level 10, 20 … 1000.
  - Mechanics arrive one at a time: hazards, geodes, skyrays, treasure,
    swarms, giants, hazard clusters, affinities, bounce profiles, armoured
    swarms, survival waves and more. See docs/LEVEL_BALANCING.md.
- **Ten bosses:** Crystal Colossus, Storm Engine, Molten Titan, Frost
  Guardian, Void Devourer, Iron Behemoth, Prism Hydra, Gravity Core, Chaos
  Architect and the four-phase Worldbreaker. Each has:
  - its own silhouette and armour layout;
  - a supply of balls it keeps throwing: shots pass through the boss, every
    ball smashed drains its health, and it goes down with the last one;
  - telegraphed attacks: shard rain, slams, lightning columns, lava,
    freezing ground, weaving shots and gravity pulls;
  - several phases;
  - a one-time chapter reward of coins, and on some chapters a reward-only
    cannon skin.
- **Calm, capped speed:** every enemy moves at one pace set by the level.
  It starts at about 55% of the old speed and has a hard cap (see
  `SpeedSpec`).
- **Also:**
  - Endless mode and a date-seeded Daily Challenge;
  - a 7-day daily reward and 18 goals;
  - 6 upgrade tracks, 11 cannon skins and 4 sky themes;
  - 4 power-ups, a 3-heart hull and an optional rewarded continue.

## Firebase (cloud save, analytics, crash reports)

Package name: **`com.boomforge.game`** (Android and iOS).

Every Firebase feature is built in:

- a first-launch choice: "Continue with Google" or "Continue as Guest" (no
  account, nothing uploaded);
- Firestore cloud save with safe merging between phones;
- Analytics and Crashlytics.

They switch on when you add your project's `android/app/google-services.json`
(and `GoogleService-Info.plist` for iOS). Without those files the game
saves locally as before. Step-by-step setup: **docs/FIREBASE_SETUP.md**.

## Requirements

- Flutter 3.47+ (Dart 3.13+). Verified with Flutter 3.47.7.
- Android SDK 36, JDK 17+ (verified with JDK 21). Android 7.0 (API 24)+.
- iOS: macOS with Xcode (not verified in this environment).

## Run

```bash
flutter pub get
flutter run --profile       # realistic performance (debug is much slower)
flutter run                 # debug, Google test ads
```

Release builds. The Play bundle needs the upload key and `release.json` and
stops with an error without them (see `docs/PRODUCTION_SETUP.md`):

```bash
flutter build appbundle --release --dart-define-from-file=release.json
flutter build apk --release   # local testing; no ads without release.json
```

## Test

```bash
dart format .
flutter analyze
flutter test                # unit + widget tests
```

Developer tools (not part of `flutter test`):

```bash
dart run tool/generate_audio.dart                    # regenerate assets/audio (20 sounds)
flutter test tool/render_icon_test.dart              # regenerate icon PNGs
dart run flutter_launcher_icons                      # apply icons to platforms
flutter test tool/balance/balance_report_test.dart   # endless-mode balance table
flutter test tool/balance/campaign_report_test.dart  # plays all 1000 levels with an
                                                     # auto-player and a real economy;
                                                     # writes build/campaign_report.md
flutter test tool/soak/soak_test.dart                # every level, many seeds, stall checks
FLUTTER_ROOT=<flutter sdk> flutter test tool/screenshots/screenshots_test.dart --update-goldens
                                                     # render 16 screens to tool/screenshots/out
```

## Project layout

```
lib/
  app/        app widget, service container (AppScope), lifecycle
  config/     balance.dart (tuning numbers, SpeedSpec, CampaignSpec),
              campaign.dart (1000 levels), level_animation.dart (level skies),
              bosses.dart (10 bosses + 90 variants), app/ads
  game/
    sim/      pure-Dart rules: simulation, entities, waves/levels, boss engine, RNG
    boomforge_game.dart   Flame game: loop, parallax world, rendering, FX
    effects.dart, hud_model.dart
  economy/    upgrades, cosmetics catalog (incl. boss-reward skins)
  progress/   save model (schema v3), repository + migrations, progress, daily, goals
  render/     procedural art: world, crystals, 10 bosses, zones, cannon, icons
  services/   audio, haptics, ads, analytics, Firebase setup, cloud/ (cloud save)
  ui/         theme tokens, reusable widgets, screens
test/         unit and widget tests (test/support/auto_player.dart: scripted player)
tool/         asset generators, balance reports, screenshot renderer
docs/         plan, architecture, balancing, testing, release, setup
```

## Renaming

- Display title / tagline: `--dart-define=APP_TITLE=...`,
  `--dart-define=APP_TAGLINE=...` (defaults in `lib/config/app_config.dart`).
- Launcher label: `android:label` in `android/app/src/main/AndroidManifest.xml`
  and `CFBundleDisplayName` in `ios/Runner/Info.plist`.

## Troubleshooting

- **Release app crashes at start with `WorkDatabase` errors:** keep the R8
  rules in `android/app/proguard-rules.pro`.
- **No ads:** expected in local release APKs without `release.json` and
  whenever consent, network or fill fails. The game never depends on ads.
- **No sound:** check in-game Settings and the device media volume. Audio
  errors are logged (`Audio disabled: ...`) and never crash the game.

See `docs/` for architecture, balancing, test results and release steps.
