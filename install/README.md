# Phoenix Portal test build 2026.11.25 (368)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 95323322 bytes.
  SHA-256 `49f74954edda97a8cd5cb2323b21958ec63c47efe49ff7fb54e214984d6da5eb`.
- New: Phoenix Home launcher (Home Assistant optional), School menus and
  calendar, 13 more Kids Portal activities and a daily challenge.
- Signed with the same **debug key** as the 2026.11.24 test build, so it
  installs over that one with `adb install -r`. Over the earlier
  release-signed build it needs `adb uninstall com.phoenix.portal` first
  (that resets the app's settings).
- Setup script: `provisioning/phoenix-provision.sh` on this branch.

Remove this folder before merging the branch.
