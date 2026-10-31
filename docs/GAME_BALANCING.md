# Game Balancing

All numbers live in `lib/config/balance.dart`.

> **The 1000-level campaign, speed and bosses are documented in
> [LEVEL_BALANCING.md](LEVEL_BALANCING.md)**, which supersedes the old
> "Campaign (World 1)" and "Prism Colossus" sections below. Those sections
> are kept as a record of the 10-stage version. This file remains current
> for the arena, creatures, elements, hazards, upgrades and rewards.

Regenerate the Endless table with
`flutter test tool/balance/balance_report_test.dart`, and the campaign
table with `flutter test tool/balance/campaign_report_test.dart`.

## Arena

| Setting | Value |
|---|---|
| Arena width | 360 world units |
| Arena height | screen aspect, clamped 560–900 |
| Ground band | 72 units (element/power-up bar sits on it) |
| Simulation | 1/120 s fixed step, frame delta clamped to 0.1 s |
| Gravity | 900 units/s² |
| Pace | one time scale for every enemy (`SpeedSpec`). Campaign: set per level, 0.47 at level 1, capped at 0.78. Endless: 0.50 → 0.78 over 16 waves (`WaveSpec.paceAt`) |
| Crowding | at most 12 crystals alive before new spawns wait |
| Drag | 1:1 — the cannon moves exactly as far as the finger |
| Cannon hitbox | body 48 wide x 46 tall + barrel tip circle at 68 (art drawn at 1.25x) |
| Hull | 3 hearts, 1.4 s invulnerability after a hit |

## Creatures

| Type | Behaviour | Durability |
|---|---|---|
| Shard (tiers 0–4, radius 28 / 37 / 47 / 58 / 70) | Bounces to a fixed per-size height; splits into two of the next size with 50% durability | `10 × 1.2^(d−1) × tierFactor(0.5…1.9) ± 18%` |
| Geode (tiers 2–4) | Shard with a rock shell worth 70% of its durability; 25% slower. Fire and explosions do x2 to the shell | as shard + shell |
| Skyray | Glides across the upper sky, bobbing; drops a shard every ~3.4 s (min 1.6 s) with a 0.6 s glow warning; never splits; drops 3 coins | 1.2 × scale |
| Enemy shard | Falls under gravity; costs a heart on contact; one bullet destroys it | 1 hit |

`d` is the difficulty: endless wave number, or for stages
`1 + (stage−1)×1.2 + (wave−1)×0.75`.

## Elements

| Element | Unlock | Bullet damage | Effect |
|---|---|---|---|
| Kinetic | start | 100% | none |
| Fire | clear stage 2 | 80% | splash 36 units for 50%; x2 vs rock (geodes, boss plates) |
| Ice | clear stage 4 | 85% | chill (45% speed, 1.6 s); 8 hits freeze for 1.5 s |
| Shock | clear stage 6 | 75% | arcs to the 2 nearest targets within 95 for 60% |

Frozen creatures take +50% from fire and explosions ("shatter"). The
Element Power upgrade (+10%/level, 10 levels) scales splash size, arc and
blast damage, chill and freeze duration.

## Volatile crystals and chains

| Hazard | Introduced | Detonation |
|---|---|---|
| Blaze | stage 2 | 115-unit explosion, 1.4 × scale damage, fire (x2 vs rock) |
| Frost | stage 4 | 130-unit nova, freezes for 2.5 s, 0.3 × scale damage |
| Storm | stage 6 | lightning to 5 nearest targets within 170, 1.0 × scale each |

- Hazards have 0.45 × scale durability, block bullets, and are damaged by
  other blasts, splashes and arcs. Chained detonations wait 0.12 s each.
- Hazards per wave: 1, +1 above difficulty 6, +1 above 12 (spread across
  the width at 34–52% height). Leftovers vanish when a wave ends.
- **Chain combo:** every detonation and every non-bullet kill adds 1; the
  window is 1.2 s. Chains of 3+ pay `count` coins (with coin bonus) and
  `25 × count²` score.

## Campaign (World 1): historical, see LEVEL_BALANCING.md

| Stage | New | Wave hits (seeded) | Mid loadout seconds* |
|---|---|---|---|
| 1 | shards | 15 / 21 / 55 | 1 |
| 2 | blaze crystals | 22 / 56 / 68 | 2 |
| 3 | geodes | 55 / 64 / 81 | 3 |
| 4 | frost crystals | 110 / 125 / 288 | 7 |
| 5 | skyrays | 315 / 367 / 414 | 14 |
| 6 | storm crystals | 314 / 531 / 1,120 | 25 |
| 7 | mixed | 777 / 1,554 / 1,759 | 53 |
| 8 | mixed | 1,221 / 1,404 / 1,714 | 56 |
| 9 | mixed | 1,549 / 1,789 / 2,038 | 69 |
| 10 | boss | 1,769 / 2,030 / boss core 3,767 + 2 × 848 plates | 108 |

*Mid loadout = Fire Rate 6, Bullet Power 4, Cannon Level 3 (≈78 DPS,
≈2.8k coins of upgrades). A fresh cannon (6 DPS) handles stages 1–3 and
needs upgrades from stage 4–5 on.

- Stars: 3 = no heart lost, 2 = one lost, 1 = cleared.
- Clear bonus: `15 + 5 × stage` coins, doubled on the first clear.

## Boss: Prism Colossus: historical, now the Crystal Colossus

| | Value |
|---|---|
| Core | 40 × scale; while 2/1/0 plates remain it takes 25% / 60% / 100% damage |
| Plates | 9 × scale each, x2 from fire/explosions |
| Phase 1 (>66%) | moves 55/s; shard rain every 4 s (3 columns, one on the cannon, 0.9 s warning) |
| Phase 2 (>33%) | moves 75/s; rain every 3.4 s; spawns 2 small shards every 8 s (max 6); ground slam every 9 s with 1.1 s target warning |
| Phase 3 | moves 95/s; rain every 2.6 s; 5-shard fan every 3 s; slam every 6.75 s |
| Transitions | 1.2 s invulnerable roar; spawns fresh volatile crystals beside it |
| Reward | 60 coins (shower), +2,000 score |

## Upgrades

| Upgrade | Levels | Effect | First cost | Growth |
|---|---|---|---|---|
| Fire Rate | 1–15 | 6 + 0.6/level shots/s | 60 | x1.30 |
| Bullet Power | 1–20 | damage = level | 80 | x1.38 |
| Cannon Level | 1–5 | +1 stream at Lv 3 and 5; +8% fire rate at Lv 2 and 4 | 600 | x2.2 |
| Coin Bonus | 0–10 | +10% coins/level | 150 | x1.45 |
| Starting Shield | 0–3 | Lv 1 starts shielded; each extra level +1 shield power-up | 300 | x2.5 |
| Element Power | 0–10 | +10% elemental effects/level | 200 | x1.5 |

## Rewards and power-ups

| Source | Amount |
|---|---|
| Coin drop | 60% per destroyed shard; 1/1/2/3/4 by size; geode shell 2; skyray 3 |
| Power-up drop | 4.5% per destroyed shard, max one on screen |
| Daily reward | 100, 200, 300, 500, 400 (+1 of each power-up), 600, 1,000 |
| Daily challenge | 250 once per day (fixed loadout with all elements) |
| Rewarded ad (optional) | 100 coins, max 3/day; or one revive per run |

| Power-up | Effect |
|---|---|
| Bomb | destroys creatures and detonates hazards within 175 units; 5% boss core |
| Slow Motion | everything hostile at 45% speed for 6 s |
| Shield | absorbs one hit (12 s) |
| Power Shot | x2 damage for 7 s |

Each run starts with 1 Bomb, 1 Slow Motion, 1 Power Shot; 1 s cooldown.
