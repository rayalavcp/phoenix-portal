# Phoenix Portal test build 2026.11.24 (367)

- `phoenix-portal.apk`: armeabi-v7a, runs on every Portal. 94909618 bytes.
  SHA-256 `76c8d7ea51b8b4e72b2ff23e6ae289af34d9c47c7b5790a2fed27d028aa1fd4c`.
- Signed with a **debug key**, not the Phoenix release key. Installing it over
  the earlier release-signed test build needs `adb uninstall com.phoenix.portal`
  first (that resets the app's settings).
- Setup script: `provisioning/phoenix-provision.sh` on this branch (it now
  also turns on the App Launcher).

Remove this folder before merging the branch.
