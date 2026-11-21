# Phoenix Portal test build 2026.11.27 (370)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 95771677 bytes.
  SHA-256 `5b0a66d341bb336dca634953d6f15b7907781dca0ca30b8b61869248944eca3d`.
- New in this build:
  - **Today home screen** (the new default): a greeting, the next festival
    and the moon phase up top; glass cards over the daily landscape photo
    with weather effects (clock and 5-day forecast, photos, Up next,
    front door camera or favourite apps, school, Telugu word of the day);
    one row of big buttons along the bottom. The old tile grid is still
    there: Customize (the sliders button) > Layout > Tiles.
  - **School menus from SchoolCafe** (where Frisco ISD posts them). Set the
    SchoolCafe school ID once: School > the gear, or the remote admin's
    Phoenix Home > School. The school calendar can be a Home Assistant
    calendar (for example `calendar.frisco_isd`) or an iCal link.
  - **No more Home Assistant after a reboot**: the installer turns on
    Start on boot and offers to stop other apps (such as Portal HA Bridge)
    from opening themselves at boot. Those apps stay installed.
- Signed with the same **debug key** as the 2026.11.24 to 2026.11.26 test
  builds, so it installs over them with `adb install -r` and keeps the
  settings. Over the original release-signed build it needs
  `adb uninstall com.phoenix.portal` first (that resets the app's
  settings).
- Windows installer: `install-phoenix.ps1` (download, verify, install, set up, check).
- Setup script for Git Bash/Linux/macOS: `provisioning/phoenix-provision.sh` on this branch.

Remove this folder before merging the branch.
