# Troubleshooting

**"You are on the latest version", but a newer release exists.** Builds before 2026.12.17
could miss a release. Install the newest one by link once (see [Updates](Updates.md)); from
2026.12.17 on, the check double-checks GitHub and names the newest version it saw.

**An update or install says "signatures do not match" (INSTALL_FAILED_UPDATE_INCOMPATIBLE).**
The APK was signed with a different key than the one installed. Only official releases (or
builds signed with the project key) install over Phoenix. Don't uninstall to force it: that wipes
the Portal's settings. Ask the person who built it.

**The camera's green light stays on.** Something keeps opening the camera. Home Assistant's
ESPHome **Camera** entity for the Portal takes a picture on every fetch: exclude it in Home
Assistant (ESPHome › the Portal › Excluded entities) if you only want the camera for games.

**Notification access shows "Not granted".** A Portal has no settings screen for it. Set up
Shizuku and tap **Grant on device**, or from a computer with the Portal on USB:
`adb shell cmd notification allow_listener com.phoenix.portal/me.jxl.kiosk_satellite.MediaSessionListener`

**ADB says "unauthorized".** Tap **Allow** on the Portal's screen and run the step again.

**The remote admin doesn't open.** Check the Portal's address (Settings › Device, or your router), that the
computer is on the same network, and that **Remote management** is on in Settings › Device.

**Camera games don't follow my hand.** Allow the camera in Settings › Camera, stand about one to
two metres away in good light, and use the ↔ button in the game if left and right are swapped.

**Guides or the licence link show "page not found".** Builds up to 2026.12.19 linked to a branch
that was removed; update to 2026.12.20 or newer.
