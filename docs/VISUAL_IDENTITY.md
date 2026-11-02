# BOOMFORGE visual identity

The "Forge" look, introduced in the November 2026 redesign. It replaced a
bright cartoon style (wheeled field cannon, sky with snowy peaks, a grass
strip, thick black outlines) that read too close to other games in the
falling-ball shooter genre. Gameplay was not changed. See "What the redesign
did not touch" below.

## Direction

A forge at dusk: deep iron-indigo glass, molten ember and polished brass,
lit by a warm horizon. Shapes are rounded and softly bevelled, depth comes
from soft shadows instead of outlines, and the playfield stays calm so
crystals and hazards stay the brightest things on screen.

## Design system

All tokens live in `lib/ui/theme/palette.dart`.

| Token | Value | Use |
|---|---|---|
| `Palette.background` | `#0F1428` | Screen base |
| `Palette.panel` / `panelLight` | `#1A2042` / `#29315E` | Iron-glass panel gradient |
| `Palette.panelBorder` | `#414C86` | Panel rim |
| `Palette.wood` / `woodLight` | `#261C3A` / `#3A2B52` | Warm results panels (brass rim) |
| `Palette.ember` | `#FF7A2B` | Brand accent, glows, rules |
| `Palette.brass` | `#E2B15C` | Trim, eyebrow labels |
| `Palette.gold` | `#FFC24A` | Stars, cleared path, primary highlights |
| `Palette.ballTiers` | unchanged | Crystal size colours (gameplay information) |

- **Type:** Russo One (display: titles, buttons, numbers, crystal labels) with
  the platform font (Roboto on Android) for body text. `TextStyles.outlined`
  is a soft ink drop shadow, not a hard outline. `TextStyles.eyebrow` is small
  spaced brass capitals.
- **Radii:** 12 / 16 / 22 / 28 (`Radii`).
- **Spacing:** 4 / 8 / 12 / 16 / 24 / 32 (`Gaps`).
- **Elevation:** `Elevation.panel` (deep soft shadow), `Elevation.control`
  and `Elevation.glow(color)` for a coloured under-glow on primary controls.
- **Buttons** (`GameButton`): soft-bevelled body with a top sheen and a 4 px
  lip; press sinks the face and scales to 97%. Tones: molten gold (primary),
  green (go/resume), iron navy (secondary), red (destructive), blue, purple
  and white.
- **Icons:** Material rounded icons only, filled with the brass-to-ember
  gradient (`ForgeIcon`) on the menu. In-game power-up, element, coin and
  heart icons are the game's own vector art (`lib/render/icon_art.dart`,
  `hud_art.dart`). No emoji are used as icons.
- **Motion:** 280 ms fade/slide/scale page transitions, button press scale,
  the coin total rolls to its new value, the menu turret rises in, overlays
  fade and scale in, stars pop in on level clear. All of it is UI-only; none
  of it reads or changes simulation state or timing.

## Signature elements

- **Forge Strider** (`lib/render/cannon_art.dart`): a hovering turret. An
  armoured hull rides two ember thrusters, curved shoulder plates hold a
  glowing element core, and twin rails fire the bolts. It fits the same
  ~66×58 envelope the simulation's hitbox (`CannonSpec`) was sized for.
- **World** (`lib/render/world_art.dart`): ringed sun with faint rays and a
  forge-glow horizon, soft haze bands, flat-topped mesas with strata,
  clusters of hexagonal basalt columns, faceted foothills with crystal
  outcrops, and a forged-stone floor with a brass rim, ember seam and riveted
  plates.
- **Wordmark** (`GameLogo`): "BOOM" in molten metal and "FORGE" in brushed
  steel, set straight with a bevel split, and the tagline between two ember
  rules.
- **Menu:** the turret hovering over a brass pedestal ring, a chapter card
  with Play, two mode pills and a glass dock.
- **Level map:** hexagonal forge-socket nodes on a glowing seam.

## Asset sources

| Asset | Source | Licence |
|---|---|---|
| All game art (turret, crystals, bosses, world, icons, coin) | Drawn in code in `lib/render/` for this game | Original |
| Launcher icon, feature graphic, store screenshots | Rendered from the game's own art by `tool/render_icon_test.dart`, `tool/render_store_art_test.dart`, `tool/screenshots/screenshots_test.dart` | Original |
| Sound effects and music (`assets/audio/`) | Synthesised by `tool/generate_audio.dart` | Original |
| Russo One font (`assets/fonts/RussoOne-Regular.ttf`) | Google Fonts repository, by Jovanny Lemonad | SIL Open Font License 1.1 (`assets/fonts/OFL-RussoOne.txt`) |
| Material Icons, Roboto | Shipped with Flutter | Apache License 2.0 |

No third-party images, sprites, sounds or screenshots are used. The previous
font (Lilita One, also OFL) was removed with the redesign.

## What the redesign did not touch

`git diff pre-redesign-checkpoint` shows no changes in `lib/game/sim/`,
`lib/config/`, `lib/progress/`, `lib/services/`, `lib/app/`,
`lib/economy/upgrades.dart` or `lib/game/boomforge_game.dart`. Physics,
collision, hitboxes, shooting, levels, difficulty, bosses, rewards, upgrades,
saves, sign-in and ads are byte-for-byte unchanged. In
`lib/economy/catalog.dart` only the four shop themes' display names and
colours changed. Their ids and prices are unchanged, so owned themes stay
owned. The renamed themes are Forge Dawn, Ember Dusk and Brass Noon; Aurora
Night keeps its name.

## Google Play originality and policy notes

These are risk notes, not legal advice. Nothing here guarantees approval.

1. **Firebase project id `ball-blast-d0a65`.** It appears in the privacy
   policy URL in the store description, the in-app legal links
   (`AppConfig`), and the account deletion page. A reviewer comparing the
   app with the well-known "Ball Blast" game could read this as a link to it.
   The project id cannot be renamed. Firebase Hosting can add a second site
   with a neutral name (for example `boomforge-game.web.app`) or a custom
   domain; then update `PRIVACY_URL` and similar keys, the store listing and the
   Data safety form.
2. **Repository and folder names** (`Ball blast`, `Bullet-Bridge`) are not
   shipped in the app or listing and do not reach users.
3. **Genre similarity.** The core loop (steer a launcher, shoot falling
   numbered objects that split) is a common arcade mechanic and is not itself
   protected. The distinct expression (hover turret, faceted crystals and
   geodes, hazards and chain reactions, elements, bosses, forge world, UI)
   is this game's own. The store listing should describe the game on its own
   terms and never name or compare to another game.
4. **Name.** "BOOMFORGE" still needs a trademark search (USPTO, EUIPO, WIPO
   Global Brand Database) and a Play Store search before launch.
5. **Store assets** were all rendered from the build. Screenshots must keep
   matching the shipped build. Regenerate them after visual changes.
6. **Metadata accuracy.** The description must not promise features that are
   not in the build, and must disclose ads (the listing does).
7. **Third-party SDKs** (AdMob/UMP, Firebase Auth, Firestore, Analytics,
   Crashlytics, Google Sign-In) must match the Data safety form.

## Regenerating art

```
flutter test tool/screenshots/screenshots_test.dart --update-goldens
$env:STORE_SHOTS=1; flutter test tool/screenshots/screenshots_test.dart --update-goldens
flutter test tool/render_store_art_test.dart
flutter test tool/render_icon_test.dart; dart run flutter_launcher_icons
```

Then copy the store files into `store/play-upload/`.
