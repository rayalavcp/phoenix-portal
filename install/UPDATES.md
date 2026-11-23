# Updating Phoenix Portal from GitHub

Phoenix Portal updates itself from this repository's
[GitHub Releases](https://github.com/rayalavcp/phoenix-portal/releases). No PC is needed once a build
with this feature is installed.

## On the Portal

1. In **Device › Updates** (on the Portal, or in the remote admin at
   `http://<portal-ip>:2324`), **Update source** must be **GitHub Repository**
   (the default).
2. The Portal checks on its own. To check now: in the remote admin, open
   **Dashboard** and press **Check for updates**.
3. When a newer version is found, the Portal's menu shows **Update available**.
   Tap it, then **Update**. The Portal downloads the APK (about 100 MB),
   installs it over the current version and restarts. Your settings are kept.

The Portal compares version names (for example `2026.12.3`), so every new
build gets a new version name.

## What the Portal reads

| File | What it is## What the Portal reads

Every build is a GitHub Release, tag `v<version>` (for example
`v2026.12.14`), with the APK attached twice:

| File | For |
|---|---|
| `kiosk-satellite-<version>.armeabi-v7a.apk` | The Portal's own updater (it picks the APK by this name). |
| `phoenix-portal.apk` | People and the PC installer. The newest is always at https://github.com/rayalavcp/phoenix-portal/releases/latest/download/phoenix-portal.apk |

Portals on **2026.12.14 or newer** read the releases from GitHub's API.
Older builds read [`install/releases.json`](releases.json) from the branch,
which names the same release file, so they update the same way.

APKs are never committed to the repository (each one is about 100 MB, and
history kept every one of them).

## Publishing a new version

1. Build the APK with a new version name in `app/pubspec.yaml`
   (for example `version: 2026.12.15+390`).
2. Write the release file for older builds:
   ```bash
   python3 install/make_releases.py 2026.12.15 "What changed in this build" path/to/app.apk
   ```
3. Update `$Version`, `$ApkSize` and `$ApkSha256` in `install/install-phoenix.ps1`
   (for PC installs). Commit and push the branch.
4. Publish the release:
   ```bash
   install/publish_release.sh path/to/app.apk
   ```
   It pushes one temporary commit holding the APK; the **Phoenix release**
   workflow (`.github/workflows/phoenix-release.yml`) makes release
   `v2026.12.15` with the APK attached, takes the temporary commit off the
   branch again and deletes releases older than the newest three. Portals
   offer the update at their next check.

## Where the APKs are

On the repository's **Releases** page:
https://github.com/rayalavcp/phoenix-portal/releases (on the repository's
main page: **Releases** in the right-hand column). Only the newest three
builds are kept; older ones are deleted when a new one is published.

all from file**: in the remote admin, Device › Updates › Install from
  file, pick `phoenix-portal.apk` downloaded from the Releases page.
- **From a PC over USB**: run `install/install-phoenix.ps1`
  (see [`LOCAL_AGENT.md`](LOCAL_AGENT.md)).
- **No internet**: set Update source to Custom Repository and point it at a
  folder on your network holding a copy of `releases.json` and the APK.
