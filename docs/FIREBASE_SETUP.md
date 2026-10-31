# Firebase setup (cloud save, analytics, crash reports)

BOOMFORGE already contains all the Firebase code. Until you add your
project's config files, the game runs exactly as before: progress is saved
on the phone, and Settings → Cloud Save says "not available". This guide
connects the game to your own Firebase project.

## App identity

| | Value |
|---|---|
| **Android package name** | `com.boomforge.game` |
| **iOS bundle ID** | `com.boomforge.game` |
| App name | BOOMFORGE |
| Debug signing SHA-1 (this PC) | `27:0D:D6:19:7D:72:9E:FC:4D:C2:D2:EC:B1:79:4E:7C:CE:16:70:18` |
| Debug signing SHA-256 (this PC) | `3E:98:1F:DC:85:FD:26:96:63:EF:58:91:73:E2:37:B7:5E:77:C9:06:3E:84:6C:84:B0:A8:B6:1E:52:6A:D4:11` |

The package name is permanent once the app is on Google Play.

## What is included

| Feature | Firebase product | Where in code |
|---|---|---|
| First-launch choice: "Continue with Google" or "Continue as Guest" | none | `lib/ui/screens/welcome_screen.dart` |
| Google sign-in to keep progress after a reinstall or on a new phone | Authentication → Google | `lib/services/cloud/firebase_cloud_backend.dart`, `linkGoogle` |
| Cloud copy of all progress | Cloud Firestore, `players/{uid}` | `lib/services/cloud/cloud_sync.dart` |
| Safe merging of two devices' progress | none (game code) | `lib/progress/save_merge.dart` |
| Gameplay statistics | Google Analytics | `lib/services/analytics_service.dart` |
| Crash reports | Crashlytics | `lib/services/firebase_setup.dart` |
| Settings: cloud status, Google sign-in, Sign Out, Sync Now, Delete Cloud Data, Share Usage Data switch | none | `lib/ui/widgets/cloud_save_panel.dart` |
| Security rules | Firestore rules | `firestore.rules` (with `firebase.json`) |

### How progress is kept

1. On first launch the player chooses. A guest has no account: progress stays
   on the phone and the rest of this list does not apply.
2. After Google sign-in, and at each launch after that, the game downloads the
   cloud save, merges it with the phone's save and uploads the result.
3. After every change (a finished level, a purchase, a setting) the game
   uploads within about 4 seconds. Several changes close together are sent
   as one write. Leaving the app uploads immediately.
4. Without internet, everything keeps working locally. Firestore's offline
   cache sends the changes later.

**Merge rules.** Nothing earned is ever lost, and coins are never
duplicated:

- **Taken as the maximum or union of both saves:** levels cleared, stars,
  best scores, upgrades, owned skins and themes, claimed rewards,
  statistics, the tutorial flag.
- **Taken from whichever save changed last:** coins, daily-reward state and
  selected cosmetics.
- **Never synced:** settings stay as they are on each phone.

**Accounts:**

- Guest progress is lost if the app is uninstalled. Guests can sign in later
  in Settings, which uploads what they have.
- After a reinstall, or on a new phone, signing in again finds the existing
  save and merges it into the phone.
- "Sign Out" stops uploading and keeps the cloud save for the next sign-in.
- "Delete Cloud Data" removes the document and the account, and the phone goes
  back to guest. Google Play requires this option for apps that create
  accounts.

## Step 1: Create the Firebase project

1. Go to <https://console.firebase.google.com> and click **Add project**.
   Name it, for example, `boomforge`.
2. Keep **Google Analytics enabled** and pick or create an Analytics
   account.

## Step 2: Add the Android app

1. Project overview → **Add app** → Android.
2. Enter these details:
   - **Android package name:** `com.boomforge.game`
   - **App nickname:** BOOMFORGE
   - **Debug signing certificate SHA-1:** the SHA-1 from the table above.
3. **Register app** → **Download `google-services.json`**.
4. Put the file at `android/app/google-services.json`. Ignore the console's
   Gradle instructions; the project is already set up. The plugins switch
   on automatically when this file exists.
5. Under Project settings → Your apps → Android → **Add fingerprint**, also
   add the **SHA-256** from the table.

Later, for Play Store builds, add two more pairs of fingerprints. After
each change, download `google-services.json` again and replace the file:

- the SHA-1 and SHA-256 of your **upload key** (see
  docs/PRODUCTION_SETUP.md):
  `keytool -list -v -keystore upload-keystore.jks -alias upload`
- the SHA-1 and SHA-256 of the **Play App Signing key**, from Play Console
  → your app → Test and release → App integrity.

Google sign-in fails for any build signed with a key that is not listed.

## Step 3: Add the iOS app (only if you ship on iOS)

1. **Add app** → iOS, with **Bundle ID** `com.boomforge.game`.
2. Download `GoogleService-Info.plist`.
3. Open `ios/Runner.xcworkspace` in Xcode, drag the file into the
   **Runner** group, and tick "Copy items if needed" and the Runner target.
4. For Google sign-in on iOS:
   1. Open the plist and copy `REVERSED_CLIENT_ID`.
   2. In Xcode, go to Runner → Info → URL Types → **+**.
   3. Paste it into **URL Schemes**.
5. Run `cd ios && pod install`. This needs macOS and Xcode.

## Step 4: Turn on the Firebase products

1. **Authentication** → Get started → Sign-in method:
   - Enable **Google**: choose a support email and save. Anonymous sign-in is
     no longer used.
2. **Firestore Database** → Create database:
   1. Choose **Production mode**.
   2. Pick a location close to your players, for example `asia-south1`
      (Mumbai) for India. The location cannot be changed later.
3. Firestore → **Rules**: replace everything with the contents of
   `firestore.rules` in this repository, then click **Publish**. Or deploy
   them with the CLI:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase use --add            # pick your project
   firebase deploy --only firestore:rules
   ```
4. **Crashlytics** → Get started. It activates once the app has started
   and sent a report.
5. **Analytics** is on already. Events appear in DebugView or after about
   24 hours.

## Step 5: Build and check

```bash
flutter clean
flutter run            # or: flutter build apk --release
```

On the phone:

1. On the first screen, tap **Continue with Google** and choose an account.
2. Open **Settings → Cloud Save** and check that the panel shows your email.
3. In Firebase console → Firestore → Data, a document should appear under
   `players/` with a `save` map.
4. Test a restore: clear the app's data, or install it on a second phone.
   Open Settings → **Sign in with Google** with the same account; your
   levels, stars and upgrades come back.
5. Test crash reports with a release build. Crashlytics only collects in
   release builds, and only when "Share Usage Data" is on.

To watch analytics events live, turn on debug mode, then open Firebase
console → Analytics → DebugView:

```bash
adb shell setprop debug.firebase.analytics.app com.boomforge.game
```

## Events logged

| Event | Parameters |
|---|---|
| `level_start` | `level_name` (`level_7`) |
| `level_end` | `level_name`, `success` (0/1), `stars`, `seconds`, `score` |
| `boss_defeated` | `level`, `boss` |
| `chapter_complete` | `chapter` |
| `endless_end` | `wave`, `score` |
| `upgrade_bought` | `upgrade`, `level` |
| `cloud_linked` | none |
| `screen_view` | `screen_name` (widget name, such as `ShopScreen`) |
| `button_tap` | `button` (its label) |
| `account_choice` | `choice` (`guest` or `google`) |
| `account_signed_out`, `account_deleted` | none |
| `element_selected` | `element` |
| `power_up_used` | `power_up` |
| `rewarded_ad` | `placement` (`continue` or `shop`), `earned` (0/1) |
| `interstitial_shown` | none |
| `item_bought` | `item` |

No names, emails or device identifiers are logged as event data. Turning
off "Share Usage Data" stops analytics and crash reports.

## Store and privacy checklist

- **Privacy policy:** add the Firebase section from
  docs/PRIVACY_POLICY_TEMPLATE.md.
- **Google Play Data safety form:**
  - App activity (gameplay events) and Crash logs: collected, used for
    analytics, not shared, user can opt out.
  - Account and app data: user IDs, stored to provide cloud saves.
  - Email address: only when the player signs in with Google.
  - All data is encrypted in transit.
  - Users can request deletion through Settings → Delete Cloud Data.
- **Account deletion:** Play also asks for a web link where users can
  request deletion. A simple form or email address on your website is
  enough.

## Costs

The free Spark plan covers a small or medium game:

- Firestore allows 50,000 reads and 20,000 writes per day. A player uses
  about 1 read and 5–20 writes per session.
- Anonymous and Google sign-in are free.
- Analytics and Crashlytics are free.

If daily active players climb into the thousands, watch Firestore usage
under Usage and billing.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Settings says "not available in this build" | `android/app/google-services.json` is missing, or its package name is not `com.boomforge.game`. Run `flutter clean` and rebuild. |
| Stays "Offline" | No internet, or Firestore was never created. Check Firestore → Data. |
| `PERMISSION_DENIED` in logs | The rules were not published. |
| "Sign-in is turned off" message | Google sign-in is disabled: Authentication → Sign-in method → Google → Enable. |
| Google sign-in fails or does nothing | Add the SHA-1 and SHA-256 of the key that signed this build, download a fresh `google-services.json`, and check that the Google provider is enabled. The error `clientConfigurationError` usually means a missing fingerprint. |
| Account sheet shows the wrong app name | Project settings → General → **Public-facing name**. |
| No crash reports | Crashlytics only reports from release builds, after the app restarts, with Share Usage Data on. |

## Website: privacy policy, terms, account deletion

The game's website is in `website/` and is served by Firebase Hosting:

| Page | URL |
|---|---|
| Home | https://ball-blast-d0a65.web.app |
| Privacy Policy | https://ball-blast-d0a65.web.app/privacy |
| Terms of Service | https://ball-blast-d0a65.web.app/terms |
| Delete account | https://ball-blast-d0a65.web.app/delete-account |

The game opens these from Settings (`AppConfig` in
`lib/config/app_config.dart`). Override them with `--dart-define`
(`PRIVACY_POLICY_URL`, `TERMS_URL`, `DELETE_ACCOUNT_URL`) if you move the
site to your own domain.

The delete page offers three ways to delete an account:

1. In the game: Settings → Cloud Save → Delete Cloud Data.
2. Google-linked players sign in on the page and delete their account and
   save themselves.
3. Anyone who can't sign in sends their Player ID (shown in Settings → Cloud
   Save) through a form. Guests have no cloud data to delete. Requests land in Firestore → `deletionRequests`. **Check them
   regularly**: within 30 days, delete `players/{Player ID}` and the user
   (Authentication → Users → search the ID), then delete the request.

After editing the site or the rules, deploy both:

```bash
firebase deploy --only hosting,firestore:rules
```

To use your own domain, go to Hosting → Add custom domain.

## Google Play checklist

Checked against Play policy, October 2026:

| Requirement | Status |
|---|---|
| Target API level 36 (new apps and updates from 31 Aug 2026) | Done (`targetSdk` 36) |
| Privacy policy URL in Play Console and inside the app | Done (`/privacy`, Settings → Privacy Policy) |
| In-app account deletion for apps that create accounts | Done (Delete Cloud Data) |
| Web account-deletion link that works without the app | Done (`/delete-account`); enter it in Data safety |
| Privacy policy names the developer and a privacy contact | Done (`website/privacy.html` and `AppConfig.supportEmail`) |
| Data safety form matches the app | Fill it in as in "Store and privacy checklist" above |
| Target audience | The policies say 13+. If you choose an audience under 13, the Families policy applies: ads must be child-directed (`ADMOB_CHILD_DIRECTED=true`), and Google sign-in, Analytics and the policy need review. |
| Ads declaration | Answer "Yes, contains ads" if AdMob unit IDs are set in the release |
| Release signing SHA-1 and SHA-256 in Firebase | **To do** after the first upload (see Step 2), or Google sign-in fails in Play builds |

## Moving your current phone's progress

The game used to be installed as `com.orbitblast.orbit_blast`. The new
package `com.boomforge.game` installs as a separate app. To carry your
local progress over once, while both debug builds are installed:

1. With the phone connected, copy the save from the old app to the new one:
   ```bash
   adb shell run-as com.orbitblast.orbit_blast cat shared_prefs/FlutterSharedPreferences.xml > save.xml
   adb push save.xml /data/local/tmp/save.xml
   adb shell "run-as com.boomforge.game sh -c 'mkdir -p shared_prefs && cat /data/local/tmp/save.xml > shared_prefs/FlutterSharedPreferences.xml'"
   ```
2. Uninstall the old app.
