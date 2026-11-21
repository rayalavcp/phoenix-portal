<#
  Phoenix Portal installer for Windows (PowerShell 5.1 or 7).

  Installs or updates Phoenix Portal on a Meta Portal connected over USB,
  sets it up as the home screen, and checks the result. Every step says what
  it does; anything that removes or disables something asks first.

  Run it:
    powershell -ExecutionPolicy Bypass -File .\install-phoenix.ps1

  Options:
    -Yes            answer the safe questions with their default (still asks
                    before uninstalling)
    -KeepMetaUpdates  do not block Meta OS updates
    -Serial <id>    which device, when more than one is connected
#>
param(
  [switch]$Yes,
  [switch]$KeepMetaUpdates,
  [string]$Serial = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 defaults to old TLS, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Version   = '2026.11.26'
$Branch    = 'claude/fervent-hopper-25a7jk'
$ApkUrl    = "https://github.com/rayalavcp/phoenix-portal/raw/$Branch/install/phoenix-portal.apk"
$ApkSize   = 95639665
$ApkSha256 = '4dc841acc35c5cbecfa5f2a18727ef71c4fb393868c5e66f04bfe9df7ba5ae2b'
$Pkg       = 'com.phoenix.portal'
$Ns        = 'me.jxl.kiosk_satellite'
$Main      = "$Pkg/$Ns.MainActivity"
$HomeAlias = "$Pkg/$Ns.HomeAlias"
$Provision = "$Pkg/$Ns.ProvisionActivity"
$A11y      = "$Pkg/$Ns.KioskAccessibilityService"
$Admin     = "$Pkg/$Ns.KioskAdminReceiver"
$StockHome = 'com.facebook.alohaapps.launcher/com.facebook.aloha.app.home.touch.HomeActivity'
$WorkDir   = Join-Path $env:USERPROFILE 'phoenix-portal-install'

$results = New-Object System.Collections.Generic.List[string]
function Say($text)  { Write-Host $text }
function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    OK   $text" -ForegroundColor Green; $results.Add("OK      $text") }
function Warn($text) { Write-Host "    WARN $text" -ForegroundColor Yellow; $results.Add("WARNING $text") }
function Fail($text) { Write-Host "    FAIL $text" -ForegroundColor Red; $results.Add("FAILED  $text") }
function Ask($question, $default) {
  if ($Yes) { return $default }
  $hint = 'y/N'
  if ($default) { $hint = 'Y/n' }
  $answer = Read-Host "$question ($hint)"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
  return $answer.Trim().ToLower().StartsWith('y')
}

# ── adb ─────────────────────────────────────────────────────────────────────
Step 'Finding adb'
$Adb = $null
$cmd = Get-Command adb -ErrorAction SilentlyContinue
if ($cmd) { $Adb = $cmd.Source }
elseif (Test-Path 'C:\platform-tools\adb.exe') { $Adb = 'C:\platform-tools\adb.exe' }
if (-not $Adb) {
  Warn 'adb is not installed.'
  if (Ask 'Download Android platform-tools (Google, about 7 MB) to C:\platform-tools?' $true) {
    $zip = Join-Path $env:TEMP 'platform-tools.zip'
    Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
    Expand-Archive $zip -DestinationPath 'C:\' -Force
    $Adb = 'C:\platform-tools\adb.exe'
  } else {
    Fail 'adb is needed. Install platform-tools and run this again.'
    exit 1
  }
}
Ok "adb: $Adb"

function Adb {
  $all = @()
  if ($Serial) { $all += @('-s', $Serial) }
  $all += $args
  $out = & $Adb @all 2>&1 | Out-String
  return $out.Trim()
}
function Sh($command) { return Adb shell $command }

# ── The Portal ──────────────────────────────────────────────────────────────
Step 'Looking for the Portal on USB'
& $Adb start-server *> $null
$deadline = (Get-Date).AddSeconds(90)
while ($true) {
  $lines = (& $Adb devices) | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' }
  if ($Serial) { $lines = $lines | Where-Object { $_ -like "$Serial*" } }
  $ready = @($lines | Where-Object { $_ -match '\tdevice$' })
  $unauth = @($lines | Where-Object { $_ -match 'unauthorized' })
  if ($ready.Count -gt 1 -and -not $Serial) {
    Fail 'More than one device is connected. Run again with -Serial <id> from this list:'
    $lines | ForEach-Object { Say "      $_" }
    exit 1
  }
  if ($ready.Count -eq 1) { break }
  if ((Get-Date) -gt $deadline) {
    Fail 'No Portal found. Check the USB cable and that USB debugging is on, then run again.'
    exit 1
  }
  if ($unauth.Count -gt 0) { Say '    The Portal asks to allow USB debugging: tap Allow on its screen (tick Always allow).' }
  else { Say '    Waiting for the Portal... (plug it in, unlock it, allow USB debugging)' }
  Start-Sleep -Seconds 3
}
if (-not $Serial) { $Serial = ($ready[0] -split "`t")[0] }
$model = Sh 'getprop ro.product.model'
$android = Sh 'getprop ro.build.version.release'
$sdk = [int](Sh 'getprop ro.build.version.sdk')
Ok "Found $model (Android $android, SDK $sdk), serial $Serial"
$before = Sh "dumpsys package $Pkg | grep versionName"
if ($before) { Say "    Installed now: $($before.Trim())" } else { Say '    Phoenix Portal is not installed yet.' }

# ── Download ────────────────────────────────────────────────────────────────
Step "Downloading Phoenix Portal $Version"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$Apk = Join-Path $WorkDir "phoenix-portal-$Version.apk"
$have = (Test-Path $Apk) -and ((Get-Item $Apk).Length -eq $ApkSize)
if (-not $have) { Invoke-WebRequest $ApkUrl -OutFile $Apk }
$size = (Get-Item $Apk).Length
$hash = (Get-FileHash $Apk -Algorithm SHA256).Hash.ToLower()
if ($size -ne $ApkSize -or $hash -ne $ApkSha256) {
  Fail "The download doesn't match (size $size, SHA-256 $hash). Delete $Apk and run again."
  exit 1
}
Ok "Downloaded and verified $Apk"

# ── Install ─────────────────────────────────────────────────────────────────
Step "Turning off Meta's install verifier (it blocks apps it doesn't know)"
Sh 'pm disable-user --user 0 com.facebook.appverifier' | Out-Null
Sh 'settings put global package_verifier_enable 0' | Out-Null
Ok 'Verifier off'

Step 'Installing (this takes a minute on a Portal)'
$out = Adb install -r -g "$Apk"
if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
  Warn 'The Phoenix Portal on the device is signed with another key, so it must be removed first.'
  Say  '    Removing it resets its settings (dashboard address, admin password, tiles).'
  if (Ask 'Remove the old Phoenix Portal and install the new one?' $false) {
    Adb uninstall $Pkg | Out-Null
    $out = Adb install -r -g "$Apk"
  } else {
    Fail 'Install cancelled: the old version is still there.'
    exit 1
  }
}
if ($out -match 'Success') { Ok 'Installed' }
else {
  Fail "Install failed: $out"
  Say  '    Last install messages from the Portal:'
  Adb logcat -d | Select-String -Pattern 'PackageManager|verif|install' | Select-Object -Last 40 | ForEach-Object { Say "      $_" }
  exit 1
}

# ── Permissions ─────────────────────────────────────────────────────────────
Step 'Granting permissions'
$perms = @('RECORD_AUDIO', 'CAMERA', 'ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'READ_LOGS')
if ($sdk -ge 33) { $perms += 'POST_NOTIFICATIONS' }
foreach ($p in $perms) { Sh "pm grant $Pkg android.permission.$p" | Out-Null }
Sh "appops set $Pkg SYSTEM_ALERT_WINDOW allow" | Out-Null
Sh "appops set $Pkg WRITE_SETTINGS allow" | Out-Null
Sh "appops set $Pkg GET_USAGE_STATS allow" | Out-Null
Sh "dumpsys deviceidle whitelist +$Pkg" | Out-Null
Sh "dpm set-active-admin $Admin" | Out-Null
Ok 'Microphone, camera, location, storage, logs, overlay, settings, usage, battery and screen-off granted'

Step 'Turning on the kiosk guard (keeping Meta''s own accessibility services)'
$current = Sh 'settings get secure enabled_accessibility_services'
if ($current -notlike "*$A11y*") {
  if ([string]::IsNullOrWhiteSpace($current) -or $current -eq 'null') { $next = $A11y } else { $next = "$current`:$A11y" }
  Sh "settings put secure enabled_accessibility_services '$next'" | Out-Null
}
Sh 'settings put secure accessibility_enabled 1' | Out-Null
Sh 'settings put secure immersive_mode_confirmations confirmed' | Out-Null
Ok 'Accessibility on'

if ($sdk -lt 29) {
  Step 'Fixing the Gen-1 white-on-white installer dialog'
  foreach ($o in @('com.facebook.aloha.rro.niu.android', 'com.facebook.aloha.rro.niu.settings')) {
    Sh "cmd overlay disable --user 0 $o" | Out-Null
  }
  Ok 'Installer overlays off'
}

if (-not $KeepMetaUpdates) {
  Step 'Meta OS updates'
  if (Ask 'Block Meta OS updates so an update cannot undo this setup?' $true) {
    foreach ($o in @('com.facebook.aloha.alohaotasetup', 'com.facebook.aloha.otaui')) {
      Sh "pm disable-user --user 0 $o" | Out-Null
    }
    Ok 'Meta OS updates blocked'
  } else { Warn 'Meta OS updates left on' }
}

# ── Home screen ─────────────────────────────────────────────────────────────
Step 'Saving the stock launcher for a later restore'
$saved = Sh 'cat /sdcard/phoenix_restore.env 2>/dev/null'
if ($saved -notlike 'STOCK_HOME=*') {
  Sh "echo STOCK_HOME=$StockHome > /sdcard/phoenix_restore.env" | Out-Null
}
Ok 'Saved in /sdcard/phoenix_restore.env'

# Provisioning payloads go through a small script on the device: PowerShell
# would mangle the JSON quotes on the adb command line.
function Provision($json) {
  $file = Join-Path $WorkDir 'phx.sh'
  $line = "am start -W -n $Provision --es ks.provision '$json'"
  [System.IO.File]::WriteAllText($file, "$line`n", (New-Object System.Text.UTF8Encoding $false))
  Adb push "$file" /data/local/tmp/phx.sh | Out-Null
  $r = Sh 'sh /data/local/tmp/phx.sh'
  Sh 'rm /data/local/tmp/phx.sh' | Out-Null
  Remove-Item $file -ErrorAction SilentlyContinue
  return $r
}

Step 'Making Phoenix Portal the home screen'
Provision '{"home.enabled":true,"launcher.enabled":true,"home.screen":"phoenix","kiosk.start_on_boot":true}' | Out-Null
Ok 'Phoenix Home is the start screen and opens after every reboot'
Sh "pm enable $HomeAlias" | Out-Null
if ($sdk -ge 29) { Sh "cmd role add-role-holder android.app.role.HOME $Pkg" | Out-Null }
else { Sh "cmd package set-home-activity $HomeAlias" | Out-Null }

# Other launchers (for example Portal HA Bridge) fight for HOME.
$homes = (Sh 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME') -split "`n" |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -match '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+$' -and $_ -notlike "$Pkg/*" -and $_ -notlike 'com.facebook.*' -and $_ -notlike 'com.android.settings/*' }
foreach ($h in $homes) {
  Warn "Another app also wants to be the home screen: $h"
  if (Ask "Turn off $h's home screen (the app itself stays installed)?" $false) {
    $r = Sh "pm disable --user 0 $h"
    if ($r -match 'disabled') { Ok "$h no longer competes for the home screen" }
    else { Warn "Couldn't turn it off: $r" }
  }
}
# Apps that open themselves after a reboot (Portal HA Bridge does) cover
# Phoenix Home even when Phoenix is the home screen. Offer to stop only their
# start-at-boot; the apps stay installed and still open from All apps.
Step 'Checking for apps that take over the screen after a reboot'
$bootRx = (Sh 'cmd package query-receivers --brief -a android.intent.action.BOOT_COMPLETED') -split "`n" |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -match '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+$' -and $_ -notlike "$Pkg/*" -and $_ -notlike 'com.facebook.*' -and $_ -notlike 'com.android.*' -and $_ -notlike 'com.google.*' -and $_ -notlike 'android/*' -and $_ -notlike 'com.oculus.*' -and $_ -notlike 'com.meta.*' }
$takeovers = $bootRx | Where-Object { $_ -match '(?i)homeassistant|hass|bridge|kiosk|launcher|dashboard|fully' }
if (-not $takeovers) { Ok 'No other app opens itself at boot' }
foreach ($r in $takeovers) {
  $app = $r.Split('/')[0]
  Warn "$app starts itself after a reboot ($r). This is what sends the Portal back to Home Assistant."
  if (Ask "Stop $app from opening at boot (the app stays installed and still works)?" $true) {
    $out = Sh "pm disable --user 0 $r"
    if ($out -match 'disabled') { Ok "$app no longer opens at boot" }
    else { Warn "Couldn't change it: $out" }
  }
}

$resolved = Sh 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
if ($resolved -like "*$Pkg/*") { Ok 'Phoenix Portal is the home screen' }
else { Warn "Home screen resolves to: $resolved" }

# ── Admin password ──────────────────────────────────────────────────────────
Step 'Remote admin password'
if (-not $Yes) {
  $pw = Read-Host 'Type a new admin password for http://<portal>:2324 (at least 4 characters), or press Enter to keep the current one'
  if (-not [string]::IsNullOrWhiteSpace($pw)) {
    if ($pw.Length -lt 4 -or $pw.Contains("'") -or $pw.Contains('"')) {
      Warn 'Password not changed: use at least 4 characters and no quotes.'
    } else {
      Provision ('{"remote.enabled":true,"remote.password":"' + $pw + '"}') | Out-Null
      Ok 'Admin password set'
    }
  } else { Ok 'Admin password unchanged' }
}

# ── Start and check ─────────────────────────────────────────────────────────
Step 'Starting Phoenix Portal'
Sh "am force-stop $Pkg" | Out-Null
Sh "am start -n $Main" | Out-Null
Start-Sleep -Seconds 6
Sh 'input keyevent KEYCODE_HOME' | Out-Null
Start-Sleep -Seconds 4

# A reboot proves it: Phoenix Home should be on screen, not Home Assistant.
if (Ask 'Reboot the Portal now to check Phoenix Home comes back on its own (about 1 minute)?' $false) {
  Sh 'reboot' | Out-Null
  Start-Sleep -Seconds 20
  Adb wait-for-device | Out-Null
  for ($i = 0; $i -lt 60; $i++) {
    if ((Sh 'getprop sys.boot_completed').Trim() -eq '1') { break }
    Start-Sleep -Seconds 2
  }
  Start-Sleep -Seconds 25
  $top = Sh 'dumpsys activity activities | grep -m1 -E "topResumedActivity|mResumedActivity"'
  if ($top -like "*$Pkg*") { Ok 'After a reboot Phoenix Home is on screen' }
  else { Warn "After a reboot the screen shows: $($top.Trim()). Run this installer again and say Y to the boot question." }
}

$after = Sh "dumpsys package $Pkg | grep versionName"
if ($after -match [regex]::Escape($Version)) { Ok "Version: $($after.Trim())" } else { Fail "Version is $($after.Trim()), expected $Version" }
$procId = Sh "pidof $Pkg"
if ($procId) { Ok "Running (process $procId)" } else { Fail 'Phoenix Portal is not running' }

$shot = Join-Path $WorkDir 'phoenix-screen.png'
cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$shot`""
if ((Test-Path $shot) -and (Get-Item $shot).Length -gt 1000) { Ok "Screenshot: $shot" } else { Warn 'No screenshot taken' }

$ipLine = Sh 'ip -f inet addr show wlan0'
$ip = ''
if ($ipLine -match 'inet (\d+\.\d+\.\d+\.\d+)') { $ip = $Matches[1] }

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '================ Phoenix Portal: summary ================' -ForegroundColor Cyan
Write-Host "Device: $model, Android $android"
$results | ForEach-Object { Write-Host "  $_" }
if ($ip) { Write-Host "Remote admin: http://$($ip):2324" } else { Write-Host 'Remote admin: Wi-Fi address not found (is the Portal on Wi-Fi?)' }
Write-Host "Screenshot: $shot"
Write-Host 'Undo: run phoenix-provision.sh --restore, or ask for the restore steps.'
Write-Host '========================================================='
