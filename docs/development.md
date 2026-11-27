# Development

## Requirements

| Tool | Version | For |
| --- | --- | --- |
| Flutter | 3.47.9 (stable), Dart ^3.13 | The app |
| Android SDK, Java 17 | | Android builds |
| `clang`, `cmake`, `ninja`, GTK 3, `libmpv` | | The Linux build (media_kit plays audio and video through libmpv) |
| Node.js 22+ and the `neon` CLI | | The backend in `backend/` |
| Python 3 | | The e2e partner (`tool/partner`), the icon and design renders |
| Playwright's headless Chromium | | `tool/design_render/render.sh` |
| ImageMagick | | `tool/docs_renders.sh` |

## Mock mode

```bash
flutter pub get
flutter run
```

Without `env.json`, every repository is a mock (`lib/mock/`). The pretend partner, Aatika:

- answers your texts with a typing indicator and a reply;
- sends your moments back as bursts;
- answers calls after 3 seconds, and calls back if you write "call me";
- sends a re-pair request if you write "new phone".

On the mock, PIN `1402` opens August and `2580` opens the decoy chat. Invite `K7Q2MX` joins, `R3PA1R` plays the new-phone wait, and any other code has expired. All of this is listed in [`mockdata.md`](../mockdata.md).

## Real mode (Neon)

1. Set up the backend (see [`backend/README.md`](../backend/README.md)) and deploy it.
2. Copy `env.example.json` to `env.json` (git-ignored) and fill it in:

   ```json
   {
     "AUGUST_API_URL": "https://<branch-id>-api.compute.<region>.aws.neon.tech",
     "AUGUST_AUTH_URL": "https://<endpoint>.neonauth.<region>.aws.neon.tech/neondb/auth",
     "AUGUST_KLIPY_KEY": "<optional>"
   }
   ```

3. Build with it: `flutter run --flavor dev --dart-define-from-file=env.json` on Android (see [On the phone](#on-the-phone)), or without `--flavor` on Linux.

Other build-time defines:

| Define | Default | Does |
| --- | --- | --- |
| `AUGUST_UPDATE_URL` | The latest GitHub release's `update.json` | Where the updater looks |
| `AUGUST_CHECK_EVERY` | 480 (seconds) | The background check's interval |

### Firebase

Push needs `android/app/google-services.json` (committed; the client key is public by design) and, on the server, a service-account key at `backend/firebase-sa.json` (git-ignored). `npm run deploy` passes it to the Function as `FIREBASE_SA_B64`. Without Firebase, August still works: it just can't be woken, and relies on the live socket and the background check.

## On the phone

Android builds have two flavors with **one app ID** (`com.rd6260.august`), so only one is installed at a time. Every Android build names one:

| | `--flavor prod` | `--flavor dev` |
| --- | --- | --- |
| Who | CI and GitHub releases | Local builds while developing |
| Label | August | August Dev |
| Data | The app's private folder; secrets in the Keystore | The phone's own storage: `August/profiles/<profile>/` at the top of Internal storage, secrets in a plain `vault.json` beside the data |
| Survives an uninstall | No: uninstalling wipes the identity and the chat | **Yes**: a reinstall finds the same identity, pairing and history |
| Profiles | One | Several (Settings › Developer › Profile), each with its own account, identity, pairing and chat |
| In-app updates | From GitHub releases | Off (a release would replace it with a build that can't see its data) |

### Dev builds

```bash
flutter run --flavor dev --dart-define-from-file=env.json --android-skip-build-dependency-validation
```

- **Hot reload, any signing key:** if Android refuses the install (a different key, a lower version), `flutter run` uninstalls and reinstalls. That's fine in dev: the data is in phone storage, not the app.
- **"All files access":** dev asks for it at start, and again after every reinstall (Android drops it on uninstall). Until it's on, August shows a screen with **Open settings**.
- **Profiles:** each is a folder under `August/profiles/`, and `August/current.json` names the one in use. A new profile starts at Welcome, so it can pair with someone else (a second phone, the Linux build, `tool/partner/`, or another profile on the same phone: make a code, switch, join). Switching restarts August. Only the current profile is checked in the background and woken by pushes.
- **Not private:** any app with storage access can read `August/`. Dev only; prod never uses it.
- **Back it up** now and then: `adb pull /storage/emulated/0/August`.

### Moving from prod to dev

The first dev run moves a prod install's chat, media and secrets into the profile **Main** (and points stored media paths at the new folder). That only works if the dev build installs **over** prod without an uninstall, so make that first one with the release key:

```bash
. ~/.android/august-release.env   # the AUGUST_KEYSTORE_* variables
flutter run --release --flavor dev --dart-define-from-file=env.json --android-skip-build-dependency-validation
```

### Prod builds by hand

```bash
. ~/.android/august-release.env
flutter build apk --release --split-per-abi --flavor prod --target-platform android-arm64 --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-prod-release.apk
```

- `adb install -r` keeps the app's data. **Never `flutter install`**: it uninstalls first.
- Without the `AUGUST_*` signing variables, Gradle signs with the debug key, which can't be installed over a release-key install.
- Screenshots: `adb exec-out screencap -p > shot.png`.

## On Linux

The Linux build is a full second device: the same pairing and chat, against the same backend.

```bash
flutter build linux --debug --dart-define-from-file=env.json
build/linux/x64/debug/bundle/august
```

| | Linux |
| --- | --- |
| App data | `~/.local/share/com.rd6260.august/` (`moose.json`, `vault.json`) |
| Cache | `~/.cache/com.rd6260.august/` |
| Secrets | `FileVault`: a private `vault.json`, because the desktop keyring isn't always reachable |
| Audio and video | media_kit (libmpv) |
| Not available | Push (no FCM on Linux), the background check, round video recording, ML Kit cut-outs, the camera QR scanner (type the code instead), and self-update. Share on the pair screen copies the code instead |

## Conventions

- **Cupertino only:** `CupertinoApp` and go_router, with `uses-material-design: false`. Don't import `package:flutter/material.dart`.
- **Colours only through `VColors`:** `test/design/no_banned_colors_test.dart` fails on any `Color(…)` outside `lib/core/theme/v_colors.dart`.
- **Text through `VText`:** Doto for titles and numbers, Inter for everything else. Colour comes from the surrounding `DefaultTextStyle`, which is how inversion works.
- **Blur in three places only:** the shell's edge blur, the tab pill, and behind a moment burst. Never put a blur inside an `Opacity` or a fade; animate the sigma instead.
- **Lists:** `GridView` and `ListView` need `padding: EdgeInsets.zero`, or they take the status-bar inset as a gap.
- **Covered pages stay mounted:** during a transition the old page goes to opacity 0; it's never swapped for a placeholder.
- **No stand-ins:** a value drawn straight into a widget (a progress bar, a time) goes in [`mockdata.md`](../mockdata.md) until it follows real data.
- **Both inks:** check every screen on a dark and a light wallpaper.
- **Comments say why**, in plain sentences, and doc comments reference the screen codes from `design/SCREENS.md`.

## Tests

```bash
flutter analyze        # must be clean
flutter test           # about 300 tests
```

| Suite | Covers |
| --- | --- |
| `test/*_test.dart` | Widget tests for every area on the mocks: chat, composer and keyboard, media, voice, stickers and music, doodles, calls, onboarding and QR, settings, the shell, step transitions, the update UI and the crash overlay |
| `test/net/` | Crypto (sealing, the security code), the wire format, local persistence, auth, push descriptions and the updater (manifest, ABI, verification) |
| `test/design/` | The banned-colour check |
| `test/neon/` | Live tests against a deployed branch. **Skipped** unless the Neon env is set |
| `integration_test/` | On a device: the app, focus, look, Neon, QR scanning and round video |
| `backend/test/e2e.ts` | The API end to end (`npm test` in `backend/`) |

Notes:

- `test/flutter_test_config.dart` loads the real fonts, so text measures the same as on the phone.
- `test/data_test.dart` "Aatika types and then replies" is timing-sensitive and can fail under load; rerun it.

### End to end with a real phone

```bash
tool/e2e_neon.sh     # needs env.json, backend/.env.local and a phone on adb
```

August runs on the phone, and Aatika is emulated in Python on this computer (`tool/partner/partner.py`, with `calls.py` using aiortc for WebRTC, in the venv at `tool/partner/.venv`). They meet only through the deployed backend. The phone's screen has to stay on for the whole run. Afterwards, `npm run cleanup` in `backend/` deletes the `e2e-…` test accounts.

## Renders

Two kinds of picture are committed:

| What | Source | Regenerate |
| --- | --- | --- |
| **App renders** (`docs/renders/*.webp`) | The real widgets on the mock data, drawn by the local peek harness in `test_peek/` (git-ignored) at 390 × 844, on the night and paper wallpapers | `tool/docs_renders.sh` (`--keep` to only convert) |
| **Design boards** (`design/screens/*.png`) | The design canvas, `design/canvas/*.dc.html` | `tool/design_render/render.sh` |

The peek harness loads Doto and Inter from `assets/fonts`, Noto Color Emoji and Noto Sans Mono from the system (`VText.fallback`), and fakes the status and gesture bars as both `padding` and `viewPadding`, as a phone reports them.

## Tools

| Path | Does |
| --- | --- |
| `tool/e2e_neon.sh` | The end-to-end journey against Neon with the Python partner |
| `tool/partner/` | The emulated partner: `partner.py` (pairing, mail, crypto) and `calls.py` (aiortc) |
| `tool/docs_renders.sh` | Refreshes `docs/renders/` |
| `tool/design_render/` | Renders the design canvas with headless Chromium and `dc-mini.js` |
| `tool/icon/make_icon.py` | Draws the launcher icon |
| `backend/scripts/` | `migrate.ts`, `cleanup.ts`, and `push-check.ts` (who has a push token; send a test push) |
