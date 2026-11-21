# Phoenix Portal test build 2026.11.25 (368)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 95323322 bytes.
  SHA-256 `f6d0590a7098b6598aa0ad5944566efa17e2297c2c6f768ec4b7e9bbf840664f`.
- New: Phoenix Home launcher (Home Assistant optional), School menus and
  calendar, 13 more Kids Portal activities and a daily challenge.
- Signed with the same **debug key** as the 2026.11.24 test build, so it
  installs over that one with `adb install -r`. Over the earlier
  release-signed build it needs `adb uninstall com.phoenix.portal` first
  (that resets the app's settings).
- Setup script: `provisioning/phoenix-provision.sh` on this branch.

Remove this folder before merging the branch.
