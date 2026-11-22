# Phoenix Portal test build 2026.11.28 (371)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 99636484 bytes.
  SHA-256 `602f81305f01714198d9a9664bd8de24614821a52ebb80f6f91e6262d26fd759`.
- New in this build:
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
