# Production Setup

Everything below needs your accounts or decisions; nothing here has been done
or verified for you.

## 1. Package name (do this first, it is permanent)

Chosen and applied (2026-10-28):

- Android: `com.boomforge.game` (`android/app/build.gradle.kts`,
  `namespace` + `applicationId`;
  `android/app/src/main/kotlin/com/boomforge/game/MainActivity.kt`).
- iOS: `com.boomforge.game` (Xcode → Runner → Signing & Capabilities).

Google Play never allows changing it after the first upload. The same ID is
registered in Firebase (see docs/FIREBASE_SETUP.md).

## 2. Android release signing

```bash
keytool -genkey -v -keystore C:/keys/boomforge-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (git-ignored):

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/keys/boomforge-upload.jks
```

Without this file `flutter build appbundle` stops with an error; only local
APK builds fall back to the debug key. Back up the keystore and passwords;
enable Play App Signing.

## 3. AdMob

1. Create an AdMob account and two apps (Android, iOS).
2. Create ad units: one **Rewarded** and one **Interstitial** per platform.
3. Android: copy `release.json.example` to `release.json` (git-ignored), fill
   in the app ID and unit IDs, and build:

```bash
flutter build appbundle --release --dart-define-from-file=release.json
```

   The build stops with an error if the upload key or any ID is missing,
   malformed, one of Google's samples, or from a different publisher. For a
   deliberately ad-free release, set `"ADS_DISABLED": "true"` instead.
4. iOS app ID: replace `GADApplicationIdentifier` in `ios/Runner/Info.plist`
   and add Google's `SKAdNetworkItems` list.
5. iOS unit IDs are passed at build time:

```bash
flutter build ipa --release \
  --dart-define=ADMOB_REWARDED_IOS=ca-app-pub-XXXX/3333 \
  --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-XXXX/4444
```

6. In AdMob → Privacy & messaging, publish a GDPR consent message (and US
   state message if needed). The app already calls the UMP SDK and shows
   "Ad Privacy Choices" in Settings when required.
7. If your audience includes children, build with
   `--dart-define=ADMOB_CHILD_DIRECTED=true`, review Google Play Families
   policy, and consider removing interstitials.
8. iOS App Tracking Transparency is **not** implemented; ads on iOS will be
   non-personalised unless you add an ATT prompt
   (`NSUserTrackingUsageDescription` + a plugin).
9. Add `app-ads.txt` to `website/` with the line AdMob gives you, and deploy.

Behaviour without IDs: debug/profile builds show Google test ads; local
release APKs disable ads. `ADS_DISABLED=true` turns ads off everywhere.

## 4. Privacy policy and terms

- The policies are live on Firebase Hosting (source in `website/`; see
  docs/FIREBASE_SETUP.md). The in-app copies are in
  `lib/ui/screens/legal_screen.dart`; keep both in sync.
- The contact email is in `website/privacy.html` and `AppConfig.supportEmail`
  (`SUPPORT_EMAIL` in `release.json` overrides the in-app one).

## 5. Store listing assets

All in `store/`, text in `docs/STORE_LISTING.md`:

- `icon-512.png` and `feature-graphic.png` (1024×500).
- `screenshots/` at 1080×1920 without alpha. Play rejects images taller than
  2:1, so `tool/screenshots/out/` (1080×2340) cannot be uploaded.

To regenerate (PowerShell, with `FLUTTER_ROOT` set to the Flutter SDK):

```powershell
$env:STORE_SHOTS=1; flutter test tool/screenshots/screenshots_test.dart --update-goldens
flutter test tool/render_store_art_test.dart
```
