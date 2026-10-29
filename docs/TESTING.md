# Testing

## Firebase and cloud save (2026-10-28)

- Package renamed to `com.boomforge.game` on Android and iOS.
- `flutter analyze`: no issues.
- `flutter test`: **162 passed**. New tests:
  - `test/progress/save_merge_test.dart` (7): earned progress never lost;
    coins and selections from the newer save; settings stay per device;
    idempotent merge; bounded run history; `mergeFrom` persists and
    notifies; changes are timestamped.
  - `test/services/cloud_sync_test.dart` (9), against an in-memory fake
    backend: first upload; cloud save merged on start; debounced upload
    (two changes, one write); offline play and later sync; flush;
    Google sign-in on a new phone restores the old save; cancelled
    sign-in; deleting cloud data keeps local progress; disabled without
    Firebase.
- Builds:
  - `flutter build apk --debug` without `google-services.json` (Firebase
    off): OK.
  - Debug build with a placeholder `google-services.json`, to check that
    the Google Services and Crashlytics Gradle plugins work with AGP 9.1:
    OK. The placeholder was deleted afterwards.
  - `flutter build apk --release`: OK (56.5 MB).
- Not verified: a real Firebase project (it needs your console
  account), Google sign-in on a device, and iOS. See
  docs/FIREBASE_SETUP.md, step 5.

## Remaining-issues pass (2026-10-28)

Fixed after the campaign update. Each fix has a test where one is
possible:

| # | Issue | Fix | Test |
|---|---|---|---|
| 1 | After two failed saves, "Next Level" still opened a level whose clear could not count | The next level opens only once the clear is saved; a failed save shows **Retry Save** instead | `run_flow_bugs_test`: the next level waits until the cleared level is saved |
| 2 | Shots at a boss during its entrance or a phase change vanished silently | `BossShielded` event: cyan shield spark plus a soft clink, throttled | `boss_test`: shots at an invulnerable boss show a shield spark |
| 3 | Old "stage" wording | HUD shows "LEVEL n", "LEVEL CLEAR!", goal "Clear level 3", tutorial and locked-element hint updated | analyzer and screenshot review |
| 4 | Level map hid the new-mechanic badge on levels 2, 4 and 6 | Element badge on the right, new-mechanic badge on the left | screenshot review |
| 5 | Shard rain could trap the cannon (columns 70 units apart left no safe spot) | Rain uses the same spaced-column rule as lightning | `boss_test`: rain leaves a safe band (200 seeds) |
| 6 | Freezing ground followed by an aimed slam or strike was unavoidable | Aimed attacks (slam, lightning, lava) wait while the cannon is frozen | `boss_test`: aimed attacks wait while the cannon is frozen |
| 7 | The last two bosses were too hard with mid gear (3/8 and 1/8 wins); warm-up waves cost hull | Warm-up waves at 60% durability with no largest-size crystals; Chaos Architect and Worldbreaker core ×38 → ×32, last-phase tempo 0.9 → 1.0 | win rates now 7/8 and 4/8; `boss_test` fights pass |
| 8 | Many native audio players (memory) and a ~2 s sound start-up | 41 → 29 voices (2 for rate-limited effects, 1 for jingles), loaded in parallel | `audio_service_test` |
| 9 | Gameplay screenshot goldens differed on every run (unseeded particle randomness) | Effects use a seeded `Random`; baselines regenerated (level 7 replaces stage 6 in the script) | `screenshots_test` passes twice in a row |
| 10 | GAME_BALANCING.md described the old 10-stage pace and boss | Marked those sections historical and pointed to LEVEL_BALANCING.md | n/a |

Not done (needs the phone):

- the on-device run of `integration_test/campaign_test.dart`;
- measuring memory and start-up time on hardware after the audio change.

The phone disconnected before these could start.

## 100-level campaign update (2026-10-28)

Windows 11, Flutter 3.47.7, Dart 3.13.5.

### Commands run

| Command | Result |
|---|---|
| `dart format lib test tool integration_test` | OK |
| `flutter analyze` | No issues found |
| `flutter test` | **142 passed, 0 failed** |
| `flutter test tool/balance/campaign_report_test.dart` | 2 passed. All 100 levels cleared by the scripted player with an earned-coins-only economy, 0 failures (table in docs/LEVEL_BALANCING.md) |
| `flutter test tool/soak/soak_test.dart` | 2 passed. 100 levels × 3 seeds × 2 elements finish with no stalls, NaNs, escaped crystals or unbounded lists; twelve 30-minute Endless runs stay healthy |
| `flutter test tool/perf/frame_cost_test.dart` | update avg 0.1 ms (max 3.0), record avg 0.5 ms (max 7.8), 0 frames over 16.7 ms with 12 crystals (headless) |
| `flutter test tool/soak/render_soak_test.dart` | 20 simulated minutes: per-frame cost 0.31 → 0.18 ms, so no slowdown over time |
| `flutter test tool/screenshots/boss_gallery_test.dart` | renders all 10 bosses mid-fight plus 6 sample levels into `tool/screenshots/out/bosses`, reviewed by eye |
| `flutter build apk --release` | Built `app-release.apk` (53.7 MB) |
| On-device run of `integration_test/campaign_test.dart` | **Not run in this update**: no device was connected. It now plays levels 1, 5, 9, 10, 11, 26, 50, 90 and 100. |

### Tests for the campaign

- `test/config/campaign_test.dart` (14):
  - 100 levels in 10 chapters with correct numbering;
  - bosses exactly on levels 10…100, each different;
  - every level definition valid (waves, patterns, counts, tiers,
    durability, pace and drift within caps, hazards, rewards, hint);
  - levels are not copies (more than 80 distinct signatures, every spawn
    pattern used);
  - mechanics introduced one per level, only on calm levels, and kept
    afterwards;
  - chapter rhythm (intro, recovery on slot 6, boss on slot 10);
  - recovery levels less demanding than the challenge and hard levels
    around them, and chapter openers gentler than the previous final test;
  - durability drops on at least 20 levels while chapter averages climb;
  - pace starts at 0.5 or below, stays capped, and never jumps by 0.1 or
    more between levels;
  - every wave of every level respects object limits, at most two big
    crystals, and only unlocked enemies, affinities and hazards;
  - creatures move at the level pace (level 8 below 0.6, where the old game
    was at 1.0);
  - split and bomb-pushed crystals never exceed the drift cap;
  - low-bounce levels bounce lower and run slower;
  - identical results at 30 fps and 144 fps.
- `test/sim/boss_test.dart` (24):
  - data: 10 distinct bosses and silhouettes, one per chapter, consistent
    exposure tables, fit in the arena, valid rewards and skins, every plate
    or head reachable by bullets, no two bosses with the same attack set;
  - engine:
    - the entrance is invulnerable and descends;
    - plates shield the core;
    - every boss walks through all its phases in order;
    - phase changes are invulnerable;
    - rain is telegraphed;
    - slams land where telegraphed;
    - attacks never start closer than the attack gap;
    - defeat clears the stage and every attack;
  - attacks:
    - lightning strikes only the warned column, and stepping out avoids it;
    - lava warns, then hurts once, then burns out;
    - freezing ground slows steering without hurting;
    - weaving shots stay within their amplitude;
    - pull changes direction only;
    - the void rift does tiny damage shut and big damage open, and cycles;
    - Hydra heads take ×2 from their element and ×0.5 from others, and
      regrow at phase 2;
    - Behemoth exposure steps up with every broken section;
  - fights: every boss level (10–100) is won by the scripted player with a
    mid-strength loadout within 4 attempts, with fewer than 40 objects on
    screen.
- `test/progress/progress_test.dart` (40, 9 of them new or changed):
  - first clear pays double and unlocks only the next level;
  - replays pay 25% of the bonus;
  - locked levels cannot be skipped to;
  - the boss reward is paid exactly once (coins and skin), and duplicate
    run ids are rejected;
  - reward skins cannot be bought;
  - per-level best scores;
  - the campaign ends at level 100;
  - schema 2 → 3 migration keeps coins, upgrades, skins, stars and progress,
    marks chapter 1 as paid for players who beat the old boss, and is
    idempotent;
  - schema 1 → 3 still works.
- `test/sim/mechanics_test.dart` and `test/sim/edge_cases_test.dart` were
  updated for the new level and boss APIs. That includes revive on the
  final wave and the boss not hanging on the floor through a phase change.

### Bugs found by this testing and fixed

- **The Molten Titan crashed the renderer.** A three-colour gradient had no
  colour stops. Found by the boss gallery render.
- **The Prism Hydra's middle head could not be hit** because it sat behind
  the body. Moved below the body; reachability is now tested.
- **Two lava pools could cover the whole floor**, and late lightning columns
  could trap the cannon. Both now always leave a safe gap.
- **Crowding**: up to 5 of the largest crystals per wave made late levels
  undodgeable. Capped at 2 per wave, base counts reduced, and low bounce
  limited to short challenge levels with a slower pace.
- **The economy was far too generous** (upgrades maxed by level 69). Chapter
  coin scaling was reduced from +30% to +15% per chapter.
- **The level map banner** overflowed by 14 px. Found by a widget test.

### Not verified in this update

- Feel and frame timing on a real phone for the new levels and bosses.
  Run when a device is connected:
  `flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/campaign_test.dart -d <device>`
- iOS.

---

## Earlier phase (2026-10-27)


Results recorded on 2026-10-27 (Windows 11, Flutter 3.47.7, Dart 3.13.5)
after the BOOMFORGE rebuild.

## Commands run

| Command | Result |
|---|---|
| `flutter pub get` | OK |
| `dart format lib test tool` | OK |
| `flutter analyze` | No issues found |
| `flutter test` | **93 passed, 0 failed** |
| `flutter test tool/screenshots/screenshots_test.dart --update-goldens` | 16 screens rendered and reviewed |
| `flutter build apk --release` | see "Builds" below |
| `flutter build appbundle --release` | see "Builds" below |
| iOS build | **Not run**: needs macOS + Xcode |

## Automated tests (`test/`)

`test/sim/game_simulation_test.dart` (30): core rules carried over from the
first version: damage/overkill scoring, splitting, no double destruction,
same-step multi-hits, swept bullets, fire rate and streams, cannon
clamping, collisions (now costing hull), shield, starting shield, revive,
power-up inventory/cooldown/expiry/bomb, coins and fractional bonus, wave
flow, 90 s bounds soak, bounce heights, determinism, delta clamping.

`test/sim/mechanics_test.dart` (22): BOOMFORGE mechanics
- elements: locked elements rejected; fire splash vs kinetic; ice chill →
  freeze after 8 hits, frozen creatures don't move, thaw; shatter bonus;
  electric arcs only within range
- geodes: shell absorbs damage first, fire doubles shell damage, one
  ArmorBroken event
- hazards: blaze → neighbouring blaze detonates one delay later (depth 1 →
  2); blasts kill creatures and a 5-chain pays its bonus; frost freezes in
  range only; storm hits exactly 5 targets; hazards block bullets
- skyrays drop shards that cost a heart; bullets destroy shards
- hull: 3 hits end the run, invulnerability ignores repeat hits, stars = 1
- stages: a stage ends after 3 waves with 3 stars for a clean run; features
  introduced one per stage; seeded stage waves identical; stage 10 ends
  with the boss
- boss: plates reduce core damage until broken; phase changes at 2/3 and
  1/3 with an invulnerable transition; shard rain telegraphed before it
  falls; phase-2 slam lands where telegraphed and hurts; defeat clears the
  stage

`test/progress/progress_test.dart` (33): upgrades, purchases (double tap,
insufficient funds, failed write), skins/themes, run commits once, best
score, daily challenge reward once, bonus power-ups, achievements, daily
reward streak/rollback/reset, ad-coin limit, challenge determinism, save
round trip / defaults / corruption / migration; **campaign:** first-clear
double bonus and unlock, stars never decrease, failed stages keep coins
only, element unlocks, reset clears campaign, schema 1 → 2 migration, star
map sanitising.

`test/widget/app_flow_test.dart` (8): main menu without overflow at
320×568, 360×640, 393×852, 412×915; buying an upgrade persists; settings
persist; every menu destination (Levels, Shop, Daily, Challenge, Goals,
How to) opens and returns; first Play shows the tutorial then stage 1,
pause/resume.

## Bugs found by testing in this phase and fixed

- Boss core exposure table was reversed (core took full damage with both
  plates up) — boss test.
- Main menu overflowed on 320–360 dp screens; side-button captions were not
  tappable — widget tests.
- Shop price tags overflowed; Settings links used `ListTile` inside opaque
  panels (invisible ink) — widget tests.
- PLAY button covered the cannon on the menu; twin bullet streams with round
  heads read as pairs of eyes — screenshot review.
- Stage curve too steep for stage 7–10 — stage balance report.

## Builds

Release APK and AAB were built after the final balance change; see the
final report in the conversation for sizes. The release APK from the
previous phase was installed on the Pixel 8a and launched without crashes.
The phone stayed fingerprint-locked for this whole phase, so the BOOMFORGE
build has **not** been played or screenshotted on hardware.

## Not yet verified

- Hands-on feel and difficulty on a real device; measured frame rate.
- Audio/haptics by ear and hand; ads on a device.
- iOS.
