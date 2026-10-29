# Level balancing: 100-level campaign

This document records why the old campaign felt too fast and too short, the
plan for the 100-level campaign, and (at the end) the generated difficulty
table for every level.

## 1. Findings in the existing game (before this change)

Project: Flutter 3.47 / Dart 3.13, Flame 1.38. Gameplay runs in a pure-Dart
`GameSimulation` at a fixed 1/120 s step (`Physics.fixedStep`), so movement
was already frame-rate independent. Flame only renders it.

### Why the balls felt too fast

Creature motion was multiplied by several independent factors:

| Factor | Where | Old value |
|---|---|---|
| Time scale ("pace") applied to gravity, drift, flyers, shots and the boss | `WaveSpec.paceAt(difficulty)` | 0.6 at stage 1, rising linearly to **1.0 by stage 8** |
| Horizontal speed per wave | `WaveSpec.speedMultiplier(wave)` | 1.0 up to **1.55** (Endless) |
| Base horizontal speed per tier | `BallSpec.baseSpeedX` | 68–92 world units/s |
| Bounce launch speed | `bounceSpeed(tier)` from gravity 900 and apex height | fall speed at the floor ≈ 770 u/s × pace |
| Bomb knock-back | `_split(pushFromX)` | 1.4× base, uncapped |
| Skyrays | `EnemySpec.skyraySpeed × speedMultiplier(wave)` | uncapped |

From stage 5 on, the campaign was already at 0.81–0.9 pace and reached the
full 1.0 pace by stage 8. Nothing capped the product of all these factors.

### Why the campaign was short and flat

- `StageSpec.stagesPerWorld = 10`. Every stage was 3 waves built by one
  generic generator: `difficulty = 1 + (stage−1)·1.2 + (wave−1)·0.75`.
- Durability grew as 1.2^difficulty and pace grew with it, so each stage was
  strictly harder than the one before. There were no recovery levels.
- There was a single boss, the Prism Colossus, on stage 10.
- `Features.forStage` introduced one new feature per stage from 2 to 6. After
  that nothing new appeared.

## 2. Plan (implemented)

1. **One speed system** (`SpeedSpec` in `lib/config/balance.dart`):
   - Each level sets a **pace** (time scale for every creature, shot and boss)
     and a **drift** (horizontal multiplier).
   - Endless derives both from its difficulty.
   - Both have hard caps.
   - Spawns, split children, knock-backs, bomb pushes, skyrays and treasure
     crystals all get their horizontal speed from `GameSimulation._speedFor`,
     which clamps it to `SpeedSpec.maxDriftSpeed`.
   - The per-wave `speedMultiplier` growth inside a campaign stage is gone.
   - Level 1 starts at pace 0.50. That is about 55% of the old typical
     pace (~0.9). Pace climbs slowly to a cap of 0.82, and recovery levels
     dip it again.
2. **Data-driven campaign** (`lib/config/campaign.dart`):
   - 10 chapter definitions × a 10-slot intensity template produce the 100
     `LevelDef`s.
   - Each level gets:
     - waves, spawn patterns, ball count and tiers;
     - durability, pace, drift and bounce profile;
     - enemy mix, hazards, special mechanic and rewards;
     - category, chapter theme and boss.
   - Explicit per-level overrides are possible.
3. **Recovery rhythm**: each chapter goes easy → normal → new mechanic →
   short challenge → recovery → hard → preparation → final test → boss.
   Durability, pace, ball count, hazards and the enemy mix rise
   independently, and some levels deliberately ease off.
4. **Ten bosses** (`lib/config/bosses.dart`, `lib/game/sim/boss.dart`,
   `lib/render/boss_art.dart`):
   - one shared, data-driven boss engine;
   - per-boss silhouettes, plates/heads, phases, attacks and special rules;
   - new attacks:
     - lightning columns;
     - lava pools;
     - freezing zones that slow the cannon;
     - curving shots;
     - weak-point windows;
     - element-weak heads;
     - a gravity pull on minions.
5. **New level mechanics**, introduced one at a time:
   - treasure crystals;
   - swarms;
   - giants;
   - hazard clusters (chain structures);
   - elemental-affinity crystals;
   - low and high bounce profiles;
   - armored swarms;
   - survival levels (5 waves);
   - skyray squads.
6. **Progression and rewards**:
   - Save schema 3 adds per-level best scores and claimed chapter rewards,
     with a tested migration.
   - The first-clear bonus and the boss chapter reward are paid once; replays
     pay a small replay bonus.
   - Coin pickups grow with the chapter.
   - Boss rewards include reward-only cannon skins.
7. **Calibration**: `tool/balance/campaign_report_test.dart` plays all 100
   levels with an auto-player. Between levels it buys upgrades only from
   coins it earned itself, records clear time, hits taken and coins, and
   prints the table at the end of this document.

## 3. Ball speed: what changed

| | Before | After |
|---|---|---|
| Pace (time scale for all enemy motion) at level 1 | 0.60 | **0.47–0.50** |
| Pace at level 10 | 1.00 | **0.48–0.55** |
| Highest pace anywhere | 1.00 | **0.78** (`SpeedSpec.maxPace`) |
| Horizontal drift multiplier | up to 1.55 (rising every wave) | **1.00 → 1.20** across the campaign, fixed per level |
| Horizontal speed cap | none | **115 u/s** before pace, for spawns, splits, knock-backs and bomb pushes |
| Split children | parent wave's multiplier, bomb push 1.4× uncapped | same capped speed as a fresh crystal of that size |
| Skyrays / treasure / enemy shots / bosses | separate multipliers | all move on the same pace |

- Level 1 runs at about 55% of the old typical pace.
- The pace climbs by 0.003 per level, and category offsets move it up or
  down (recovery −0.06, challenge +0.02, boss −0.05). Low-bounce levels run
  0.05 slower to make up for their quicker bounces.
- Neighbouring levels never differ by 0.1 or more.
- Endless and the daily challenge use the same caps: pace 0.50 → 0.78 over
  16 waves, drift up to 1.20.

Movement was already frame-rate independent: a fixed 1/120 s simulation
step, with the frame delta clamped to 0.1 s. `campaign_test.dart` checks
this by running 10 s at 30 fps and at 144 fps and expecting the same result.

## 4. How the 100 levels are built

`lib/config/campaign.dart` resolves each level from three small tables:

1. **Chapters**: a theme palette, a signature wave pattern, the mechanics
   the chapter introduces and its boss.
2. **Slots**: the ten-step rhythm every chapter follows.

| Slot | Category | Waves | HP factor | Pace offset | Extra crystals | Hazards |
|---|---|---|---|---|---|---|
| 1 | intro / recovery | 2 | 0.70 | −0.03 | −1 | 1 |
| 2 | easy | 3 | 0.80 | −0.02 | −1 | 1 |
| 3 | normal | 3 | 1.00 | 0 | 0 | 1 |
| 4 | new pattern | 3 | 0.90 | −0.01 | 0 | 1 |
| 5 | short challenge | 2 | 1.15 | +0.02 | +1 | 2 |
| 6 | recovery (treasure) | 2 | 0.75 | −0.06 | −1 | 1 |
| 7 | normal-to-hard | 3 | 1.10 | +0.01 | +1 | 2 |
| 8 | preparation | 4 | 1.00 | +0.01 | 0 | 2 |
| 9 | final test | 3 | 1.20 | +0.02 | 0 | 2 |
| 10 | boss | warm-up + boss | 1.00 | −0.05 | −1 | 0 |

3. **Curves** (`CampaignSpec`):
   - Durability: `10 × (1 + 0.25·(L−1))^1.25`, which is 10 at level 1, 41 at
     level 10 and 490 at level 100. Each wave of a level adds 10%.
   - Pace and drift: described above.
   - Coin pickups: worth ×1.0 to ×2.35 by chapter.
   - Base crystals per wave by chapter: 2, 2, 3, 3, 3, 3, 4, 4, 4, 4.
   - At most two of the largest sizes per wave, so there is always room to
     dodge.

`Campaign.overrides` adjusts single levels. It currently:

- makes level 1 one small crystal at a time;
- teaches geodes on level 3;
- turns levels 54, 58, 88 and 98 into five-wave survival levels.

## 5. Mechanics by chapter

| Ch | Name (environment) | Signature waves | Introduced (level) | Boss |
|---|---|---|---|---|
| 1 | Crystal Highlands | standard | basics (1), blaze hazards (2), geodes (3), frost hazards (4), skyrays (5), storm hazards (6) | Crystal Colossus |
| 2 | Storm Plains | skyraid | treasure crystals (11), swarms (14) | Storm Engine |
| 3 | Molten Rift | hazard fields | giants (21), hazard clusters (24) | Molten Titan |
| 4 | Frozen Reach | elemental | ember affinity (31), low bounce (34) | Frost Guardian |
| 5 | Void Hollow | elemental | high bounce (41), frost and volt affinities (44) | Void Devourer |
| 6 | Iron Foundry | armored | armoured swarms (51), survival (54) | Iron Behemoth |
| 7 | Prism Gardens | skyraid | skyray squads (61), affinity squads (64) | Prism Hydra |
| 8 | Gravity Wells | giants | geode giants (71), dense clusters (74) | Gravity Core |
| 9 | Chaos Spires | mixed | combo waves (81), elite affinity geodes (84) | Chaos Architect |
| 10 | World's Edge | mixed | finale (91) | Worldbreaker |

How the new mechanics work:

- **Treasure crystals** are gold gems that cross the sky once. Popping one
  pays 5 coin pickups, and one that escapes is lost. They never attack.
- **Elemental affinity**: a crystal takes ×0.5 damage from its own element
  and ×1.6 from its counter. Ember is weak to ice, frost to fire, volt to
  kinetic. Frost-affinity crystals cannot be chilled. Children inherit the
  affinity. A coloured ring shows it, and bombs ignore it.
- **Giants**: one or two of the largest size with ×1.5 durability, moving at
  70% horizontal speed.
- **Hazard clusters**: four or five volatile crystals 61 units apart. That is
  closer than any blast radius, so one shot sets off the whole row.
- **Bounce profiles**: low bounces reach 0.82× the usual height (with a
  slower pace); high bounces reach 1.1×.
- **Survival levels**: five waves at reduced durability.

New mechanics only ever appear on intro, easy, normal or new-pattern levels
(this is tested), never on hard levels or boss fights. Every mechanic stays
in the pool afterwards.

## 6. Bosses

All ten run on one boss engine (`Boss` + `GameSimulation._updateBoss`):

- Each phase has its own attack timers.
- A global 1.2 s attack gap stops attacks from stacking.
- Every attack is telegraphed.
- Each boss enters with a 2 s descent, during which it cannot be damaged.
- Phase changes are short invulnerable transitions with a banner.
- The HUD bar shows the boss name, one pip per phase and the remaining
  armour.

| # | Boss | Silhouette | Armour | Phases | Attacks by phase | Special rule | Reward |
|---|---|---|---|---|---|---|---|
| 1 | Crystal Colossus | crowned gem, orbiting shards | 2 rock plates | 3 | rain → +minions, slam → +fan | plates shield the core (25/60/100%) | 250 |
| 2 | Storm Engine | spinning cog, sparks | 2 coils | 3 | lightning → +fan, minions → +rain | lightning columns strike instantly after a 1.15 s warning | 400 + Storm Engine skin |
| 3 | Molten Titan | lava-seamed rock | 2 plates | 2 | lava, rain → +slam | lava pools burn for 3.2 s; fire cracks plates ×2 | 600 |
| 4 | Frost Guardian | rotating snowflake | 3 icicles | 3 | freeze, rain → fan, minions → fan, rain | freezing ground slows steering to 40% for 2.2 s | 800 + Glacier skin |
| 5 | Void Devourer | dark disc, fragment ring | none | 2 | weaving shots, rain → +minions, lightning | rift cycle: ×0.12 damage when shut, ×1.6 when open (warned 1 s ahead) | 1,000 |
| 6 | Iron Behemoth | riveted hull | 4 sections | 3 | rain, slam → +fan, geode minions → all | core opens in steps 12/30/50/75/100% | 1,300 + Iron Forge skin |
| 7 | Prism Hydra | body with three heads | 3 heads | 2 | head shots, rain → +minions, lightning | each head takes ×2 from its element, ×0.5 from the rest; one head regrows at phase 2; affinity minions | 1,600 |
| 8 | Gravity Core | sphere in two orbit rings | 2 plates | 3 | weaving shots, rain → +minions, pull → +lightning | pull turns minions towards it (direction only, never speed) | 2,000 + Event Horizon skin |
| 9 | Chaos Architect | rotating triangle and square | 2 plates | 3 | rain, lightning → lava, minions, weaving → freeze, fan, slam | each phase combines earlier bosses' attacks | 2,500 |
| 10 | Worldbreaker | cracked planet, debris ring | 4 crust plates | 4 | rain, slam → lightning, lava, minions → weaving, fan, rain + rift → freeze, lightning, fan, slam + rift | all of the above, with cracks spreading per phase | 4,000 + Worldbreaker skin |

Boss durability is `level durability × core factor` (30–38) and
`× plate factor` per plate. Playtesting the simulated campaign found and
fixed these fairness problems:

- The Hydra's middle head was hidden behind its body. It now sits below the
  body, and a test checks that every plate can be hit.
- Two lava pools could cover the whole floor. The second pool now goes on
  the far half of the arena.
- Rain and lightning columns could trap the cannon. All columns are now
  spaced so a safe band always remains (tested over 200 seeds).
- A frozen cannon steers slowly, so attacks aimed at it (slam, lightning,
  lava) now wait until it can move freely again.
- Minions are now the smallest size, which does not split.
- A boss level's warm-up wave runs at 60% durability with no crystals of
  the largest size, so the player reaches the boss with full hull.
- Shots at a boss during its entrance or a phase change show a shield
  spark instead of vanishing.

Win rate over 8 varied attempts with a mid loadout (fire rate 12, bullet
power 14, cannon level 5, element power 4):

| Boss level | 10–40 | 50 | 60 | 70 | 80 | 90 | 100 |
|---|---|---|---|---|---|---|---|
| Wins out of 8 | 8 each | 6 | 8 | 5 | 7 | 7 | 4 |

The final boss is the hardest, but needs neither maxed upgrades nor
grinding.

## 7. Rewards and saves

- **Clear bonus**: `15 + 5·level`, scaled by stars (×0.85, ×1.0 or ×1.15).
  The first clear pays it twice. A replay pays 25%, so a cleared level never
  pays its full completion reward again.
- **Boss reward**: paid once per chapter, tracked in
  `SaveData.chapterRewards`. It brings coins, a reward-only skin for chapters
  2, 4, 6, 8 and 10, and a "Chapter complete" card. Reward skins cannot be
  bought.
- **Unlocking**: only clearing level `highest + 1` advances progress.
  Replays and impossible jumps never do.
- **Save schema 3** adds `levelBest` (best score per level) and
  `chapterRewards`. The migration from schema 2:
  - Coins, upgrades, skins, stars and progress carry over unchanged.
  - A player who had already beaten the old stage-10 boss gets
    `chapterRewards = [1]`, so that reward is not paid a second time, and
    chapter 2 opens for them.
  - Older schemas still migrate step by step.
- **Achievements**: two campaign goals added ("Defeat the Void Devourer",
  "Defeat the Worldbreaker"). The old ids are unchanged, so earlier claims
  still count.
- **No pay-to-progress**: the simulated player below finishes every level
  using only coins earned in play. It never watches an ad or buys anything.

## 8. Calibration results

`flutter test tool/balance/campaign_report_test.dart` plays levels 1–100 in
order with the scripted `AutoPlayer` (`test/support/auto_player.dart`):

- It reacts with a delay, steers at a finger's speed and dodges telegraphs,
  zones, shards and predicted crystal paths.
- It picks elements by affinity, armour and Hydra heads.
- It uses power-ups in emergencies.
- It starts with nothing and buys the upgrade with the best damage gain per
  coin.
- After a failed attempt it replays the previous level once.
- Each retry plays slightly differently.

Results of the final run:

| Chapter | Avg attempts | Avg hits taken (of 3) | Avg clear time |
|---|---|---|---|
| 1 | 1.1 | 0.4 | 50 s |
| 2 | 1.0 | 0.7 | 50 s |
| 3 | 1.4 | 1.2 | 53 s |
| 4 | 1.0 | 0.7 | 40 s |
| 5 | 1.3 | 1.0 | 43 s |
| 6 | 1.1 | 0.7 | 49 s |
| 7 | 1.0 | 0.5 | 50 s |
| 8 | 1.7 | 1.1 | 46 s |
| 9 | 1.0 | 0.9 | 48 s |
| 10 | 1.0 | 1.0 | 50 s |

- All 100 levels were cleared and no level was ever failed outright.
- The bot's damage per second stayed between 1.1× and 2.2× the level's
  durability scale for the whole campaign.
- It earned 127k coins in total and reached near-max upgrades only in the
  final chapter.

A human player who spends coins on cosmetics will be weaker than this bot.
That is the reason for the margin above 1.0×.

## 9. The 100 levels

Columns:

- Pace, drift and bounce come from the level data.
- HP scale is the durability of wave 1.
- Attempts, clear time, hits, coins earned and DPS come from the simulated
  playthrough. Hits are listed by cause: ball, shot, zap, lava or slam.

The table is regenerated by `tool/balance/campaign_report_test.dart` into
`build/campaign_report.md`.

| Lvl | Ch | Category | Waves | Pace | Drift | Bounce | HP scale | Patterns / boss | Attempts | Clear s | Hits | Coins earned | DPS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | intro | 2 | 0.47 | 1.00 | normal | 7 | standard, standard | 1 | 21 | 0 | 56 | 6 |
| 2 | 1 | easy | 3 | 0.48 | 1.00 | normal | 11 | standard, standard, standard | 1 | 52 | 0 | 68 | 6 |
| 3 | 1 | normal | 3 | 0.51 | 1.00 | normal | 17 | standard, armored, standard | 2 | 61 | 1 {ball: 1} | 150 | 13 |
| 4 | 1 | newPattern | 3 | 0.50 | 1.01 | normal | 18 | standard, standard, standard | 1 | 46 | 0 | 135 | 20 |
| 5 | 1 | challenge | 2 | 0.53 | 1.01 | normal | 24 | standard, skyraid | 1 | 34 | 1 {shot: 1} | 124 | 26 |
| 6 | 1 | recovery | 2 | 0.46 | 1.01 | normal | 21 | standard, mixed | 1 | 24 | 0 | 137 | 29 |
| 7 | 1 | hard | 3 | 0.53 | 1.01 | normal | 35 | mixed, standard, mixed | 1 | 60 | 1 {ball: 1} | 172 | 31 |
| 8 | 1 | preparation | 4 | 0.53 | 1.01 | normal | 35 | standard, standard, standard, standard | 1 | 84 | 0 | 342 | 39 |
| 9 | 1 | finalTest | 3 | 0.54 | 1.02 | normal | 47 | mixed, standard, mixed | 1 | 54 | 0 | 266 | 47 |
| 10 | 1 | boss | 2 | 0.48 | 1.02 | normal | 44 | **Crystal Colossus** | 1 | 64 | 1 {shot: 1} | 466 | 54 |
| 11 | 2 | intro | 2 | 0.50 | 1.02 | normal | 34 | treasure, standard | 1 | 24 | 0 | 265 | 63 |
| 12 | 2 | easy | 3 | 0.51 | 1.02 | normal | 42 | standard, skyraid, standard | 1 | 44 | 0 | 344 | 67 |
| 13 | 2 | normal | 3 | 0.54 | 1.02 | normal | 57 | skyraid, standard, skyraid | 1 | 59 | 1 {ball: 1} | 329 | 71 |
| 14 | 2 | newPattern | 3 | 0.53 | 1.03 | normal | 55 | swarm, swarm, skyraid | 1 | 40 | 1 {ball: 1} | 238 | 82 |
| 15 | 2 | challenge | 2 | 0.56 | 1.03 | normal | 75 | skyraid, swarm | 1 | 35 | 0 | 290 | 82 |
| 16 | 2 | recovery | 2 | 0.49 | 1.03 | normal | 53 | treasure, standard | 1 | 22 | 0 | 278 | 86 |
| 17 | 2 | hard | 3 | 0.56 | 1.03 | normal | 82 | mixed, skyraid, mixed | 1 | 76 | 2 {ball: 2} | 379 | 86 |
| 18 | 2 | preparation | 4 | 0.56 | 1.03 | normal | 79 | skyraid, swarm, standard, skyraid | 1 | 80 | 2 {ball: 2} | 414 | 97 |
| 19 | 2 | finalTest | 3 | 0.57 | 1.04 | normal | 101 | mixed, skyraid, mixed | 1 | 62 | 1 {ball: 1} | 421 | 97 |
| 20 | 2 | boss | 2 | 0.51 | 1.04 | normal | 89 | **Storm Engine** | 1 | 58 | 0 | 766 | 105 |
| 21 | 3 | intro | 2 | 0.53 | 1.04 | normal | 66 | giants, standard | 1 | 32 | 0 | 361 | 111 |
| 22 | 3 | easy | 3 | 0.54 | 1.04 | normal | 79 | standard, hazardField, standard | 1 | 41 | 1 {ball: 1} | 413 | 117 |
| 23 | 3 | normal | 3 | 0.57 | 1.04 | normal | 104 | hazardField, standard, hazardField | 1 | 73 | 2 {ball: 2} | 498 | 117 |
| 24 | 3 | newPattern | 3 | 0.56 | 1.05 | normal | 98 | hazardField, hazardField, hazardField | 1 | 51 | 2 {ball: 2} | 445 | 130 |
| 25 | 3 | challenge | 2 | 0.59 | 1.05 | normal | 131 | hazardField, hazardField | 1 | 53 | 1 {ball: 1} | 421 | 130 |
| 26 | 3 | recovery | 2 | 0.51 | 1.05 | normal | 89 | treasure, standard | 1 | 26 | 0 | 404 | 136 |
| 27 | 3 | hard | 3 | 0.59 | 1.05 | normal | 137 | mixed, hazardField, mixed | 3 | 81 | 2 {ball: 2} | 1039 | 136 |
| 28 | 3 | preparation | 4 | 0.59 | 1.05 | normal | 129 | hazardField, hazardField, standard, hazardField | 3 | 82 | 2 {ball: 2} | 1398 | 143 |
| 29 | 3 | finalTest | 3 | 0.60 | 1.06 | normal | 161 | mixed, hazardField, mixed | 1 | 51 | 1 {ball: 1} | 575 | 285 |
| 30 | 3 | boss | 2 | 0.54 | 1.06 | normal | 140 | **Molten Titan** | 1 | 40 | 1 {lava: 1} | 1067 | 285 |
| 31 | 4 | intro | 2 | 0.56 | 1.06 | normal | 102 | elemental, standard | 1 | 21 | 0 | 542 | 314 |
| 32 | 4 | easy | 3 | 0.57 | 1.06 | normal | 120 | standard, elemental, standard | 1 | 33 | 1 {ball: 1} | 543 | 314 |
| 33 | 4 | normal | 3 | 0.60 | 1.06 | normal | 156 | elemental, standard, elemental | 1 | 46 | 1 {ball: 1} | 589 | 314 |
| 34 | 4 | newPattern | 3 | 0.54 | 1.07 | low | 129 | standard, standard, elemental | 1 | 44 | 0 | 720 | 328 |
| 35 | 4 | challenge | 2 | 0.57 | 1.07 | low | 192 | elemental, standard | 1 | 35 | 1 {ball: 1} | 621 | 328 |
| 36 | 4 | recovery | 2 | 0.54 | 1.07 | normal | 129 | treasure, standard | 1 | 22 | 0 | 562 | 328 |
| 37 | 4 | hard | 3 | 0.62 | 1.07 | normal | 196 | mixed, elemental, mixed | 1 | 53 | 1 {ball: 1} | 737 | 328 |
| 38 | 4 | preparation | 4 | 0.62 | 1.07 | normal | 183 | elemental, standard, standard, elemental | 1 | 61 | 0 | 840 | 358 |
| 39 | 4 | finalTest | 3 | 0.63 | 1.08 | normal | 227 | mixed, elemental, mixed | 1 | 50 | 2 {ball: 2} | 635 | 358 |
| 40 | 4 | boss | 2 | 0.57 | 1.08 | normal | 195 | **Frost Guardian** | 1 | 39 | 1 {shot: 1} | 1392 | 358 |
| 41 | 5 | intro | 2 | 0.59 | 1.08 | high | 140 | standard, standard | 1 | 18 | 0 | 724 | 388 |
| 42 | 5 | easy | 3 | 0.60 | 1.08 | normal | 165 | standard, elemental, standard | 1 | 40 | 1 {ball: 1} | 768 | 388 |
| 43 | 5 | normal | 3 | 0.63 | 1.08 | normal | 212 | elemental, standard, elemental | 1 | 46 | 1 {ball: 1} | 794 | 388 |
| 44 | 5 | newPattern | 3 | 0.62 | 1.09 | normal | 196 | elemental, elemental, elemental | 1 | 42 | 2 {ball: 2} | 699 | 404 |
| 45 | 5 | challenge | 2 | 0.65 | 1.09 | normal | 257 | elemental, elemental | 1 | 34 | 0 | 768 | 404 |
| 46 | 5 | recovery | 2 | 0.57 | 1.09 | normal | 172 | treasure, standard | 1 | 23 | 0 | 702 | 404 |
| 47 | 5 | hard | 3 | 0.65 | 1.09 | high | 259 | mixed, elemental, mixed | 1 | 54 | 2 {ball: 2} | 734 | 404 |
| 48 | 5 | preparation | 4 | 0.65 | 1.09 | normal | 241 | elemental, elemental, standard, elemental | 2 | 63 | 2 {ball: 2} | 1726 | 434 |
| 49 | 5 | finalTest | 3 | 0.66 | 1.10 | normal | 296 | mixed, elemental, mixed | 1 | 58 | 0 | 900 | 434 |
| 50 | 5 | boss | 2 | 0.60 | 1.10 | normal | 253 | **Void Devourer** | 3 | 54 | 2 {shot: 1, zap: 1} | 2543 | 434 |
| 51 | 6 | intro | 2 | 0.62 | 1.10 | normal | 181 | armoredSwarm, standard | 1 | 21 | 0 | 873 | 468 |
| 52 | 6 | easy | 3 | 0.63 | 1.10 | normal | 212 | standard, armored, standard | 1 | 36 | 0 | 1068 | 468 |
| 53 | 6 | normal | 3 | 0.66 | 1.11 | normal | 271 | armored, standard, armored | 1 | 47 | 1 {ball: 1} | 1095 | 468 |
| 54 | 6 | newPattern | 5 | 0.65 | 1.11 | normal | 208 | standard, armored, swarm, armoredSwarm, mixed | 1 | 70 | 0 | 1236 | 468 |
| 55 | 6 | challenge | 2 | 0.63 | 1.11 | low | 325 | armored, mixed | 1 | 43 | 0 | 1067 | 468 |
| 56 | 6 | recovery | 2 | 0.60 | 1.11 | normal | 217 | treasure, standard | 1 | 21 | 0 | 877 | 468 |
| 57 | 6 | hard | 3 | 0.68 | 1.11 | normal | 325 | mixed, armored, mixed | 2 | 62 | 2 {ball: 2} | 1873 | 468 |
| 58 | 6 | preparation | 5 | 0.68 | 1.12 | normal | 241 | armored, mixed, standard, armored, armored | 1 | 87 | 1 {ball: 1} | 1542 | 501 |
| 59 | 6 | finalTest | 3 | 0.69 | 1.12 | normal | 369 | mixed, armored, mixed | 1 | 45 | 2 {ball: 2} | 1112 | 501 |
| 60 | 6 | boss | 2 | 0.63 | 1.12 | normal | 314 | **Iron Behemoth** | 1 | 54 | 1 {shot: 1} | 2224 | 501 |
| 61 | 7 | intro | 2 | 0.65 | 1.12 | normal | 224 | skyraid, standard | 1 | 32 | 0 | 1165 | 501 |
| 62 | 7 | easy | 3 | 0.66 | 1.12 | normal | 261 | standard, skyraid, standard | 1 | 44 | 1 {ball: 1} | 1186 | 501 |
| 63 | 7 | normal | 3 | 0.69 | 1.13 | normal | 333 | skyraid, standard, skyraid | 1 | 56 | 0 | 1417 | 752 |
| 64 | 7 | newPattern | 3 | 0.68 | 1.13 | normal | 305 | elemental, elemental, skyraid | 1 | 54 | 0 | 1290 | 752 |
| 65 | 7 | challenge | 2 | 0.71 | 1.13 | normal | 397 | skyraid, elemental | 1 | 45 | 0 | 1185 | 752 |
| 66 | 7 | recovery | 2 | 0.64 | 1.13 | normal | 264 | treasure, standard | 1 | 25 | 0 | 1077 | 752 |
| 67 | 7 | hard | 3 | 0.71 | 1.13 | high | 394 | mixed, skyraid, mixed | 1 | 68 | 1 {ball: 1} | 1446 | 752 |
| 68 | 7 | preparation | 4 | 0.71 | 1.14 | normal | 364 | skyraid, elemental, standard, skyraid | 1 | 81 | 1 {ball: 1} | 1575 | 752 |
| 69 | 7 | finalTest | 3 | 0.72 | 1.14 | normal | 445 | mixed, skyraid, mixed | 1 | 56 | 1 {ball: 1} | 1249 | 752 |
| 70 | 7 | boss | 2 | 0.66 | 1.14 | normal | 377 | **Prism Hydra** | 1 | 42 | 1 {shot: 1} | 2672 | 802 |
| 71 | 8 | intro | 2 | 0.68 | 1.14 | normal | 269 | giants, standard | 1 | 24 | 0 | 1213 | 802 |
| 72 | 8 | easy | 3 | 0.69 | 1.14 | normal | 312 | standard, giants, standard | 1 | 35 | 0 | 1430 | 802 |
| 73 | 8 | normal | 3 | 0.72 | 1.15 | normal | 397 | giants, standard, giants | 1 | 52 | 1 {ball: 1} | 1606 | 802 |
| 74 | 8 | newPattern | 3 | 0.71 | 1.15 | normal | 363 | hazardField, hazardField, giants | 1 | 46 | 1 {ball: 1} | 1463 | 802 |
| 75 | 8 | challenge | 2 | 0.69 | 1.15 | low | 471 | giants, hazardField | 1 | 44 | 1 {ball: 1} | 1392 | 802 |
| 76 | 8 | recovery | 2 | 0.67 | 1.15 | normal | 312 | treasure, standard | 1 | 29 | 0 | 1214 | 802 |
| 77 | 8 | hard | 3 | 0.74 | 1.15 | normal | 465 | mixed, giants, mixed | 1 | 61 | 2 {ball: 2} | 1632 | 802 |
| 78 | 8 | preparation | 4 | 0.74 | 1.16 | normal | 430 | giants, hazardField, standard, giants | 3 | 72 | 2 {ball: 2} | 5746 | 852 |
| 79 | 8 | finalTest | 3 | 0.75 | 1.16 | normal | 523 | mixed, giants, mixed | 6 | 54 | 2 {ball: 2} | 9968 | 852 |
| 80 | 8 | boss | 2 | 0.69 | 1.16 | normal | 443 | **Gravity Core** | 1 | 38 | 2 {shot: 2} | 3142 | 852 |
| 81 | 9 | intro | 2 | 0.71 | 1.16 | normal | 315 | mixed, standard | 1 | 24 | 0 | 1496 | 902 |
| 82 | 9 | easy | 3 | 0.72 | 1.16 | normal | 365 | standard, mixed, standard | 1 | 39 | 1 {ball: 1} | 1568 | 902 |
| 83 | 9 | normal | 3 | 0.75 | 1.17 | normal | 463 | mixed, standard, mixed | 1 | 46 | 2 {ball: 2} | 1546 | 902 |
| 84 | 9 | newPattern | 3 | 0.74 | 1.17 | normal | 423 | elemental, elemental, mixed | 1 | 50 | 2 {ball: 2} | 1496 | 902 |
| 85 | 9 | challenge | 2 | 0.77 | 1.17 | normal | 548 | mixed, elemental | 1 | 40 | 2 {ball: 2} | 1404 | 902 |
| 86 | 9 | recovery | 2 | 0.70 | 1.17 | normal | 362 | treasure, standard | 1 | 25 | 0 | 1382 | 902 |
| 87 | 9 | hard | 3 | 0.77 | 1.17 | high | 539 | mixed, mixed, mixed | 1 | 54 | 1 {ball: 1} | 1848 | 902 |
| 88 | 9 | preparation | 5 | 0.77 | 1.18 | normal | 397 | mixed, elemental, standard, mixed, mixed | 1 | 83 | 0 | 2422 | 902 |
| 89 | 9 | finalTest | 3 | 0.78 | 1.18 | normal | 604 | mixed, mixed, mixed | 1 | 61 | 0 | 1906 | 902 |
| 90 | 9 | boss | 2 | 0.72 | 1.18 | normal | 511 | **Chaos Architect** | 1 | 55 | 1 {ball: 1} | 3822 | 902 |
| 91 | 10 | intro | 2 | 0.74 | 1.18 | normal | 362 | mixed, standard | 1 | 21 | 0 | 1545 | 902 |
| 92 | 10 | easy | 3 | 0.75 | 1.18 | normal | 419 | standard, mixed, standard | 1 | 38 | 0 | 2018 | 902 |
| 93 | 10 | normal | 3 | 0.78 | 1.19 | normal | 531 | mixed, standard, mixed | 1 | 60 | 2 {ball: 2} | 1958 | 902 |
| 94 | 10 | newPattern | 3 | 0.77 | 1.19 | normal | 484 | mixed, mixed, mixed | 1 | 48 | 1 {ball: 1} | 1679 | 902 |
| 95 | 10 | challenge | 2 | 0.73 | 1.19 | low | 627 | mixed, mixed | 1 | 35 | 1 {ball: 1} | 1731 | 952 |
| 96 | 10 | recovery | 2 | 0.73 | 1.19 | normal | 414 | treasure, standard | 1 | 24 | 0 | 1543 | 952 |
| 97 | 10 | hard | 3 | 0.78 | 1.19 | normal | 615 | mixed, mixed, mixed | 1 | 65 | 2 {ball: 2} | 1714 | 952 |
| 98 | 10 | preparation | 5 | 0.78 | 1.20 | normal | 453 | mixed, mixed, standard, mixed, mixed | 1 | 90 | 2 {ball: 2} | 2550 | 952 |
| 99 | 10 | finalTest | 3 | 0.78 | 1.20 | normal | 688 | mixed, mixed, mixed | 1 | 50 | 0 | 2000 | 952 |
| 100 | 10 | boss | 2 | 0.75 | 1.20 | normal | 580 | **Worldbreaker** | 1 | 69 | 2 {shot: 2} | 5369 | 952 |
