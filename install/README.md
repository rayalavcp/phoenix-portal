# Phoenix Portal test build 2026.11.26 (369)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 95639665 bytes.
  SHA-256 `12653852cc98f8528e7d9f07cb67c03546beef8242e6fb9462ed2f7d063c95b9`.
- New: Phoenix Home launcher with live, resizable tiles and themes, weather
  in the background, the Telugu calendar, the School page (Miller
  Elementary, Frisco ISD menus and calendar), photos from Immich or a
  network folder with the photo frame screensaver, more Kids Portal
  activities with levels, and a Phoenix Home page in the remote admin.
- Signed with the same **debug key** as the 2026.11.24 and 2026.11.25 test
  builds, so it installs over them with `adb install -r` and keeps the
  settings. Over the original release-signed build it needs
  `adb uninstall com.phoenix.portal` first (that resets the app's
  settings).
- Windows installer: `install-phoenix.ps1` (download, verify, install, set up, check).
- Setup script for Git Bash/Linux/macOS: `provisioning/phoenix-provision.sh` on this branch.

Remove this folder before merging the branch.
