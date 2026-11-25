# Instructions for the local agent (Windows PC with the Portal on USB)

Copy everything below the line into the agent.

---

Install the newest Phoenix Portal on the Meta Portal connected to this Windows PC by USB.

Do exactly these steps, in order. Do not skip steps or change anything else.
Do not uninstall or delete anything unless the installer asks and I approve it.
Do not commit or push anything to git.
Do NOT compare the APK against any size or SHA-256 you remember from earlier runs.
The installer downloads the current build and checks it against the values built into it.

STEP 1. Open PowerShell.

STEP 2. Remove old downloaded copies:
Remove-Item $env:TEMP\install-phoenix.ps1, $env:TEMP\phoenix-install -Recurse -Force -ErrorAction SilentlyContinue

STEP 3. Download the installer:
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/main/install/install-phoenix.ps1 -OutFile $env:TEMP\install-phoenix.ps1

STEP 4. Run it:
powershell -ExecutionPolicy Bypass -File $env:TEMP\install-phoenix.ps1

STEP 5. Answer its questions like this:
- "Download Android platform-tools?" -> Y
- "Remove the old Phoenix Portal and install the new one?" -> STOP and ask me first
- "Block Meta OS updates?" -> Y
- "Turn off <app>'s home screen?" -> Y
- "Stop <app> from opening at boot?" -> Y
- "Type a new admin password" -> just press Enter
- "Reboot the Portal now to check?" -> Y

If it says "unauthorized": tell me to tap Allow on the Portal, then run STEP 4 again.
If it says the SHA-256 does not match: run STEP 2, STEP 3 and STEP 4 again.

STEP 6. Send me the whole SUMMARY block it prints, with the version it shows.
If any line says FAIL, also send the 30 lines above it.

After this install (version 2026.12.3 or newer), the Portal updates itself
from GitHub: the PC is only needed again if something goes wrong.

---

## Morphe: patch an app and install it on the Portal

Give the agent this part when the owner wants a Morphe-patched app (YouTube,
YouTube Music) on the Portal. Background: `install/MORPHE.md`.

STEP M1. Download the script:
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/main/install/patch-morphe.ps1 -OutFile $env:USERPROFILE\patch-morphe.ps1

STEP M2. Run it without a file. It gets Morphe and MicroG-RE and lists the
supported YouTube versions:
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\patch-morphe.ps1
(For YouTube Music add: -Package com.google.android.apps.youtube.music)
If it offers to install Java 21 -> Y, then open a NEW PowerShell and run
STEP M2 again.

STEP M3. Tell me the versions it listed. I will download one from
APKMirror into %USERPROFILE%\PhoenixMorphe\input (an APK, not a bundle).
Do not download it yourself unless I say so.

STEP M4. When I say the file is there, run:
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\patch-morphe.ps1 -Apk "%USERPROFILE%\PhoenixMorphe\input\<file name>"
If it says INSTALL_FAILED_UPDATE_INCOMPATIBLE: STOP and ask me (an old
copy would have to be uninstalled).

STEP M5. Send me the SUMMARY block. Never delete the
%USERPROFILE%\PhoenixMorphe folder (it holds the signing key).

---

## Optional: remove Immortal (ONLY when the owner says so)

Give the agent this part only after the owner has decided to remove
Immortal. Background: `docs/phoenix/IMMORTAL.md`.

Do exactly these steps. Do NOT run Immortal's Restore-Portal or
`provision.sh --restore`: it turns Meta's OS updates back on and undoes
the fixes Phoenix needs.

STEP A. Check Phoenix is installed and is the home screen:
adb shell pm list packages com.phoenix.portal
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
The second line must mention com.phoenix.portal. If not, STOP and tell me.

STEP B. Turn off Immortal's device admin:
adb shell dpm remove-active-admin com.immortal.launcher/.AdminReceiver
If that fails, tell me to open on the Portal: Settings > Security >
Device admin apps > Immortal > Deactivate, then continue.

STEP C. Uninstall it:
adb uninstall com.immortal.launcher

STEP D. Make sure Meta's presence sensor is on (Phoenix uses it):
adb shell pm list packages -d
If com.facebook.alohaservices.presence is in that list, run:
adb shell pm enable com.facebook.alohaservices.presence

STEP E. Send me the output of every step.
