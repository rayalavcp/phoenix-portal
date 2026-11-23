# Morphe on a Portal: update it, patch apps, install them

The Portal's browser will not download APK files, so Phoenix Portal brings
apps to the Portal three other ways. Pick whichever suits.

## 1. Morphe and MicroG-RE: from the App Store (no PC)

The App Store (Apps on the Today dock, or the remote admin) lists **Morphe**
and **MicroG-RE**. The Portal downloads them from their GitHub releases
itself, and shows **Update** when a newer release is out (it checks when the
store opens). The remote admin has the same, on the **Phoenix** page under
**Install apps on this Portal**, with **Check for updates**.

- **MicroG-RE** gives YouTube and YouTube Music Google sign-in on a Portal,
  which has no Google services. Install it once; it updates the same way.
- **Morphe** can patch on the Portal, but it gives the patcher at most about
  1 GB of memory on a 32-bit device like the Portal, so YouTube may run out
  of memory. Patching on the PC (below) is the reliable way.

## 2. Patch on the Windows PC, install over USB

`install/patch-morphe.ps1` does it all on the PC that has the Portal on USB:

```
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/claude/fervent-hopper-25a7jk/install/patch-morphe.ps1 -OutFile $env:USERPROFILE\patch-morphe.ps1
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\patch-morphe.ps1
```

1. The first run gets the newest **Morphe Desktop** and **MicroG-RE**
   (Java 21 is needed; it offers to install it) and lists the YouTube
   versions the newest patches support. For YouTube Music add
   `-Package com.google.android.apps.youtube.music`.
2. On the PC, download exactly one of those versions from APKMirror: an
   **APK, not a BUNDLE**, arm or universal (nodpi). Save it in
   `%USERPROFILE%\PhoenixMorphe\input`.
3. Run again with the file:
   `powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\patch-morphe.ps1 -Apk <file>`.
   It patches (keeping only the Portal's 32-bit code, so the APK is small)
   and installs MicroG-RE and the patched app on the Portal.

To update later: run step 1 again (it fetches the newest Morphe and
patches), download the new supported version, run step 3. Keep the
`%USERPROFILE%\PhoenixMorphe` folder: it holds Morphe's signing key
(`morphe-data\morphe.keystore`), and only an APK signed with the same key
installs over the app already on the Portal.

## 3. Any APK: upload it or give a link (no USB)

On the remote admin (`http://<portal>:2324`), **Phoenix** page, **Install
apps on this Portal**:

- **Upload an APK**: an APK from the computer, for example one patched with
  `patch-morphe.ps1 -NoInstall` or with the Morphe Desktop app.
- **Install from a link**: a direct link to an `.apk` file. The Portal
  downloads it itself.

Android asks on the Portal's screen before installing (tap **Install**), or
installs silently when Shizuku is set up. Split bundles (APKM, APKS, XAPK)
must be merged into one APK first; Morphe Desktop merges them when it
patches.
