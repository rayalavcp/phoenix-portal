# Updating Phoenix Portal

Phoenix Portal updates itself from this repository's
[GitHub Releases](https://github.com/rayalavcp/phoenix-portal/releases). No PC is needed once it
is installed.

## On the Portal

1. In **Device › Updates** (on the Portal, or in the remote admin at
   `http://<portal-ip>:2324`), **Update source** must be **GitHub Repository**
   (the default).
2. The Portal checks on its own, on start and every 12 hours. To check now: in the remote admin,
   open **Dashboard** and press **Check for updates**. "You are on the latest version" also names
   the newest version GitHub reported.
3. When a newer version is found, the Portal's menu shows **Update available**. Tap it, then
   **Update**. The Portal downloads the APK (about 100 MB), installs it over the current version
   and restarts. Your settings are kept.

The Portal compares version names (for example `2026.12.20`), so every new build gets a new
version name.

## Other ways to install a build

- **By link, no USB:** remote admin › **Phoenix** › **Install apps on this Portal** › **Install
  from a link**:
  `https://github.com/rayalavcp/phoenix-portal/releases/latest/download/phoenix-portal.apk`
- **From a file:** remote admin › Device › Updates › **Install from file**, with
  `phoenix-portal.apk` downloaded from the Releases page.
- **From a PC over USB:** `install/install-phoenix.ps1` (see [`LOCAL_AGENT.md`](LOCAL_AGENT.md)).
- **No internet:** set Update source to **Custom Repository** and point it at a folder on your
  network holding a copy of `releases.json` and the APK.

## What the Portal reads

Every build is a GitHub Release, tag `v<version>` (for example `v2026.12.20`), with the APK
attached twice:

| File | For |
|---|---|
| `kiosk-satellite-<version>.armeabi-v7a.apk` | The Portal's own updater (it picks the APK by this name). |
| `phoenix-portal.apk` | People and the PC installer. The newest is always at https://github.com/rayalavcp/phoenix-portal/releases/latest/download/phoenix-portal.apk |

The Portal reads the list of releases from GitHub's API, takes the newest by version number and
double-checks GitHub's latest-release page. [`install/releases.json`](releases.json) on `main`
names the newest release too, for very old builds.

APKs are never committed to the repository.

## Where the APKs are

On the repository's **Releases** page: https://github.com/rayalavcp/phoenix-portal/releases (on
the repository's main page: **Releases** in the right-hand column). Only the newest three builds
are kept; older ones are deleted when a new one is published.

## Publishing a new version (developers)

1. Give the build a new version name in `app/pubspec.yaml` (for example
   `version: 2026.12.21+396`), build it and check it is signed with the project key
   (see [`HANDOFF.md`](../HANDOFF.md)).
2. Write the release file:
   ```bash
   python3 install/make_releases.py 2026.12.21 "What changed in this build" path/to/app.apk
   ```
3. Update `$Version`, `$ApkSize` and `$ApkSha256` in `install/install-phoenix.ps1` and the size
   and SHA-256 at the top of `install/README.md`. Commit and push to `main`.
4. Publish the release:
   ```bash
   install/publish_release.sh path/to/app.apk
   ```
   It pushes one temporary commit holding the APK. The **Phoenix release** workflow
   (`.github/workflows/phoenix-release.yml`) makes release `v2026.12.21` with the APK attached,
   takes the temporary commit off `main` again and deletes releases older than the newest three.
   Portals offer the update at their next check.
