# Releases and OTA

Every push to `main` builds, tests, signs and publishes a GitHub release, and installed copies of August update themselves from it.

## Versioning

Bump the version **on every push to main**, in three places:

| File | What |
| --- | --- |
| `pubspec.yaml` | `version: 0.32.2+41` (name + build number) |
| `lib/app/version.dart` | `augustVersion` |
| `test/settings_test.dart` | The expected "Version 0.32.2 · licences, developer" |

`test/version_test.dart` checks that they agree.

**Only arm64** (`arm64-v8a`) is built and released: 64-bit ARM phones. 32-bit phones and x86 emulators get no APK, and the updater offers them nothing.

**versionCodes:** the build keeps `--split-per-abi` (with `--target-platform android-arm64`) because it adds 2000 to the build number for arm64, so build 41 becomes **2041**. Don't drop the flag: the versionCode would fall to 41, below every installed copy, and no phone would take the update.

CI **fails on purpose** if the arm64 versionCode isn't above the last release's, because a release no phone can install would sit there as "latest" and offer nothing.

**Commits** are in Cariño style: a sentence-case subject with the version (`Fix X (0.32.2)`), and a body saying what changed and why. Commit subjects since the last release become the update's "What's new".

## The release workflow

`.github/workflows/release.yml`: on push to `main`, in the GitHub environment `deployment`, with a 45-minute limit. A newer push cancels a running one.

```mermaid
flowchart TB
  A[Checkout, Java 17, Flutter 3.47.9] --> B[Read version from pubspec]
  B --> C[Decode keystore from secret]
  C --> D[flutter test]
  D --> E[Write env.json from secrets with jq]
  E --> F[Fetch Gradle via aria2 mirrors<br/>and lower Gradle's heap]
  F --> G[flutter build apk --release --split-per-abi<br/>--flavor prod --target-platform android-arm64<br/>retried up to 3 times]
  G --> H{Signed with the<br/>debug key?}
  H -- yes --> X[Fail]
  H -- no --> I[Write update.json:<br/>URL, size, SHA-256, versionCode for arm64]
  I --> J{arm64 versionCode<br/>went up?}
  J -- no --> X
  J -- yes --> K[Remove keystore and env.json]
  K --> L["Release 'August X'<br/>tag v&lt;ver&gt;-&lt;sha&gt;, make_latest"]
```

- **Gradle memory** is turned down for the runner: the old 8 GB heap made it lose contact and die.
- **Gradle itself** is fetched with aria2 from mirrors, because the default download timed out on cold caches.
- There's **no AppImage or Linux release**; the Linux build is for development.

### Secrets (environment `deployment`)

| Secret | For |
| --- | --- |
| `AUGUST_KEYSTORE_BASE64` | The release keystore, base64 |
| `AUGUST_KEYSTORE_PASSWORD`, `AUGUST_KEY_PASSWORD` | Its passwords |
| `AUGUST_KEY_ALIAS` | `upload` |
| `AUGUST_API_URL`, `AUGUST_AUTH_URL` | The Neon Function and Managed Auth |
| `AUGUST_KLIPY_KEY` | KLIPY GIFs (optional) |

`android/app/build.gradle.kts` reads the `AUGUST_KEYSTORE_*` and `AUGUST_KEY_*` variables, and falls back to the debug key when they're missing, so local debug builds still work.

### The release key

Releases from **0.31.0** onward are signed with the release key, which lives outside the repo. Android only installs an update signed by the same key, so:

- **Never lose it.** Without it, every user would have to uninstall (losing their chats) to move to a new key.
- A phone with a release-signed install can't take a debug-signed build over it without wiping its data. To test locally, build release-signed too (see [Development](development.md#on-the-phone)).

## `update.json`

Published with every release, at `https://github.com/rd6260/august/releases/latest/download/update.json`:

```json
{
  "version": "0.32.2",
  "build": 41,
  "published": "2026-11-14T…Z",
  "notes": ["Keep covered setup steps alive, so a scanned QR pairs", "…"],
  "apks": {
    "arm64-v8a": {"url": "https://github.com/rd6260/august/releases/download/v0.32.2-63a4ad8/app-arm64-v8a-release.apk",
                  "sha256": "…", "size": 0, "versionCode": 2041}
  }
}
```

The versionCode is read from the APK with `aapt2 dump badging`, not computed.

## Over-the-air updates

`lib/net/updater.dart` (Dart), `lib/platform/updater_channel.dart` and `android/…/Updater.kt` (Kotlin).

```mermaid
stateDiagram-v2
  [*] --> Checking: launch / resume after 6 h / Settings
  Checking --> UpToDate
  Checking --> Available: newer versionCode for this ABI
  Available --> Downloading: Update
  Downloading --> Downloading: resume with Range
  Downloading --> Verifying
  Verifying --> Failed: size / SHA-256 / signer mismatch
  Verifying --> Ready
  Ready --> Installing: Install
  Installing --> [*]: PackageInstaller session
```

1. **Check:** read `update.json` (a build can point elsewhere with `--dart-define=AUGUST_UPDATE_URL=…`), pick this phone's ABI, and compare versionCodes. This runs at launch, on resume if 6 hours have passed, and from Settings › Check for updates.
2. **Prompt:** a card in Chat (dismissed per version) and a row in Settings both open the update sheet.
3. **Download:** with progress, following redirects by hand and **resuming with Range headers** after a drop.
4. **Verify:** the size and SHA-256 must match `update.json`, the APK's **signer must match the installed app** (`sameSigner`), and its versionCode must be higher.
5. **Install:** the first time, Android asks to allow "Install unknown apps" for August. Then a **PackageInstaller session** installs it. After the first self-install, Android skips its own confirm screen.
6. **After:** `UpdatedReceiver` posts a quiet "August updated to X" notification, and "What's new" shows once on the next launch.

**Google Play Protect** may still show "App scan recommended" for each new APK. That's Play Protect's decision about apps from outside the Play Store; the user taps Scan app.

### Testing an update locally

```bash
# A Range-capable static server with update.json and the APK in it
python3 -m http.server 8765        # or any server that supports Range
adb reverse tcp:8765 tcp:8765
flutter build apk --release --split-per-abi --flavor prod --target-platform android-arm64 \
  --dart-define-from-file=env.json --dart-define=AUGUST_UPDATE_URL=http://127.0.0.1:8765/update.json
```

Install an older build with that define, put a newer APK and its `update.json` on the server, then use Settings › Check for updates. Python's built-in `http.server` doesn't support Range, so use a small Range-capable one to test resuming.
