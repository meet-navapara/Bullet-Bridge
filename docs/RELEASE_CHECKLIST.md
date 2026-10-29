# Release Checklist

Passing this list does not mean store approval; Google and Apple review
every submission.

## Before the first build

- [ ] Final package name / bundle ID chosen (docs/PRODUCTION_SETUP.md §1)
- [ ] App name and `APP_TITLE` final; launcher labels updated
- [ ] Decide whether to rename the Dart package (`orbit_blast`) before release
- [ ] `version:` bumped in `pubspec.yaml` (`1.0.0+1` → name+build number)
- [ ] Upload keystore created, `android/key.properties` present, backed up
- [ ] AdMob app IDs and unit IDs configured (or ads deliberately disabled)
- [ ] Privacy policy hosted; URLs passed via `--dart-define`
- [ ] Bracketed placeholders in `legal_screen.dart` filled in

## Quality

- [ ] `dart format .`, `flutter analyze` clean, `flutter test` green
- [ ] Played 20+ minutes on a mid-range Android phone in `--profile`;
      DevTools shows no sustained jank at wave 10+
- [ ] Tested a small phone (≈360 dp wide) and a tall phone (20:9)
- [ ] Sound, music, vibration and all toggles verified by ear/hand
- [ ] Backgrounding during a run pauses it; killing the app on game over
      keeps the coins
- [ ] Debug test ads: consent form, rewarded continue, rewarded coins,
      interstitial frequency
- [ ] Release build with real IDs installed from an internal test track

## Google Play Console

- [ ] `flutter build appbundle --release` (+ dart-defines) uploaded to
      internal testing first
- [ ] Data safety form (with ads):
  - Data collected by the AdMob SDK: device or other IDs (advertising ID),
    approximate location (from IP), app interactions / diagnostics,
    used for advertising and analytics; shared with Google
  - Data encrypted in transit: yes (SDK); users can request deletion: no
    server data held by you
  - The game itself stores progress only on the device
- [ ] "Contains ads": **Yes**
- [ ] Advertising ID declaration: Yes (AdMob uses it) — the
      `AD_ID` permission is merged from the SDK
- [ ] Content rating questionnaire (cartoon/fantasy violence: mild,
      no user interaction, no purchases)
- [ ] Target audience: if under-13s are included, follow Families policy
      and set `ADMOB_CHILD_DIRECTED=true`
- [ ] Store listing: short/full description, icon, feature graphic,
      ≥2 phone screenshots
- [ ] Privacy policy URL entered

## Apple App Store (requires macOS)

- [ ] Bundle ID, signing team and provisioning in Xcode
- [ ] `GADApplicationIdentifier` + `SKAdNetworkItems` in Info.plist
- [ ] Decide on ATT prompt (not implemented); answer App Privacy
      questions consistently with the SDKs used
- [ ] `flutter build ipa --release` and test via TestFlight
- [ ] Age rating, screenshots for required device sizes

## After release

- [ ] Monitor Play Console vitals (ANRs, crashes)
- [ ] Revisit balance (`docs/GAME_BALANCING.md`) with real play data
