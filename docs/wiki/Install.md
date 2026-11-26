# Install

You need a Meta Portal (Portal, Portal+, Portal Mini, Portal Go or Portal TV) with **ADB**
turned on (Settings → Debugging; on Portal TV, Developer options), a USB-C data cable and a
computer. Installing takes about 10 minutes.

## Option 1: Phoenix Control in the browser

[Phoenix Control](https://github.com/rayalavcp/phoenix-portal/tree/main/control) runs in Chrome
or Edge and talks to the Portal over USB (WebUSB). Nothing to install.

1. Connect the Portal and open Phoenix Control.
2. **Connect device**, then tap **Allow** on the Portal.
3. Choose the APK (download `phoenix-portal.apk` from the
   [latest release](https://github.com/rayalavcp/phoenix-portal/releases/latest)), press
   **Review plan**: it shows every command before it runs.
4. Press **Apply**. It installs Phoenix, applies the Portal fixes and makes it the home screen.

Add `?demo` to the address to try it without a device.

## Option 2: Windows installer (PowerShell)

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/rayalavcp/phoenix-portal/main/install/install-phoenix.ps1 -OutFile $env:TEMP\install-phoenix.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\install-phoenix.ps1
```

It downloads Android's platform tools if needed, downloads the newest release, checks its
SHA-256, installs it, sets Phoenix as the home screen, offers to block Meta OS updates and
prints a summary. An AI agent on the PC can do it for you:
[install/LOCAL_AGENT.md](https://github.com/rayalavcp/phoenix-portal/blob/main/install/LOCAL_AGENT.md).

## Option 3: a terminal (macOS or Linux)

```bash
./provisioning/phoenix-provision.sh --dry-run    # print the plan only
./provisioning/phoenix-provision.sh              # set up (asks before applying)
./provisioning/phoenix-provision.sh --restore    # back to the stock Portal
```

## After installing

Finish the short setup wizard on the Portal, or from a computer at `http://<portal-ip>:2324`
(see [Remote admin](Remote-Admin.md)). Home Assistant is optional: skip it if you don't use it.

The Portal then [updates itself](Updates.md).

## Replacing Immortal

If the Portal ran Immortal before, read
[Phoenix Portal and Immortal](https://github.com/rayalavcp/phoenix-portal/blob/main/docs/phoenix/IMMORTAL.md)
before removing it: do **not** run Immortal's restore, which turns Meta's updates back on.
