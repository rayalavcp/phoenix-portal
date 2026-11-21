# Instructions for the local agent (Windows PC with the Portal on USB)

Copy everything below the line into the agent.

---

Install the latest Phoenix Portal on the Meta Portal plugged into this PC by USB.
Do exactly these steps, in order. Do not improvise, do not skip, do not commit or push anything.

1. Open **PowerShell** (not Command Prompt).

2. Run this one line to download the installer:

   ```powershell
   Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/claude/fervent-hopper-25a7jk/install/install-phoenix.ps1 -OutFile $env:TEMP\install-phoenix.ps1
   ```

3. Run the installer:

   ```powershell
   powershell -ExecutionPolicy Bypass -File $env:TEMP\install-phoenix.ps1
   ```

4. Answer its questions like this:
   - "Download Android platform-tools ...?": **Y**
   - "Remove the old Phoenix Portal and install the new one?" (only asked if the old build was signed differently): **stop and ask the user first** (it resets the app's settings).
   - "Block Meta OS updates?": **Y**
   - "Turn off <app>'s home screen?": **Y**
   - "<app> starts itself after a reboot ... Stop <app> from opening at boot?": **Y**
     (this is the fix for the Portal going back to Home Assistant after a reboot;
     the app stays installed)
   - Admin password: type the password the user gives you, or press Enter to keep it.
   - "Reboot the Portal now to check...?": **Y**

5. When it finishes, copy the whole **SUMMARY** block it prints and send it to the user.
   If any line says FAIL, also send the 30 lines above it.

If `adb` says "unauthorized": tell the user to tap **Allow** on the Portal screen, then run step 3 again.
If the installer says the download's SHA-256 doesn't match: run step 2 again, then step 3.
