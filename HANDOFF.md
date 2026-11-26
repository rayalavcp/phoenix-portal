# Phoenix Portal: agent hand-off

Read this first. It is the state of the project for the next agent (Cursor,
cloud or local): what it is, where things live, how to build and ship, and
what is still open.

## Start here (updated 2026-11-26)

- **Latest release: 2026.12.20 (versionCode 395)**, published as GitHub
  Release `v2026.12.20` from `main`. It is the first build that needs
  nothing from `claude/fervent-hopper-25a7jk` (guides, licence, plugin list
  and wallpapers all come from `main`).
- **Work on `main`.** On 2026-11-25 everything was merged into `main`
  (fast-forward; `main` is the default branch to clone).
- **The old branch `claude/fervent-hopper-25a7jk` was deleted on the
  owner's request (2026-11-25).** Builds up to 2026.12.19 opened their
  guides, licence link and plugin list from it; on those builds only those
  links fail until the Portal updates to 2026.12.20 or newer (updates and
  wallpapers keep working). Everything now lives on `main`.
- **Signing key (critical).** Every build is signed with one key
  (certificate SHA-256 `47:FF:F9:89:D4:2A:FD:80:...:04:2B`). A build signed
  with any other key will not install over the app on the Portals (Android
  refuses; the only way round is uninstalling, which wipes the Portal's
  settings). The owner has the key file (`phoenix-signing.jks`, given to them
  at hand-over, NOT in git). Put it at `app/android/phoenix-signing.jks` and
  create `app/android/key.properties` (both git-ignored):

  ```properties
  storeFile=../phoenix-signing.jks
  storePassword=android
  keyAlias=androiddebugkey
  keyPassword=android
  ```

  (It is an Android debug-type key with the standard passwords.) Check every
  build: `apksigner verify --print-certs <apk>` must show `47fff989d4...`.
  Never commit the key or key.properties (`.gitignore` blocks `*.jks` and
  `key.properties`).
- **Toolchain used:** Flutter 3.44.6 stable (Dart ^3.12), Android SDK
  platform 36 / build-tools 36.0.0, Java 21, Node 22 (remote admin build and
  JS tests).
- **Owner's latest asks, all done:** README, wiki and docs with new mock
  screenshots (2026-11-26, see "Docs, wiki and screenshots"); scenic photo
  frame and everything on `main` (2026.12.20); calmer UI everywhere
  (2026.12.19); leaderboards, shopping list, quick timers, wallpaper colours,
  home screens, random mazes (2026.12.18). Decisions still waiting for the
  owner are under "Open decisions" below.
- **The owner deletes `claude/fervent-hopper-25a7jk` themselves** (the cloud
  agent's git access could not delete branches). If it is still there, it
  is an old copy of `main`: do not work on it.

### Open decisions (ask the owner first)

1. Delete the old `test-build` branch on GitHub: it holds the last APK in
   the repository (about 90 MB).
2. Rewrite the working branch's history once more to drop about 32 MB of
   files deleted since (original project screenshots and GIFs): a fresh
   clone would go from 96 MB to about 60 MB. Needs a force push.
3. Remove the unused body segmenter from `GameVision.kt` and its model
   `selfie_segmenter.tflite` (about 250 KB).
4. Google Home Mini "pucks" as intercom targets: one-way announcements to
   Home Assistant media players (Google Cast) from the Portal broadcast was
   offered; the owner has not said yes. Two-way is impossible (Google locks
   the mic).
5. CC BY-NC-ND's NoDerivatives term and public release downloads: flagged to
   the owner (keep the repo private or ask Xavier Larrea); not resolved.
6. Publish the wiki: the GitHub wiki was not reachable from the cloud
   agent. Run `docs/wiki/publish-wiki.sh` (create the wiki's first page on
   GitHub once if it is empty).

### Known flaky or failing tests (not caused by recent work)

- `test/settings_search_navigation_test.dart`: the 1200 px case does not
  complete when run after the 600 px case in the same file; passes alone.
  Pre-existing.
- Under full parallel runs only, now and then: `isolate_engine_test`,
  `dlna_port_test`, `immich_cache_clear_test` (all pass on rerun).
- The Today screen at 1024x600 overflows by 13 px on a frame shortly after
  it first lays out (a widget that is disposed right after; seen with the
  Telugu calendar on). Pre-existing; every Portal is 1280x800 or larger, but
  worth fixing. `phoenix_home_test.dart` skips the Telugu toggle there.
- `test/logs_about_localization_ui_test.py` needs Python Playwright (not
  installed in the cloud container; never run there recently).

## What it is

Phoenix Portal is a home-hub app for **Meta Portal** devices (Android 9/10,
armeabi-v7a), built on Kiosk Satellite. It is the Portal's home screen:
a launcher (Phoenix Home) with a Today screen (with a **Calls** button into
the Portal's own calling), a Kids Portal (more than 50 games: learning,
maps, puzzles, arcade, camera games, create), school menus and calendar, a
Telugu calendar, photos, live Home Assistant cameras and remote
administration. Home Assistant is optional. It replaces **Immortal**
(see `docs/phoenix/IMMORTAL.md` for what is and isn't covered, and how to
remove it safely).

- Owner: krayala, GitHub `rayalavcp`. Repository `rayalavcp/phoenix-portal`.
- Working branch: **`main`**.
- Current build: see `install/README.md` (version and SHA-256) and the
  repository's GitHub Releases (`v<version>`).

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
- **No personal data in the repository.** It is public: no school, city,
  district, IP address, names or photos from the owner's home in code
  defaults, tests, docs or screenshots. The school has no default (set it on
  the Portal), the Telugu calendar is an option (off on new installs, kept on
  for installs that already had Phoenix settings), and screenshots use mock
  data only.
- India map: India's official boundaries (Ladakh and Jammu and Kashmir as
  union territories, the whole of Jammu, Kashmir and Ladakh shown); the
  world map uses Natural Earth's India point of view to match. Keep the
  DataMeet credit (CC BY 4.0) shown under the map.
- Kids Portal look: **calm** (blurred photo backgrounds, frosted glass), big
  readable text. Do not bring back loud gradients.
- Wallpapers: real 4K photos (Wikimedia Commons, credited in
  `wallpapers/CREDITS.md`); the owner may upload their own.
- Freeze Dance music: only public-domain tunes, remixed on the device
  (`kids_dj.dart`). Real chart songs cannot be bundled (copyright).
- Do not recreate copyrighted game characters (the Space Blaster enemies are
  original saucers on purpose; the Arcade games use original characters).

## Layout

| Path | What |
|---|---|
| `app/` | The Flutter app (`app/lib`, tests in `app/test`). |
| `app/remote-ui/` | The remote admin (plain JS). Build: `cd app/remote-ui && npm run build` (copies into `app/assets/remote-ui`). |
| `app/android/app/src/main/kotlin/me/jxl/kiosk_satellite/` | Native code (camera, hand/face tracking, SoundPool instrument, installer bridges). |
| `app/l10n/` | Strings. After editing `l10n/source/*.arb`: `python3 tool/localization.py generate` then `flutter gen-l10n`. |
| `install/` | `releases.json` (for builds older than 2026.12.14), `install-phoenix.ps1`, `README.md`, `LOCAL_AGENT.md`, `UPDATES.md`, `make_releases.py`, `publish_release.sh`. APKs are GitHub Release files, never committed. |
| `wallpapers/` | 4K photos the Portal downloads on first use (kept out of the APK to keep it small). |
| `plugins/index.json` | The plugin directory list (empty). |
| `docs/` | User guides; the app's "Open guide" buttons link here. |

### Where the features live (app/lib)

| Feature | Files |
|---|---|
| Phoenix Home manager (weather, apps, tiles, wallpapers, glass, cameras, doorbell, Smart Home target, kids settings, remote `phoenixHomeGet/Set`) | `managers/home/phoenix_home_manager.dart` |
| Today screen (default home; a right swipe opens Smart Home, `isSmartHomeSwipe`) | `ui/home/today_home.dart`, `ui/home/home_glass.dart`, `ui/home/live_cameras.dart` |
| Tile layout | `ui/home/home_tiles.dart`, `ui/home/phoenix_home.dart` |
| Weather effects | `ui/home/weather_backdrop.dart` |
| School (SchoolCafe menus, iCal or HA calendar) | `managers/home/school_service.dart`, `ui/home/school_page.dart` |
| Telugu calendar (panchangam), word of the day | `managers/home/panchang.dart`, `managers/home/telugu_words.dart`, `ui/home/telugu_calendar_page.dart` |
| Photos (Immich / folder), photo frame | `managers/home/photo_service.dart`, `ui/home/photo_frame.dart` |
| Kids Portal hub and frame | `ui/kids/kids_overlay.dart`, `ui/kids/kids_activities.dart` |
| Kids games | `kids_learn.dart` (quizzes), `kids_games.dart`, `kids_puzzles.dart`, `kids_play.dart` (incl. piano), `kids_motion.dart` (camera games), `kids_arcade.dart` (Munch Maze, Brick Bash), `kids_arcade2.dart` (Hop Across, Sky Glide, Fox Run), `kids_motion2.dart` (Wall Dodge, Air Trace, Freeze Dance, Goalie, Window Wipe), `kids_touch.dart` (Star Swipe, Stack Up), `kids_learn_more.dart` (Count It, Letter Sounds, Place Value, Story Sums, Telugu Words), `kids_maps.dart` (USA, India, World maps; data in `assets/maps`, rebuilt with `tool/kids_maps`) |
| Hand/head tracking for games | native `GameVision.kt` (game mode: two hands with landmarks, every frame; its body segmenter is no longer asked for), `FaceDetector.kt`, `CameraMotion.kt` (`game` arg); Dart `motion_manager.dart` (`startGameVision`, `startHeadTracking`), `kids_motion.dart` (`KidsHands`, One Euro smoothing, `_CursorPainter`) |
| App Store, side-loading (any APK by link or upload; GitHub apps Morphe and MicroG-RE with update checks) | `managers/store/store_manager.dart`, `ui/store/store_overlay.dart`, native `StoreInstaller.kt` (`inspect`), admin card in `remote-ui/static/phoenix_home.js`, upload endpoint `POST /api/apps/upload`; PC patching `install/patch-morphe.ps1`, guide `install/MORPHE.md` |
| Updates from GitHub | `managers/update/update_manager.dart` (`_releasesUrl` = this repo's GitHub Releases API) |
| Admin Phoenix Home page | `remote-ui/static/phoenix_home.js` (+ CSS in `app.css`, `#tab-phoenix`) |

## Building

```bash
cd app/remote-ui && npm install && npm run build   # admin UI into app/assets
cd .. && flutter build apk --release --split-per-abi --target-platform android-arm
# output: build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

Sign with the release key from "Start here" (key.properties); without it the
build falls back to that machine's own debug key, which does NOT update the
Portals. Check: version (`aapt dump badging`) and signer SHA-256
`47fff989d4...` (`apksigner verify --print-certs`).
APKs ship as GitHub Release files (up to 2 GB each), so the old 100 MB
git file limit no longer applies; still keep it lean (about 100 MB now):
large assets go in `wallpapers/` and download at run time. Never commit an
APK (`.gitignore` blocks `*.apk`).

Before shipping, run the analyzer and the tests that cover what changed.
`test/kids_all_games_test.dart` opens every Kids game at 1280×800,
800×1280 and 1024×600 and plays it a little: add new games to it.

```bash
cd app && flutter analyze lib test
flutter test test/<area>_test.dart
for t in test/*.mjs; do node --test "$t"; done   # admin JS tests
```

Known flaky tests: see "Start here".

## Shipping a build

1. Give it a **new version name** in `app/pubspec.yaml` (e.g.
   `2026.12.13+388`). The Portal's update check compares names.
2. Build, then check: version and signing key.
3. `python3 install/make_releases.py <version> "notes" <apk>` writes
   `install/releases.json` (read by builds older than 2026.12.14).
4. Update `$Version`, `$ApkSize`, `$ApkSha256` in `install/install-phoenix.ps1`
   and the size/SHA in `install/README.md`.
5. Commit and push to `main` (no APK in the commit).
6. `install/publish_release.sh <apk>`: pushes one temporary commit adding
   `install/upload/phoenix-portal.apk` (the cloud environment's git proxy
   refused tags, so this uses the branch; it works the same from any
   machine with push access). The **Phoenix
   release** workflow makes release `v<version>` (from releases.json) on
   the commit below with the APK attached
   (`kiosk-satellite-<version>.armeabi-v7a.apk` and `phoenix-portal.apk`),
   force-moves the branch back off the temporary commit and keeps only the
   newest three releases. Afterwards `git fetch` and check the remote
   branch equals your HEAD and the release exists (`list_releases`).

Portals on **2026.12.3 or newer** then find it themselves (on start and every
12 hours; admin Dashboard › Check for updates checks now) and show
"Update available" in the menu. Older Portals need the PC installer
(`install/LOCAL_AGENT.md`).

Commit messages so far end with the cloud agent's attribution lines; a new
agent may use its own. Never put model names in commits.

## Docs, wiki and screenshots

- `README.md` is the front page; `docs/wiki/*.md` is the wiki's source
  (Home, Install, Today and tiles, Kids Portal, Smart Home, Calendars,
  Photos and screensavers, App Store, Remote admin, Updates,
  Troubleshooting, For developers, `_Sidebar.md`). Publish with
  `docs/wiki/publish-wiki.sh`. `install/README.md` (build notes),
  `install/UPDATES.md` (how updates work), `install/LOCAL_AGENT.md` (steps
  for an agent on the owner's Windows PC) and `CHANGELOG.md` complete it.
  When a feature changes, update the README, the wiki page and the install
  notes with it.
- **Screenshots** (`docs/phoenix/screens/*.jpg`, 1280×800) are made from
  mock data only, never from the owner's Portal or home: a throwaway widget
  test pumps the real screens with sample weather, calendar events, shopping
  items, Home Assistant entities, a made-up school ("Oakwood Elementary"),
  a made-up town ("Springfield") and leaderboard names on the built-in
  wallpapers, with the Telugu calendar off, and saves each with `RenderRepaintBoundary.toImage`. Tips: load
  the app fonts with `FontLoader` (Inter, Nunito, Rubik and Material Icons
  from the Flutter SDK); Telugu needs a font that has both Latin and Telugu
  (merge Inter, instanced at fixed weights, with Noto Sans Telugu scaled to
  2048 units per em, using fontTools), since the test renderer does not fall
  back between families; mock `path_provider` to a folder holding
  `wallpapers/photo_<id>.jpg` for the scenic frame; wait with
  `tester.runAsync` for images to decode. Don't commit the throwaway test.

## Device facts

- Remote admin at `http://<portal-ip>:2324` (ask the owner for the address).
- Package `com.phoenix.portal`. Installed from a Windows PC over USB by a
  local agent using `install/install-phoenix.ps1`.
- The installer also sets Phoenix as the home screen, turns on start on boot,
  and offers to stop other apps (e.g. Portal HA Bridge) opening at boot.

## The Kids Portal at a glance

Shelves (hub order): **Learn** (16 quizzes: Math Blitz, Times Tables, Telling
the Time, Flag Quiz, Word Scramble, Patterns, Fractions, Money, Science,
Spelling, Opposites, Count It, Letter Sounds, Place Value, Story Sums,
Telugu Words), **Maps** (USA, India, World map games), **Puzzles**, **Play**,
**Arcade** (Munch Maze, Brick Bash, Hop Across, Sky Glide, Fox Run),
**Move** (camera games: Space Blaster, Bubble Pop, Fruit Catcher, Finger
Math, Wall Dodge, Air Trace, Freeze Dance), **Create**.

- Quizzes (`KidsQuiz`): no repeats within a round, a best and stars per
  level, "Next level" after 2+ stars.
- Camera games: a **game mode** in the native camera pipeline
  (`GameVision.kt`: every frame, two hands; `CameraMotion.kt` `game` arg),
  `KidsHands` with a responsive One Euro filter (beta 6) and a 40 ms look
  ahead that fades out at low speed. One-player games pass hands through
  `PlayerLock` (keeps the followed hand by position and size, ignores other
  children's; after 1.2 s without it the biggest hand takes over) and
  `HandReach` (a box 7 × 5 hand sizes wide maps to the whole screen and is
  pushed along at its edges). The head tracker passes the last face to
  `FaceDetector.detect` so a nearby face wins over a bigger one. GameVision
  always tracks two hands (needed to choose the player) at 640 px. **Nothing of the child is drawn** (the owner found the hand and
  body renders scary, 2026.12.14): only a pastel bubble cursor per hand
  (pink, blue; yellow for the head) with a sparkle trail
  (`_CursorPainter`). The camera runs only while a camera game is played.
- `test/kids_all_games_test.dart` opens and plays every game at three
  screen sizes with random taps, so a layout bug can show only in some
  game states (Connect Four's 1.6 px button overflow at 1024×600 did:
  fixed in `KidsButton`). Simon Says failed once in a full run and never
  on reruns: if it repeats, capture the message before changing anything.

## Verified vs not yet verified on a real Portal

Verified here (tests, real admin server in Chromium, real SchoolCafe and
a district's calendar data): admin portal end to end, school menus and
calendar parsing, Kids Portal layouts at 1280x800 / 800x1280 / 1024x600,
games by touch, wallpaper and weather rendering, update list format.

Not yet seen on a device:
- A Portal updating itself from GitHub (first chance: 2026.12.3 or later
  updating to a newer build).
- Live HA camera video in the Today card and the doorbell alert (no Home
  Assistant here). The settings and the "no camera" path are tested.
- Hand and head tracking in the camera games, now through the game mode:
  the lag and two hands need a real check (the log line
  "GameVision ... ms a look" gives the per-look cost). Direction may need
  the in-game ↔ swap; the camera must be on in camera settings.
- Freeze Dance's DJ music through the native player (rendered to WAV in
  the cache, phrase by phrase).
- **Calls** on the Today dock opening the Portal's calling screen.
- The camera's green light staying off outside games: Home Assistant's
  ESPHome **Camera** entity opens the camera on every fetch; exclude it
  (ESPHome > Excluded entities) if the owner wants the camera for games only.
- The piano's sound on the device (SoundPool) and the synthesized tone.
- Whether the HA Bridge app still takes over after a reboot once the
  installer has stopped its boot start.

## Kiosk Satellite features kept (checked 2026.12.16)

Every feature in Kiosk Satellite's README is still in Phoenix and its guide
is in `docs/`: Voice Satellite (skins, timers, announcements, wake word with
the screen off and background listening), dashboard optimizations,
Sendspin / AirPlay / HA and Sonos following, Now Playing with lyrics, Music
Library, screensavers (Immich, local photos, clocks, Weather Mood, night
sky), camera motion / face / person detection, ESPHome and the Bluetooth
proxy, remote admin and Fleet, intercom, alarms with sunrise, the family
calendar (Day, Week, Month, Schedule), timers and shared timers, finger
gestures, home launcher, camera views (HA, Go2RTC), PIN kiosk mode, touch and
clap gestures, DLNA, RTSP, Shizuku, plugins, Ground Control / Voice Match,
LED control, custom pages, At a Glance, Remote and JS APIs, TLS.
Deliberately different: English only (the translation catalogs and the
Localization Credits page are gone), ARM-only builds, updates from this
repository's Releases, nothing sent to the original project.

The family calendar (`calendar_overlay.dart`), School and Telugu calendar
pages stand on the wallpaper in glass like the Today screen
(`PhoenixPageBackdrop`, `phoenixGlassTheme` and the `glassFill` colours in
`home_glass.dart`; the calendar takes the home theme's accent).

## Scenic photo frame (2026.12.20)

With no photos set up (no Immich or folder), the Phoenix Photo Frame
(screensaver mode `phoenix_photos`, the Photos page) shows the built-in 4K
landscapes instead of a setup message: `scenicWallpapers` and
`scenicPhoto()` in `phoenix_home_manager.dart` (downloaded once from
`main/wallpapers`, then cached), the slow zoom-and-drift `_Drift` and the
credit line in `photo_frame.dart`.

## Calm look (2026.12.19)

The owner asked for a calmer UI everywhere. The brand tokens in
`ui/theme.dart` (`Phx.ember`, `gold`, `iris`, `mint`, `rose`, `flame`,
`badges`) and `remote-ui/static/app.css` are softened; the home themes in
`home_themes.dart` are desaturated; `kidsSoft()` (kids_activities.dart)
calms the Kids hub and game tints. Full-screen pages use `PhoenixGlassPage`
or `PhoenixPageBackdrop` (`home_glass.dart`): Smart Home, All apps, App
Store, Timers, calendars, School, Telugu, Shopping. Keep new screens in
that look and avoid saturated fills.

## 2026.12.18 features (where they live)

- Kids leaderboards: `kids_logic.dart` (`KidsScores.offer` sets
  `pendingEntry` for a top-ten score; `leaderboard`, `addToBoard`,
  `boardPlace`, `boardInsert`; prefs `phx.kids.board.<key>`,
  `phx.kids.names`), `kids_leaderboard.dart` (name dialog, Top 10 page,
  `boardTitle`/`boardScore` for every score key). The hub wraps itself in
  `KidsHighScoreListener`, so every game gets it without changes.
- Shopping list: `managers/home/todo_service.dart` (todo.get_items through
  `haCallService` with `response: true`), `ui/home/shopping_page.dart`,
  tile id `shopping`.
- Quick-start timers: `TimerQuickStart` in `timers_overlay.dart`.
- From wallpaper theme: `themeFromPixels` / `autoHomeTheme` in
  `home_themes.dart`, fed by `HomeWallpaper`.
- Random layouts: `randomMunchMaze` / `munchMazeIsGood` and
  `randomBrickLayout` in `kids_arcade.dart` (the fixed `munchMazes` and
  `brickLevels` stay as fallbacks and occasional classics).
- Home screens: `HomeTileSpec.page` (`p` in JSON), `homePages`, the
  `PageView` in `HomeTileGrid`, the move handle in `_EditFrame`.

## License and credits

`LICENSE` (2026.12.17): Phoenix Portal under CC BY-NC-ND 4.0, as Kiosk
Satellite (Xavier Larrea) is, with that credit; plus Immortal's MIT notice
(Starbright Lab) for what came from Immortal: the Portal setup steps in
`provisioning/`, `install/install-phoenix.ps1` and `control/`, and the Calls
link. No Immortal source code was copied (checked line by line against the
`legacy-immortal` branch: only generic Android boilerplate matches). About
(device and remote admin) shows Based on Kiosk Satellite, Portal setup from
Immortal, and License linking this repository's LICENSE. Do not relicense.

## Grants a Portal has no screen for

Notification access (Now Playing / Media Session source) has no settings
screen on a Portal. `requestPermissions` with `notificationAccess` now tries
Shizuku (`runShizukuAction notificationAccess`, which runs `cmd notification
allow_listener com.phoenix.portal/me.jxl.kiosk_satellite.MediaSessionListener`)
before opening the screen; the PC installer, Phoenix Control and
`phoenix-provision.sh` run that command over adb. Without Shizuku or adb it
cannot be granted on a Portal.

## Open ideas the owner mentioned

- More motion games; owner will upload wallpapers.
- Bell times have no default; set them on the School page.
- Immortal features not in Phoenix yet (iCloud/SMB/WebDAV photos, clock
  faces, lamp, bedtime stories, notes, converter, hourly chime, help tour):
  see `docs/phoenix/IMMORTAL.md`. Uninstalling Immortal is the owner's call.
- Morphe: patching on the Portal itself can run out of memory (32-bit, ~1 GB
  for the patcher); the PC script is the reliable path. Not yet tried on a
  real Portal: the App Store's GitHub installs, link/upload installs, the
  script (written for Windows PowerShell 5.1, not run here).
- A one-tap "Camera for Kids games only" switch (exclude the HA camera
  entity, turn off the other camera features) was offered, not built.

## Repo and security review (2026.12.13)

Removed as stale: `app/ios` (Portal is Android only; launcher icons now
`ios: false`), `assets/screenshots`, the upstream demo GIFs and benchmark SVG,
four unused `docs/phoenix/screens` images, `.github/funding.yml` (pointed at
the original author) and the upstream issue bots (`stale.yml`,
`require-logs.yml`). Dead code: `core/image_orientation.dart` (and its test),
`resetCelestialPrograms`, `voiceToast`, an orphan font licence.

Security, checked and fine: every remote admin endpoint except login, setup
(only before a password exists), health, fleet invite/identity, intercom and
shared timers needs a signed bearer token (HMAC, expiry, per-IP login
throttling); fleet tokens are limited to the fleet and update endpoints;
file upload/download paths are canonicalized and kept inside their root;
exported Android components are permission-guarded or harmless
(boot/package-replaced); `UpdateHelperProvider` answers only the shell/root
uid; the remote UI builds DOM without `innerHTML`; no secrets in the repo
(only test TLS fixtures); signing keys live outside the repo.

Hardened: the admin password is compared in constant time; sideloaded APKs
(link or upload) are capped at 1 GB and must start with the zip signature
before Android's installer sees them.

Known and accepted: the remote admin is plain http on the LAN by default
(HTTPS can be turned on in its settings); cleartext is allowed because most
Home Assistant dashboards are http; user CAs are trusted for private HA
certificates. With the owner's OK the branch history was rewritten in
2026.12.14 to drop every committed APK (the repository went from about
1.5 GB to under 100 MB); builds are GitHub Release files since. Remaining `jxlarrea` mentions are the required
"Based on Kiosk Satellite" credits, the Echo-only system images (never used
on a Portal) and upstream changelog history.
