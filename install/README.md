# Phoenix Portal test build 2026.12.2 (377)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 99770760 bytes.
  SHA-256 `03a09c0039a7112f2e22f4ee4cf8be3bbe4f63f2a146629c5fc05f3d483feab5`.
- New in this build:
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
