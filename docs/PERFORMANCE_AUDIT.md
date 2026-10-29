# Performance and Visual Audit

Date: 2026-10-27. Scope: the whole game loop, rendering, effects, audio,
crystal art and viewport, prompted by reports that the game lagged, the
crystals were too small and they had eyes.

## How the game is built (relevant facts)

- One `BoomforgeGame` (Flame) per `GameScreen`. It has **no Flame
  components**: a pure-Dart `GameSimulation` advances in fixed 1/120 s
  steps (frame delta clamped to 0.1 s, so resuming never causes a jump),
  and `render()` draws everything with direct canvas calls. There is no
  per-entity component creation, no image decoding (all art is
  procedural; the only image assets are the launcher icons) and a single
  update loop.
- Restart builds a new `GameSimulation` and clears the effects layer; all
  caches are bounded (labels 500, effect text 80, sprites 200, trail
  shaders one per colour), so repeated restarts cannot grow memory or
  slow the game.
- Backgrounding pauses the run (`didChangeAppLifecycleState`) and
  suspends audio.

## Findings

| # | Area | Finding | Impact | Fix |
|---|---|---|---|---|
| 1 | Effects | Every floating damage number, the wave banner and the chain counter used `saveLayer(null, …)` for fading: each allocates a **full-screen offscreen texture**; up to 14 texts + 2 overlays per frame. | High GPU (raster) cost in busy waves | Layers are now bounded to the text rect, and skipped when fully opaque (`EffectsLayer._fadeLayer`). |
| 2 | Backdrop | Six backdrop layers were `Picture`s replayed every frame: hundreds of paths, gradients and a large `MaskFilter.blur`; the cloud layer was replayed twice. Pictures drawn in a game canvas are **not raster-cached**. | High GPU cost every frame | Each layer is rasterised once into an image (`_Baked` in `boomforge_game.dart`) at min(dpr, 2) (sky at 1x) and drawn with one `drawImageRect`. |
| 3 | Crystals | Each crystal drew ~15 paths plus a new radial-gradient shader (glow) every frame; geodes also built a `Random`, a polygon and several paths per frame. | Medium CPU + GPU | Gem bodies, rock shells and glows are rasterised once per (colour, size, variant) into sprites (`CrystalArt._sprite`); hit flashes use a colour filter on the same sprite. |
| 4 | Bullets | A new `Gradient.linear` shader per bullet per frame for the trail. | Allocation churn | One unit-space shader per colour, reused. |
| 5 | Audio | Each sound start is a platform-channel round trip (`AudioPool.start`). Shots, hits, pops and coins could total 40+ starts/s. | Possible UI-thread hitches | Longer per-sound gaps plus a shared 35 ms gap for frequent sounds. |
| 6 | Widgets | The HUD and the `GameWidget` shared a paint layer, so the HUD repainted every game frame. | Low–medium | `RepaintBoundary` around the game and the top HUD. HUD rebuilds only when a shown value changes (`HudModel`). |
| 7 | Particles | Cap of 320. | Low | Lowered to 240. |
| 8 | Collisions | Bullets are swept vertically against at most 12 crystals, hazards and the boss: ≈ 40 bullets × 20 targets per 1/120 s step ≈ 100k cheap checks/s. | Negligible (see measurement) | No broad phase needed; kept simple and exact (no tunnelling). |
| 9 | Allocation | Bullets / particles are small Dart objects (~15 bullets/s). | Negligible | Pooling not warranted. |
| 10 | Shake | Shake up to 12 units of random jitter per frame. | Readability | Halved and capped at 7. |

## Visual findings

- **Eyes/faces** came only from procedural code in
  `lib/render/crystal_art.dart` (`_face` for shards and skyrays; eyes and a
  mouth on the boss). Removed at the source: `_face` and the `lookX`
  parameters are gone; the boss now has a pulsing energy core. No image
  asset contained faces; the launcher icon is re-rendered from the
  faceless art.
- **Size:** the arena was 400 units wide with crystal radii 13–39 (later
  21–55). Now the arena is 360 units (≈11% zoom on every object,
  hitboxes included, since everything is in world units) and radii are
  28 / 37 / 47 / 58 / 70: the largest is 39% of the screen width, the
  smallest 16%. Collision radius, spawn position, bounce height, split
  position and the visual size all read the same `BallSpec.radius` table.
  Element ranges grew with them (splash 56, arc 125).
- **Numbers:** without faces the label is centred and sized at 95% of the
  radius (scaled down for 3–4 characters), so it stays readable on the
  smallest crystal.

## Measurements

**Device:** not measured. The Pixel 8a stayed on the lock screen during
this work, so no on-device frame times exist yet. To measure:

```bash
flutter run --profile --dart-define=PERF_LOG=true
# then read lines like:
# [perf] frames 300 | ui avg … p90 … max … | raster avg … p90 … max … | over16.7ms N
```

(`lib/services/frame_monitor.dart`; uses Flutter's `FrameTiming`, which
works in profile and release builds.)

**Desktop CPU, headless** (`flutter test tool/perf/frame_cost_test.dart`):
a stage-6 run with 12 crystals of all tiers kept alive, auto-fire, ~15
particles, 840 measured frames:

| Phase | avg | p90 | max |
|---|---|---|---|
| `update` (simulation + events + effects) | 0.1 ms | 0.1 ms | 2.0 ms |
| `render` (recording all draw calls) | 0.4 ms | 0.6 ms | 8.4 ms (first-use sprite rasterisation) |

This was measured after the changes only; no "before" number exists for
this harness. It shows the Dart side uses a few percent of a 16.7 ms
frame, which points at GPU raster work (findings 1–3) and platform calls
(finding 5) as the causes of the lag on the phone. A headless test cannot
measure GPU time, so the improvement on hardware is **not yet verified**.

## Remaining risks

- Raster cost on low-end GPUs is unmeasured.
- Sprites are rasterised on first use, which can cause a one-off hitch
  the first time a new crystal size/colour appears (≤ 8 ms on desktop).
  If this shows up on device, pre-warm the sprites when a stage starts.

## Follow-up pass (2026-10-28)

Re-inspection after a repeat report of small balls, eyes and lag.

**Eyes / faces.** Re-checked: no eye, pupil, face or mouth drawing exists
in `lib/` and there are no image assets besides the launcher icons and
audio. All regenerated gameplay screenshots are faceless. A device still
showing eyes is most likely running a build from before 2026-10-27;
reinstall a fresh build (`flutter run` / `flutter build apk`).

| # | Area | Finding | Fix |
|---|---|---|---|
| 11 | Size | Radii were 28–70 world units (16–39% of the arena width). | Now 32 / 42 / 53 / 65 / 78 (18–43%); each split shrinks ~20%. Skyrays 34 → 38. Hitbox, spawn, bounce apex (clamped to the arena) and split position all read `BallSpec.radius`, so nothing drifts from the art. |
| 12 | Sprite cache | Cache cleared **all** sprites once it held 200; geodes alone can reach 100 entries (5 tiers × 4 variants × 5 crack stages) at ~1 MB each on a 1080p phone, so memory could reach ~200 MB and a clear caused a burst of re-rasterisation. | Byte-budget LRU (48 MB) that evicts one least-recently-used sprite at a time (`CrystalArt._sprite`). |
| 13 | First-use hitch | Shard sprites were rasterised the first time each tier appeared, mid-wave. | `CrystalArt.prewarm` rasterises every tier × variant when a run starts (cached across restarts). |
| 14 | Hit flash | Under steady fire a crystal is re-hit every ~50–80 ms, shorter than the 70 ms flash, so it stayed 50–60% white and swelled 10% almost permanently: pale blue gems against a blue sky looked ghostly and jittered. | Flash is squared (sharp pulse) and capped at 20% white; swell 4%. Verified by rendering one crystal at flash 0 / 0.5 / 0.88 / 1. |

**Measurements** (desktop CPU, `tool/perf/frame_cost_test.dart`, same
scene as above):

| | update avg / max | record avg / p90 / max |
|---|---|---|
| Before this pass (2026-10-27) | 0.1 / 2.0 ms | 0.4 / 0.6 / 8.4 ms |
| After | 0.1 / 1.2 ms | 0.5 / 0.8 / 7.3 ms |

The averages are within run-to-run noise (larger sprites cost slightly
more to rasterise); the worst frame is lower because sprites are
pre-warmed. No phone or emulator was attached, so GPU raster time and
on-device FPS are **still unmeasured**.

## "Stops working after a while" (2026-10-28)

**Root cause: leaking audio players.** Effects used `AudioPool` with
`PlayerMode.lowLatency`. In audioplayers 6.8.1 the pool does not listen for
completion in that mode (`audio_pool.dart`: `if (playerMode !=
PlayerMode.lowLatency) subscription = ...onPlayerComplete...`), so a player
returns only if the caller invokes the `stop` function that `start` returns.
`AudioService.play` discarded it. After the first play of each effect the
pool was empty, so **every** shot, hit, pop and coin created a new native
player (platform-channel create + asset load + volume + resume, all behind
one lock) that was never released: thousands per session at 10–20 sounds/s.
Memory grew, the platform thread filled with channel traffic (frame
hitches), the lock queue made sounds late, and eventually Android refused
new audio tracks.

**Fix.** `AudioService` now preloads a fixed set of low-latency players per
effect (3 for shoot/hit/pop, 2 otherwise; 41 total) and reuses them
round-robin (`stop` → `setVolume` → `resume`). The player count never grows.
`test/services/audio_service_test.dart` plays effects for 1.5 s through a
fake voice and checks that no player is created after start-up.

**Second bug: steering stopped responding.** Only the first finger down
steered. If a second finger or the palm touched and the first finger
lifted, the remaining finger was ignored until the player touched again.
A moving finger now takes over when no finger is steering (widget test
`a finger left down keeps steering after the first lifts`, which fails
without the fix).

**Ruled out by soak tests** (`tool/soak/`):

- `soak_test.dart`: an auto-player plays stages 1–10 × 12 seeds × 4
  elements and 12 endless runs of 30 min (three arena heights), checking
  every 1/120 s step for NaN, enemies outside the arena or stuck entering,
  30 s without progress, and list growth. No problems; max 26 live
  crystals, ≤ 10 bullets, ≤ 10 pickups. (Ice alone takes ~11 min against
  the boss with the daily-challenge loadout because it has no splash or
  arc damage: slow, not stuck.)
- `render_soak_test.dart`: 20 simulated minutes of the full game object
  (simulation + effects + drawing). Frame cost stayed flat at 0.2–0.4 ms
  per frame with no upward trend; particles stayed ≤ 240.

The audio fix cannot be exercised without a device; it needs confirming
on a phone in a long session.

## On-device campaign run (2026-10-28, Pixel 8a, profile mode)

`integration_test/campaign_test.dart` plays stages 1–10 with real touch drags,
switching elements as they unlock, and checks the game state every frame.

| Stage | Seconds | Frames | Raster p90 (ms) | Raster max (ms) | Frames > 16.7 ms | Sprites (MB) |
|------:|--------:|-------:|----------------:|----------------:|-----------------:|-------------:|
| 1 | 19 | 1112 | 8.3 | 31.1 | 4 | 12 |
| 2 | 21 | 1272 | 8.5 | 10.8 | 0 | 12 |
| 3 | 25 | 1509 | 8.5 | 11.3 | 0 | 14 |
| 4 | 31 | 1846 | 8.8 | 47.4 | 2 | 16 |
| 5 | 33 | 1968 | 9.0 | 14.7 | 0 | 16 |
| 6 | 41 | 2430 | 9.3 | 16.1 | 0 | 29 |
| 7 | 46 | 2754 | 9.7 | 14.8 | 0 | 24 |
| 8 | 49 | 2893 | 10.2 | 15.7 | 0 | 29 |
| 9 | 57 | 3367 | 9.7 | 18.9 | 1 | 26 |
| 10 (boss) | 69 | 4092 | 9.5 | 19.5 | 1 | 22 |

All stages cleared with no state problems (no non-finite or out-of-arena
balls, no 30 s stalls, the stage-clear card always appeared). Every sprite
was rasterised once (misses == cached count), and the cache peaked at 29 MB,
well under its 48 MB budget, so it never evicted. Audio: 41 preloaded voices,
init 1.9 s; active audio tracks stayed between 9 and 20 for the whole run.

An earlier run showed 210 slow frames on stage 3 and 74 on stage 5. That run
was disturbed by an orphaned `flutter drive` process from an interrupted run
(it also uninstalled the app). With it killed, the result did not reproduce.
