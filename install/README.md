# Phoenix Portal test build 2026.12.11 (386)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 100609682 bytes.
  SHA-256 `b1e3c3a127f44b3132633eb26bd72226be16978b2f4bd60983c50ce422f768e0`.
- New in this build:
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
  - What the camera sees in the camera games is drawn as soft, glowing
    3D pixels (body in the whole-body games, hands in the hand games).
  - Fix: a game button could overflow its space on a 1024×600 screen.
  - Docs: `docs/phoenix/IMMORTAL.md` (what Phoenix covers of Immortal and
    how to remove Immortal safely).
  - **Camera games without the lag**: while a camera game is open the
    camera runs a game mode (every frame, a steady frame rate, no power
    saving pauses), and the cursor uses a smoother that keeps still hands
    steady but follows fast moves closely, with a short look ahead.
  - **Two hands**: both are followed; Bubble Pop pops with either hand,
    Finger Math counts the fingers on both.
  - **What the camera sees**: a soft glowing aura of the body in the
    whole-body games (Wall Dodge, Freeze Dance, head-steered games) and
    a warm sparkly glow on each hand in the hand games. Freeze Dance
    reads movement from the whole body.
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
  - **Updates from GitHub**: the Portal checks install/releases.json in this
    repository and installs new builds itself (see UPDATES.md).
  - **Move** shelf in the Kids Portal: Space Blaster (arcade shooter steered
    by head or hand), Bubble Pop, Fruit Catcher, Finger Math, using the
    Portal's camera (on-device hand and head tracking).
  - **Live cameras** on the Today screen (Home Assistant, several: swipe
    across the card), a **doorbell alert** (the camera live, full screen,
    for 30 s when it rings) and a **menu items** picker.
  - **Remote admin fixed**: it stopped on its loading spinner since
    2026.11.27 (a startup error in the page's footer translation).
  - **School**: Miller Elementary menus from SchoolCafe (breakfast and
    lunch) and the Frisco ISD calendar, set up by default.
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
- Signed with the same **debug key** as the earlier test builds, so it
  installs over them with `adb install -r` and keeps the settings.
- Windows installer: `install-phoenix.ps1` (download, verify, install, set up, check).
- Instructions for the local agent: `LOCAL_AGENT.md`.

Remove this folder before merging the branch.
