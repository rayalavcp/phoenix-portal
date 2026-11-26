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
     the user agent point at `rayalavcp/phoenix-portal` / `PhoenixPortal`.
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
6. **Kids Portal: done**, aimed at primary-school children:
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
9. **Launcher first, Home Assistant as an add-on: done.**
   - **Phoenix Home** (`lib/ui/home/`, `lib/managers/home/phoenix_home_manager.dart`) is the
     default home screen (`home.screen`: `phoenix`, or `dashboard` for the old full-screen
     dashboard). It sits over the dashboard's slot, so Home Assistant's offline cover never shows
     unless the dashboard is opened, and the dashboard page is only loaded while it is open
     (`dashboardPageNeeded`).
   - Weather from Open-Meteo by city (`home.weather_city`) or the tablet's location; °F or °C.
   - App drawer with search, recent and most-used apps; long press pins to the dock, adds to the
     Kids Portal, hides, or opens Android's app info. Every installed app is shown; the old
     whitelist launcher remains for a locked kiosk.
   - Smart Home page: quick controls over `haListEntities` / `haCallService`, pinned favourites,
     rooms, and "Open dashboard".
   - School page (`school_service.dart`): Nutrislice menus (the district and school
     picked from the district's list), an iCal calendar link, bell times.
   - The setup wizards (device and remote) can skip Home Assistant (`home.setup_done`).
10. **Kids Portal, second shelf: done.** Times Tables, Telling the Time, Flag Quiz, Patterns,
    Sudoku, Maze, Word Search, Word Guess, Snake, Simon Says, Tic-Tac-Toe, Pixel Paint and Piano
    (tones synthesized to WAV and played by the native player), grouped as Learn / Puzzles / Play /
    Create, plus a daily challenge worth three stars. Rules in `kids_more_logic.dart`, tested in
    `test/kids_more_logic_test.dart`.
11. **Home, round two: done.** Live tiles with any size (`home_tiles.dart`, `packTiles`), six
    themes, a weather backdrop, the Telugu calendar (`panchang.dart`: Meeus Sun and Moon, Lahiri
    ayanamsa, festivals by masa and tithi at local sunrise, tested against 2026's dates), photos
    from Immich or an http folder with the Phoenix Photo Frame screensaver (`photo_service.dart`),
    the school's month calendar with menus and events, and Kids Portal levels plus Fractions, Money,
    Science, Spelling, Opposites, Whack-a-Mole and Lights Out.
12. **Today home and school, round three: done.** A Today screen with 4K
    wallpapers, glass cards, weather effects, live Home Assistant cameras and
    a doorbell alert; SchoolCafe menus and the district
    calendar; updates from this repository (GitHub Releases since 2026.12.14).
13. **Kids Portal, round three: done.** Calm redesign; Arcade (Munch Maze,
    Brick Bash, Hop Across, Sky Glide, Fox Run); Move camera games; Maps
    (USA, India, World); five more learning games; quiz levels with stars
    and Next level; Snake stages and Memory sizes.
14. **Camera games, low lag: done.** A native game mode (`GameVision.kt`),
    two hands, friendly bubble cursors (2026.12.14; the glow renders were removed); Freeze Dance DJ mixes of
    public-domain songs (`kids_dj.dart`).
15. **Replacing Immortal:** a Calls button on the Today dock (the stock
    Portal home's calling screen). What is still missing and how to remove
    Immortal safely: `docs/phoenix/IMMORTAL.md`.
16. **Round four: done (2026.12.13 to 2026.12.20).** Review and security
    pass; builds as GitHub Releases and an APK-free history; widget-style
    tiles on several home screens; the sun's path; Kids leaderboards and new
    puzzles every game; shopping list, quick timers, wallpaper colours; a
    calmer look everywhere; the scenic photo frame; `main` as the only
    working branch; README, wiki (`docs/wiki`) and mock screenshots.
