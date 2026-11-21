# Phoenix Portal: hybrid plan (Kiosk Satellite base + Immortal parts)

**Decision:** Phoenix Portal is this Kiosk Satellite fork. It is the **one app** that runs on
each Portal: home screen, HA dashboard, voice, screensavers and kids mode. The Immortal fork
([rayalavcp/phoenix-portal](https://github.com/rayalavcp/phoenix-portal), branch
`phoenix-portal`, see its `docs/phoenix/REVIEW.md`) is a **parts donor**: its Portal-specific
pieces move here, and the two apps are never installed together.

Why not both side by side: they would compete for the home screen, the screensaver and Meta's
presence sensor, and Home Assistant would see every Portal twice (Immortal over MQTT, Kiosk
Satellite over ESPHome).

## What comes from Immortal

| Immortal piece | Destination in Phoenix |
|---|---|
| Provisioning kit: one-click setup and restore, Gen-1 installer-overlay fix, OTA block, package verifier, Shizuku | **Phoenix Control**: a WebUSB/ADB web app, set up for this app's permission list (see `docs/portal.md`) |
| App Store catalog (`catalog.json`, F-Droid / GitHub resolution) | A "Store" tab in the App Launcher (this app already has `ApkInstaller`) |
| Launcher grid with folders | App Launcher + the new Kids home |
| Portal TV D-pad navigation | Check `key_nav.dart` on a Portal TV; port only the gaps |
| Bedtime stories, lamp | Kids activities |

**Not ported** (this app has better versions): MQTT, the screensaver, multi-room audio,
intercom, RTSP, the fleet agent.

## Order of work

1. **Base builds and runs on Android 9.** Upstream was only verified on a Portal Go
   (Android 10).
2. **Fork hygiene** (branch `phoenix-portal`). Done in this branch:
   - Application id `com.phoenix.portal`; launcher label "Phoenix Portal". The Kotlin namespace
     stays `me.jxl.kiosk_satellite`, so component names are written in full
     (`com.phoenix.portal/me.jxl.kiosk_satellite.KioskAccessibilityService`).
   - The update helper's package and provider authority now follow the application id.
   - The Shizuku grant plan writes fully qualified component names. The old
     `pkg/.Class` form would have resolved to a non-existent class after the rename.
   - Self-update, the release-tag fallback check, About links, the DLNA manufacturer URL and
     the user agent point at `rayalavcp/phx-kiosk-satellite` / `PhoenixPortal`.
   - Analytics (basic, usage, diagnostics) **default to off**.
   - The release workflow no longer fails without the Ground Control key (Voice Match sign-in
     is optional).
   - **Still to do:** your own signing keystore + repository secrets
     (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
     `ANDROID_KEY_ALIAS`).
   - **English only:** the seven translation catalogs were removed through
     `tool/localization.py`; language-specific tests are skipped with a reason.
   - **In-app text says "Phoenix Portal"** everywhere (app, web admin, Android strings, docs).
     English text doubles as the lookup key for IDs, so it was replaced consistently across
     sources, generated catalogs and tests, then regenerated. Licence, credits and changelog
     keep the upstream name for attribution.
3. **Real-Portal validation** (needs your hardware): renderer, mic and wake word, camera,
   presence (`READ_LOGS`), home launcher, store installs over Wi-Fi.
4. **Phoenix Control: done.** `control/`: WebUSB setup with the full command list before
   anything runs, live per-step results, restore, profile switch, screenshot; `?demo` mode;
   published by `.github/workflows/control-pages.yml`.
5. **Immortal pieces: done.**
   - `provisioning/phoenix-provision.sh`: setup / restore / status with the Gen-1 overlay
     fix, verifier, OTA block and stock-launcher snapshot. Verified on the Android 9 emulator.
   - App Store: 17 free apps verified on F-Droid, installed through Android's installer.
   - Immortal's security findings were not carried over.
6. **Kids Portal: done**, aimed at a 9-year-old:
   - Math Blitz, Word Scramble, 2048, Connect Four vs computer, Memory Pro, Draw Studio, with
     best scores and daily stars.
   - Daily screen time (default 1.5 h), bedtime, parent PIN or three-second hold, the
     parent-approved apps.
   - Family / Kids / Night profile; Home Assistant `Profile` select and `Kids time left`
     sensor.
7. **Polish and debloat: done.**
   - Phoenix design system (ember on ink, Inter, dark default, one smooth page transition,
     cheap ripples for old GPUs) and the new phoenix logo and launcher icon.
   - English only (seven translation catalogs removed).
   - Release builds drop x86_64 libraries.
   - Further option, not taken: drop MediaPipe (hand gestures, about 22 MB on arm64).
8. **Immortal fork:** kept as the `legacy-immortal` branch of
   [rayalavcp/phoenix-portal](https://github.com/rayalavcp/phoenix-portal); that repository's
   `main` now carries Phoenix Portal.
