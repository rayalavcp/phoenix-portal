# Updating Phoenix Portal from GitHub

Phoenix Portal updates itself from this repository,
[rayalavcp/phoenix-portal](https://github.com/rayalavcp/phoenix-portal),
on the branch `claude/fervent-hopper-25a7jk`. No PC is needed once a build
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

| File | What it is |
|---|---|
| [`install/releases.json`](releases.json) | The newest version, its notes and where its APK is. Same shape as GitHub's releases list. |
| [`install/phoenix-portal.apk`](phoenix-portal.apk) | The APK itself (armeabi-v7a, runs on every Portal). |

## Publishing a new version

1. Build the APK with a new version name in `app/pubspec.yaml`
   (for example `version: 2026.12.4+379`).
2. Copy it to `install/phoenix-portal.apk`.
3. Write the release file:
   ```bash
   python3 install/make_releases.py 2026.12.4 "What changed in this build"
   ```
4. Update `$Version`, `$ApkSize` and `$ApkSha256` in `install/install-phoenix.ps1`
   (for PC installs).
5. Commit and push. Portals offer the update at their next check.

## Without the Portal's own updater

- **Install from file**: in the remote admin, Device › Updates › Install from
  file, pick `phoenix-portal.apk` downloaded from this repository.
- **From a PC over USB**: run `install/install-phoenix.ps1`
  (see [`LOCAL_AGENT.md`](LOCAL_AGENT.md)).
- **No internet**: set Update source to Custom Repository and point it at a
  folder on your network holding a copy of `releases.json` and the APK.
