# Phoenix Portal test build 2026.12.26 (401)

- APK: on the repository's [Releases](https://github.com/rayalavcp/phoenix-portal/releases/latest)
  page (`phoenix-portal.apk`), armeabi-v7a, runs on every Portal. 105782252 bytes.
  SHA-256 `8e266e47d1128da0be566f17b0dca7418d4087f6d499e0e91df4675f7ea6783d`.
- New in this build:
  - **Scenic photo frame**: with no photos set up, the Phoenix Photo Frame
    screensaver shows the built-in 4K landscapes (Lake Louise, Gokyo,
    Zhangjiajie ...) slowly zooming and drifting, with the clock, the date
    and each photo's credit. Pick **Phoenix Photo Frame** under
    Settings > Screensaver.
  - Guides, the licence link, the plugin list and wallpapers now come from
    the repository's `main` branch.

### Earlier builds (newest first)

  - **Calmer everywhere**: the orange, gold, blue, green and rose accents
    are a step softer on every screen and in the remote admin. Smart Home,
    All apps, the App Store and Timers now stand on your wallpaper in the
    same frosted glass as the Today screen and the calendars, so moving
    between them no longer jumps between looks. The dock's Kids Portal and
    Smart Home buttons are soft tinted glass instead of bright pills. The
    Kids hub uses gentler colours, a glass stars pill, a quiet challenge
    banner and slower waving and floating. Storms flash once, softly.
  - **New puzzles every game**: Munch Maze makes a new maze each stage
    (mirrored, every path reachable, no dead ends) and Brick Bash a new
    brick wall, fuller and tougher as the stages go up. Maze, Sudoku, Word
    Search and Lights Out were already new every round.
  - **Kids leaderboards, arcade style**: a score that makes a game's top
    ten asks "New high score!" for a name (names used before are one tap
    away). **Top 10** on the Kids hub lists every game's top ten, medals for
    the first three. A parent's score reset clears them too.
  - **Shopping list**: a new tile (with Home Assistant) showing what is
    left to get; tap for a big list to tick items off, add new ones, clear
    the ticked ones or switch lists. It is Home Assistant's own to-do list,
    the same one its app and voice assistants use.
  - **Quick-start timers**: 1, 5, 10, 15 and 30 minute buttons on the
    Timers tile and the empty Timers view start a timer in one tap.
  - **From wallpaper** colours: a theme that takes the tile colours and
    accent from the wallpaper on screen and follows it when it changes.
    Picking another theme is the manual override.
  - **Several home screens**: in edit mode each tile has a move handle
    (top right): Move to Home 2, 3 ... or a new home screen. Swipe between
    them; dots show which one is up. Swiping right on the first still opens
    Smart Home. The remote admin's tile list has a Screen column.
  - **License and credits**: About (on the Portal and in the remote admin)
    links this repository's LICENSE, credits Kiosk Satellite by Xavier
    Larrea and, new, Immortal by Starbright Lab for the Portal setup steps
    and the Calls link.
  - **Update check fix**: a Portal on 2026.12.14 said it was up to date
    while newer builds were out. The check now takes the newest release by
    version number and double-checks GitHub's latest-release page, and
    "You are on the latest version" shows the newest version GitHub
    reported. A Portal on 2026.12.14 to 2026.12.16 can get this build with
    the remote admin's **Phoenix** page > **Install apps on this Portal** >
    **Install from a link**:
    `https://github.com/rayalavcp/phoenix-portal/releases/latest/download/phoenix-portal.apk`.
  - **Calendars match the Today screen**: the family calendar (Day, Week,
    Month, Schedule), the School page and the Telugu calendar now stand on
    your wallpaper with the same frosted glass cards, and the family
    calendar uses the home theme's accent colour.
  - Checked against Kiosk Satellite's feature list: nothing was lost; only
    the translations (Phoenix is English only) were left out on purpose.
  - **The sun sits on the top edge**: a half sun that moves from the left
    at sunrise to the right at sunset, so it never lands on a wallpaper's
    hills or behind the tiles. Shorter, softer rays.
  - **Notification access works on a Portal**: the Portal has no screen
    for it, so Grant on device now grants it through Shizuku when Shizuku
    is set up. The PC installer, Phoenix Control and the provisioning
    script grant it too.
  - **Localization Credits** removed from About (on the Portal and in the
    remote admin): Phoenix Portal is English only.
  - **Camera games, simpler and faster**: no more hand or body renders.
    Each hand is a soft pastel bubble with a little sparkle trail (pink,
    and blue for the second hand; a sunny one when steering with the head).
    The cursor follows quicker moves more closely, and the camera no longer
    works out the body's outline, which leaves it more time for the hands.
  - **The sun follows the day** in the weather effect: it rises low on the
    left, is highest at midday and sets on the right, at the real sunrise
    and sunset for your city. Its rays are soft beams that gently shimmer
    instead of spinning wedges; morning and evening light is warmer.
  - **Tiles like Android widgets**: hold a tile (or tap edit), then drag a
    tile to move it, drag the round handle on its corner to resize it (it
    snaps to whole cells and shows the size), tap × to hide it. The old
    size buttons and the custom size dialog are gone.
  - **Updates from GitHub Releases**: every build is now a release of the
    repository (`v<version>`); the Portal reads the releases from GitHub.
    APKs are no longer stored in the repository.
  - **Review and security pass:** stale files and dead code removed; the
    remote admin's password check is constant-time; an APK installed from a
    link or an upload must really be an APK and is capped at 1 GB.
  - **Swipe right** on the Today screen opens Smart Home (your Home
    Assistant dashboard, or whatever the Smart Home button is set to). A
    swipe in from the very left edge still opens the menu.
  - **Install apps without the browser** (the Portal's browser blocks APK
    downloads): **Morphe** and **MicroG-RE** in the App Store, from their
    GitHub releases, with **Update** when a newer one is out; on the
    remote admin's Phoenix page, **Install apps on this Portal**: any APK
    by link or by upload from the computer.
  - `install/patch-morphe.ps1`: patches YouTube (or YouTube Music) with
    Morphe Desktop on the Windows PC and installs it on the Portal over USB.
    Guide: `install/MORPHE.md`.
  - **Freeze Dance DJ**: dance remixes (beat, bass, chords, synth lead,
    an intro with a riser and a drop) of Twinkle Twinkle, Old MacDonald,
    Mary Had a Little Lamb, London Bridge, Jingle Bells and Ode to Joy,
    made on the Portal. The record scratches to a stop for each freeze.
  - **Calls** on the Today dock: the Portal's own WhatsApp and Messenger
    calling, the way Immortal's Calls tile opened it.
  - Fix: a game button could overflow its space on a 1024×600 screen.
  - Docs: `docs/phoenix/IMMORTAL.md` (what Phoenix covers of Immortal and
    how to remove Immortal safely).
  - **Camera games without the lag**: while a camera game is open the
    camera runs a game mode (every frame, a steady frame rate, no power
    saving pauses), and the cursor uses a smoother that keeps still hands
    steady but follows fast moves closely, with a short look ahead.
  - **Two hands**: both are followed; Bubble Pop pops with either hand,
    Finger Math counts the fingers on both.
  - The camera only runs while a camera game is being played.
  - **Maps** shelf in the Kids Portal: **USA Map** (50 states), **India
    Map** (28 states and 8 union territories, India's official map) and
    **World Map**. Find it, Name it, Capitals, Fill the map (colour the
    whole map in), Shape memory (match shapes to names); the world map
    adds Continents and Flags. Pinch to zoom for small places.
  - **Five new learning games**: Count It, Letter Sounds (phonics), Place
    Value, Story Sums (word problems) and Telugu Words.
  - **Quizzes**: no repeated questions in a round, a best score and stars
    for every level, a "Next level" button after a good round; bigger
    question banks, a Starter level for Spelling and Opposites, Expert
    Science, telling the time to the minute.
  - **More stages**: Snake gets walls that change every 6 apples; Memory
    Pro has 6, 8, 10 or 12 pairs.
  - **Move** shelf: Wall Dodge, Air Trace and Freeze Dance; Munch Maze,
    Hop Across and Snake can be steered by hand or head.
  - Fixes: Bubble Pop and Fruit Catcher showed a blank play area; the
    piano's floating notes caused an error; Tic-Tac-Toe overflowed in
    portrait.
  - **Three more Arcade games**: **Hop Across** (hop a chick over the road
    and across the river on logs to fill five nests), **Sky Glide** (fly Pip
    between crystal spires through day, sunset, night and space; tap, or
    steer with the head) and **Fox Run** (jump over rocks and logs through
    meadow, desert, snow and night; tap, or jump with the head).
  - **More levels**: Munch Maze has four mazes (Classic, Garden, Zigzag,
    Rooms), Brick Bash has 12 levels with three-hit steel bricks; pick
    where to start on each game's start screen.
  - **Arcade** shelf in the Kids Portal, original retro games: **Munch
    Maze** (eat the seeds, dodge the robots, power berries) and **Brick
    Bash** (paddle and bricks; the paddle follows a finger, a hand or the
    head). Both can be hidden from the remote admin.
  - Fix: leaving a camera game before pressing Start no longer crashes.
  - **Nothing goes to the original project**: analytics send nothing, the
    plugin directory and every guide link use this repository.
  - **Guides**: every Open guide button opens this repository's docs.
  - **Updates from GitHub**: the Portal checks this repository's GitHub
    Releases and installs new builds itself (see UPDATES.md).
  - **Move** shelf in the Kids Portal: Space Blaster (arcade shooter steered
    by head or hand), Bubble Pop, Fruit Catcher, Finger Math, using the
    Portal's camera (on-device hand and head tracking).
  - **Live cameras** on the Today screen (Home Assistant, several: swipe
    across the card), a **doorbell alert** (the camera live, full screen,
    for 30 s when it rings) and a **menu items** picker.
  - **Remote admin fixed**: it stopped on its loading spinner since
    2026.11.27 (a startup error in the page's footer translation).
  - **School**: menus from SchoolCafe (breakfast and lunch) and the
    district calendar, for the school you pick.
  - **Today home screen** (the default): the time and weather right on a
    4K wallpaper with live weather effects (rain, storms, snow, fog, sun,
    clouds, stars), glance cards on the right (camera, up next, school,
    Telugu word of the day), and a dock with big **Kids Portal** and
    **Smart Home** buttons.
  - **Wallpapers**: 14 real 4K nature photos from Wikimedia Commons
    (credits in wallpapers/CREDITS.md; the Portal downloads each one the
    first time it shows) rotating every 3 hours,
    11 minimal ones, Bing 4K, your own photos or an image link.
  - **Glass** cards and tiles everywhere, with a transparency slider.
  - **Smart Home** opens your Home Assistant dashboard (the page is
    configurable), or Phoenix's own controls if you prefer.
  - **Kids Portal redesign**: calm photo backgrounds (the home wallpaper,
    softly blurred), frosted glass cards, a big start screen for every game,
    quiz answers as big readable tiles, portrait fixes for 2048 and Connect
    Four, and a Kids Portal section in the remote admin (profile, name,
    daily time, bedtime, PIN, which activities show, reset scores).
  - **Kids piano**: instant notes, a real keyboard with black keys, piano,
    xylophone and music box, seven songs with Listen and follow the
    glowing key.
  - **School menus** from SchoolCafe; school calendar from a Home Assistant
    calendar or iCal.
  - The installer stops other apps (such as Portal HA Bridge) from taking
    over the screen after a reboot, if you say yes.
## About these builds

- Every build is signed with the project's key (certificate SHA-256
  starting `47fff989d4`), so each installs over the last one and keeps the
  settings. A build signed with any other key will not install over it.
- Windows installer: `install-phoenix.ps1` (downloads the release, checks
  its size and SHA-256, installs, sets up, checks).
- Instructions for an agent on the PC: `LOCAL_AGENT.md`. For developers and
  coding agents: `HANDOFF.md` at the repository root.
- How updates reach the Portals: `UPDATES.md`.
