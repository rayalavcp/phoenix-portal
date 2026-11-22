# Phoenix Portal: agent hand-off

Read this first. It is the state of the project for the next agent (cloud or
local): what it is, where things live, how to build and ship, and what is
still open.

## What it is

Phoenix Portal is a home-hub app for **Meta Portal** devices (Android 9/10,
armeabi-v7a), built on Kiosk Satellite. It is the Portal's home screen:
a launcher (Phoenix Home) with a Today screen, a Kids Portal, school menus
and calendar, a Telugu calendar, photos, live Home Assistant cameras and
remote administration. Home Assistant is optional.

- Owner: krayala, GitHub `rayalavcp`. Repository `rayalavcp/phoenix-portal`.
- Working branch: **`claude/fervent-hopper-25a7jk`** (everything ships from it).
- Current build: see `install/README.md` (version and SHA-256) and
  `install/releases.json`.

## Rules the owner set

- **Nothing may be sent to the original project.** No analytics (the endpoint
  is empty), plugin directory and update checks use this repository, guide
  links open this repository's `docs/`. Keep it that way.
- **Keep the licence credit.** The original is CC BY-NC-ND 4.0: the About
  page's "Based on Kiosk Satellite by Xavier Larrea" and its licence link stay.
  Do not relicense or remove the notice. The Voice Satellite card integration
  link (a separate project) and translator credits stay too.
- Author shown in the app: **krayala**, linking to github.com/rayalavcp.
- Ask before uninstalling, disabling or deleting anything on the device.
- Default school: **Miller Elementary, Frisco ISD**.
- India map: India's official boundaries (Ladakh and Jammu and Kashmir as
  union territories, the whole of Jammu, Kashmir and Ladakh shown); the
  world map uses Natural Earth's India point of view to match. Keep the
  DataMeet credit (CC BY 4.0) shown under the map.
- Kids Portal look: **calm** (blurred photo backgrounds, frosted glass), big
  readable text. Do not bring back loud gradients.
- Wallpapers: real 4K photos (Wikimedia Commons, credited in
  `wallpapers/CREDITS.md`); the owner may upload their own.
- Do not recreate copyrighted game characters (the Space Blaster enemies are
  original saucers on purpose; the Arcade games use original characters).

## Layout

| Path | What |
|---|---|
| `app/` | The Flutter app (`app/lib`, tests in `app/test`). |
| `app/remote-ui/` | The remote admin (plain JS). Build: `cd app/remote-ui && npm run build` (copies into `app/assets/remote-ui`). |
| `app/android/app/src/main/kotlin/me/jxl/kiosk_satellite/` | Native code (camera, hand/face tracking, SoundPool instrument, installer bridges). |
| `app/l10n/` | Strings. After editing `l10n/source/*.arb`: `python3 tool/localization.py generate` then `flutter gen-l10n`. |
| `install/` | What ships: `phoenix-portal.apk`, `releases.json`, `install-phoenix.ps1`, `README.md`, `LOCAL_AGENT.md`, `UPDATES.md`, `make_releases.py`. |
| `wallpapers/` | 4K photos the Portal downloads on first use (kept out of the APK for GitHub's 100 MB limit). |
| `plugins/index.json` | The plugin directory list (empty). |
| `docs/` | User guides; the app's "Open guide" buttons link here. |

### Where the features live (app/lib)

| Feature | Files |
|---|---|
| Phoenix Home manager (weather, apps, tiles, wallpapers, glass, cameras, doorbell, Smart Home target, kids settings, remote `phoenixHomeGet/Set`) | `managers/home/phoenix_home_manager.dart` |
| Today screen (default home) | `ui/home/today_home.dart`, `ui/home/home_glass.dart`, `ui/home/live_cameras.dart` |
| Tile layout | `ui/home/home_tiles.dart`, `ui/home/phoenix_home.dart` |
| Weather effects | `ui/home/weather_backdrop.dart` |
| School (SchoolCafe menus, iCal or HA calendar) | `managers/home/school_service.dart`, `ui/home/school_page.dart` |
| Telugu calendar (panchangam), word of the day | `managers/home/panchang.dart`, `managers/home/telugu_words.dart`, `ui/home/telugu_calendar_page.dart` |
| Photos (Immich / folder), photo frame | `managers/home/photo_service.dart`, `ui/home/photo_frame.dart` |
| Kids Portal hub and frame | `ui/kids/kids_overlay.dart`, `ui/kids/kids_activities.dart` |
| Kids games | `kids_learn.dart` (quizzes), `kids_games.dart`, `kids_puzzles.dart`, `kids_play.dart` (incl. piano), `kids_motion.dart` (camera games), `kids_arcade.dart` (Munch Maze, Brick Bash), `kids_arcade2.dart` (Hop Across, Sky Glide, Fox Run), `kids_motion2.dart` (Wall Dodge, Air Trace, Freeze Dance), `kids_learn_more.dart` (Count It, Letter Sounds, Place Value, Story Sums, Telugu Words), `kids_maps.dart` (USA, India, World maps; data in `assets/maps`, rebuilt with `tool/kids_maps`) |
| Hand/head tracking for games | native `HandTracker.kt`, `FaceDetector.kt`, `CameraMotion.kt`; Dart `managers/motion/motion_manager.dart` (`startHandTest`, `startHeadTracking`) |
| Updates from GitHub | `managers/update/update_manager.dart` (`_releasesUrl` = this repo's `install/releases.json`) |
| Admin Phoenix Home page | `remote-ui/static/phoenix_home.js` (+ CSS in `app.css`, `#tab-phoenix`) |

## Building (cloud container)

Flutter and the Android SDK live in the session scratchpad (not in git).
The build script used:

```bash
cd app && flutter build apk --release --split-per-abi --target-platform android-arm
# output: build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

The APK is debug-signed with the same key every time (certificate SHA-256
starts `47fff989d4`), so builds install over each other and keep settings.
Keep the APK under 100 MB (GitHub's file limit, 104,857,600 bytes; 2026.12.8 is
100,243,502, so about 4.6 MB of room is left): large assets go in
`wallpapers/` and download at run time.

Before shipping, run the analyzer and the tests that cover what changed.
`test/kids_all_games_test.dart` opens every Kids game at 1280×800,
800×1280 and 1024×600 and plays it a little: add new games to it.

```bash
cd app && flutter analyze lib test
flutter test test/<area>_test.dart
for t in test/*.mjs; do node --test "$t"; done   # admin JS tests
```

`settings_search_navigation_test.dart` crashes flutter_tester (a known,
pre-existing problem); it passes on its own.

## Shipping a build

1. Give it a **new version name** in `app/pubspec.yaml` (e.g.
   `2026.12.9+384`). The Portal's update check compares names.
2. Build, then check: version, signing key, size under 100 MB.
3. Copy to `install/phoenix-portal.apk`.
4. `python3 install/make_releases.py <version> "notes"` writes
   `install/releases.json`.
5. Update `$Version`, `$ApkSize`, `$ApkSha256` in `install/install-phoenix.ps1`
   and the size/SHA in `install/README.md`.
6. Commit and push to `claude/fervent-hopper-25a7jk`.

Portals on **2026.12.3 or newer** then find it themselves (on start and every
12 hours; admin Dashboard › Check for updates checks now) and show
"Update available" in the menu. Older Portals need the PC installer
(`install/LOCAL_AGENT.md`).

## Device facts

- Portal at `10.10.1.206`; remote admin `http://10.10.1.206:2324`.
- Package `com.phoenix.portal`. Installed from a Windows PC over USB by a
  local agent using `install/install-phoenix.ps1`.
- The installer also sets Phoenix as the home screen, turns on start on boot,
  and offers to stop other apps (e.g. Portal HA Bridge) opening at boot.

## Verified vs not yet verified on a real Portal

Verified here (tests, real admin server in Chromium, real SchoolCafe and
Frisco ISD calendar data): admin portal end to end, school menus and
calendar parsing, Kids Portal layouts at 1280x800 / 800x1280 / 1024x600,
games by touch, wallpaper and weather rendering, update list format.

Not yet seen on a device:
- A Portal updating itself from GitHub (first chance: 2026.12.3 or later
  updating to a newer build).
- Live HA camera video in the Today card and the doorbell alert (no Home
  Assistant here). The settings and the "no camera" path are tested.
- Hand and head tracking in the Move games (direction may need the in-game
  ↔ swap; the camera must be on in camera settings).
- The piano's sound on the device (SoundPool) and the synthesized tone.
- Whether the HA Bridge app still takes over after a reboot once the
  installer has stopped its boot start.

## Open ideas the owner mentioned

- More motion games; owner will upload wallpapers.
- Bell times for Miller Elementary are not set (unknown).
