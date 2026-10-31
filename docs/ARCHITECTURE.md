# Architecture

Goal: a solo developer can find and change any rule in one place, and the
gameplay rules can be tested without a device.

## Layers

```
Flutter UI (lib/ui)             menus, map, HUD, overlays          ── reads ──┐
   │ AppScope (InheritedWidget) gives every screen AppServices                │
   ▼                                                                           │
AppServices (lib/app)           PlayerProgress, Audio, Haptics, Ads            │
   ├── PlayerProgress (lib/progress)  transactions on SaveData ─► SaveRepository ─► KeyValueStore
   │        uses economy/upgrades, progress/daily, progress/achievements
GameScreen ─► BoomforgeGame (Flame) ─► GameSimulation (pure Dart)
                 │  renders sim state with render/* art, parallax world
                 │  drains GameEvents -> EffectsLayer, AudioService, Haptics
                 └► HudModel (ChangeNotifier) ─► HUD widgets
```

## Rules: `lib/game/sim`

| File | Responsibility |
|---|---|
| `game_simulation.dart` | One run: cannon, creatures, bullets, hazards, blasts, enemy shots, telegraphs, pickups, boss, hull, chains, waves, stage completion |
| `entities.dart` | Data types and the `GameEvent` hierarchy |
| `wave_director.dart` | `RunPlan` (`StagePlan` for a campaign level, `EndlessPlan`), wave contents per `SpawnPattern`, scattered hazards and hazard clusters |
| `boss.dart` | Runtime state of any boss: plates or heads, phases, attack timers, ball supply and throw timing, and the slam state machine |

Campaign and boss **data** live in `lib/config`:

| File | Responsibility |
|---|---|
| `balance.dart` | Every tuning number. `SpeedSpec` is the single source of enemy speed (pace, drift and their caps); `CampaignSpec` holds the durability, pace and coin curves; `BossSpec` holds the shared attack timings |
| `campaign.dart` | 10 authored and 90 generated `ChapterDef`s, the 10-slot `SlotDef` rhythm and per-level overrides, resolved once into 1000 immutable `LevelDef`s (`Campaign.level(n)`) |
| `level_animation.dart` | Each level's sky animation as data, painted by `render/ambient_art.dart` |
| `bosses.dart` | 10 `BossDef`s plus 90 generated variants (`Bosses.campaign`): silhouette, colours, plate or head layout, phases with attack sets and tempo, special rules, reward |

How a level reaches the simulation:

1. `GameScreen(stage: n)` creates `StagePlan(n)`, which holds
   `Campaign.level(n)`.
2. For each wave, `WaveDirector.buildLevelWave` returns a `WavePlan`:
   spawns, hazards, durability scale, pace, drift, bounce and, on boss
   waves, the `BossDef`.
3. `GameSimulation._startWave` applies it.
| `seeded_random.dart` | Cross-platform deterministic RNG |

- **Fixed step:** `update(dt)` clamps the frame delta to 0.1 s and advances
  in 1/120 s steps, so physics is identical at any refresh rate.
- **Step order:** timers → waves/spawns → firing → bullets → creatures →
  boss → enemy shots → telegraphs → blasts → pickups → cannon collision →
  cleanup.
- **Bullets** use a swept vertical test against every target type
  (creatures, hazards, enemy shots) and hit the first one on their path, so
  hazards genuinely block shots. They pass through bosses.
- **Damage pipeline:** `damageBall` handles shatter bonus (frozen + fire or
  explosive), rock armour (fire/explosives x2) and destruction; element side
  effects (splash, chill/freeze, arc) are applied after the direct hit.
- **Chain reactions:** a broken hazard queues a `Blast`. Blasts triggered by
  other blasts wait 0.12 s, so a chain plays out as a visible sequence. Any
  kill not caused by a direct bullet, and every detonation, advances the
  chain counter; when the 1.2 s window lapses, chains of 3+ pay coins and
  score.
- **Once-only guards:** `Ball.dead`, `Hazard.dead`, `Boss.dead`,
  `Pickup.collected`; children and minions are added after the step's
  collision pass.
- **Hull:** 3 points; a hit costs one (shield absorbs it instead) and grants
  1.4 s invulnerability; nearby crystals are knocked away.
- **Speed:** `ballTimeScale` (wave pace × slow motion) is the only time
  scale. Crystals, skyrays, treasure, enemy shots and the boss all move on
  it. Every horizontal crystal velocity (spawn, split, knock-back, bomb
  push) goes through `_clampDrift`.
- **Bosses:** one engine runs all ten.
  - Each phase arms its own attack timers.
  - A global `BossSpec.attackGap` keeps attacks from starting together.
  - Entrances and phase changes are invulnerable transitions.
  - Attacks:
    - telegraphed rain, slam, minions and fan (or per-head shots);
    - lightning columns (`TelegraphKind.zap`);
    - lava and freeze `FloorZone`s;
    - weaving shots;
    - a pull that changes direction only.
  - Health is the boss's ball supply (`BossSpec.ballPlan`):
    - it keeps throwing balls, up to `maxThrownAlive` in the arena at once;
    - bullets cannot hurt it; each ball destroyed, split pieces included,
      takes one unit of health (`Boss.unitsLeft`);
    - plates fall off and phases advance as health drops;
    - busier bosses carry fewer balls (`BossDef.ballSupplyScale`);
    - it goes down when the supply is thrown and the last ball is gone.
- **Fairness:**
  - Every spawn, shard rain column, slam, lightning strike and floor zone is
    telegraphed.
  - Multi-column attacks always leave a gap wide enough for the cannon.
  - A wave has at most two of the largest crystals.
  - Bounce height depends only on size and the level's bounce profile.
  - Spawns avoid the side the cannon hugs.

## Rendering: `lib/game/boomforge_game.dart`, `lib/render`

- The arena is always 360 world units wide; height follows the screen
  (clamped 560–900). One scale maps world → pixels; the ground band is
  anchored to the bottom of the screen.
- **World:** five layers (sky, clouds, far mountains, mid ridge with pines,
  hills) are each rasterised once into an image (`_Baked`) and drawn with a
  parallax offset driven by the cannon's position; clouds also drift. The
  grass ground is a sixth image. See docs/PERFORMANCE_AUDIT.md.
- **Art** is procedural and cached: gem bodies, rock shells and glows are
  rasterised once per (colour, size) into sprites (`CrystalArt._sprite`) and
  drawn as images; faceted gems use pre-lit facet paints
  per colour, label text layouts are cached, so a frame allocates very
  little. The same art draws menus, previews and the launcher icon.
- **Effects** (`effects.dart`): capped particles (sparks, rotating crystal
  shards, rock chunks, smoke, fireballs), shockwave rings, jagged lightning,
  outlined floating text, banners, chain counter, screen flash and shake.
  Reduced motion halves particles and disables shake/flash intensity.

## UI

- `GameScreen` takes a level number (1–1000), a daily challenge, or neither
  (endless).
  - Chapters 2–10 use their chapter environment. Chapter 1, Endless and the
    daily challenge use the player's chosen theme.
  - The level map (`WorldMapScreen`) shows ten chapter sections with
    banners, boss nodes, recovery nodes and locked chapters. It opens on
    the current chapter. It stacks the `GameWidget`, a `Listener` for relative drag
  input, the top HUD (score/coin chips, hearts, boss bar), the bottom bar
  (element selector + power-ups, drawn over the ground) and overlays
  (stage title card, pause, stage clear, defeat).
- Pause stops the Flame engine; app backgrounding pauses automatically;
  leaving the app on an end screen commits the result immediately.
- Results are committed once via `PlayerProgress.commitRun`, keyed by a
  unique run id remembered in the save.

## Persistence: `lib/progress`

- `SaveData` is one versioned JSON document.
  - Schema 2 added campaign progress: `highestStageCleared`, `stageStars`
    and `bestChain`.
  - Schema 3 adds `levelBest` and `chapterRewards` for the 100-level
    campaign.
  - Parsing is tolerant. `SaveRepository.migrate` upgrades old documents
    step by step and is idempotent.
- Writes copy the last good document to a backup key first; corrupt
  primaries fall back to the backup.
- `PlayerProgress` serializes every change as copy → mutate → persist →
  publish; purchases carry the level the UI showed so double taps are
  rejected.
- Only clearing the next locked level advances progress. A level clear:
  - pays a star-scaled bonus: ×2 on the first clear, 25% on replays;
  - records stars and the per-level best score;
  - reports newly unlocked elements;
  - pays the chapter's boss reward (coins plus a reward-only skin) exactly
    once.

## Services

- `AudioService`: 20 procedurally generated sounds in low-latency pools,
  rate-limited, one music loop, `mixWithOthers` focus, paused in background.
- `HapticsService`: platform haptics respecting the vibration setting.
- `AdsService`: UMP consent → AdMob; rewarded success only via the SDK's
  earned-reward callback; interstitials capped and only between runs.
- `FirebaseSetup` (`lib/services/firebase_setup.dart`): starts Firebase when
  the build has its config files. It is capped at 3 s and never throws;
  without config, every cloud feature is off and the game plays locally.
  It also installs the Crashlytics error hooks.
- `CloudSync` (`lib/services/cloud/`): cloud save behind a small
  `CloudBackend` interface. `FirebaseCloudBackend` uses Firebase Auth
  (Google only) and Firestore `players/{uid}`. Guests never reach it: the
  choice is made on `WelcomeScreen` and kept in `GameSettings.accountMode`.
  - On start it restores the account, downloads the cloud save, runs
    `PlayerProgress.mergeFrom` (rules in `lib/progress/save_merge.dart`) and
    uploads the result.
  - Later changes upload 4 s after the last one, or immediately when the
    app goes to the background.
  - Every change stamps `SaveData.updatedAtMs`, which the merge uses to pick
    the newer coins.
  - Setup and data model: docs/FIREBASE_SETUP.md.
- `AnalyticsService`: Firebase Analytics events (level start/end, bosses,
  chapters, upgrades). It does nothing without Firebase or when the player
  turns off "Share Usage Data".
