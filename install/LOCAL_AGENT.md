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
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/claude/fervent-hopper-25a7jk/install/install-phoenix.ps1 -OutFile $env:TEMP\install-phoenix.ps1

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
