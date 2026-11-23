# Phoenix Portal: patch an app with Morphe on this Windows PC and install it
# on the Portal over USB. Patching needs more memory than a Portal has (Morphe
# gives the patcher at most about 1 GB on a 32-bit device), and the Portal's
# browser will not download APKs, so the PC does the work:
#
#   1. gets the newest Morphe Desktop (the patcher) and MicroG-RE (Google
#      sign-in for YouTube and YouTube Music without Google services),
#   2. without -Apk: shows which app versions the newest patches support,
#      so you can download exactly that version on this PC,
#   3. with -Apk: patches it (keeping only the Portal's 32-bit code) and
#      installs MicroG-RE and the patched app on the Portal.
#
#   powershell -ExecutionPolicy Bypass -File patch-morphe.ps1
#   powershell -ExecutionPolicy Bypass -File patch-morphe.ps1 -Apk C:\path\youtube.apk
#   powershell -ExecutionPolicy Bypass -File patch-morphe.ps1 -Package com.google.android.apps.youtube.music
#
# Everything lives in %USERPROFILE%\PhoenixMorphe, including Morphe's signing
# key (morphe-data\morphe.keystore): keep that folder, or a later re-patch
# will not install over the app already on the Portal.
param(
  [string]$Apk = '',
  [string]$Package = 'com.google.android.youtube',
  [switch]$NoInstall
)
# Not 'Stop': Windows PowerShell treats a program's stderr (java -version,
# adb's progress lines) as an error under 'Stop'. Failures are checked
# explicitly instead, and web calls ask for -ErrorAction Stop themselves.
$ErrorActionPreference = 'Continue'
$Work = Join-Path $env:USERPROFILE 'PhoenixMorphe'
$Patches = 'https://github.com/MorpheApp/morphe-patches'
$results = New-Object System.Collections.Generic.List[string]

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    OK   $text" -ForegroundColor Green; $results.Add("OK      $text") }
function Warn($text) { Write-Host "    WARN $text" -ForegroundColor Yellow; $results.Add("WARNING $text") }
function Fail($text) { Write-Host "    FAIL $text" -ForegroundColor Red; $results.Add("FAILED  $text") }
function Ask($question, $default) {
  $hint = if ($default) { 'Y/n' } else { 'y/N' }
  $answer = Read-Host "$question ($hint)"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
  return $answer.Trim().ToLower().StartsWith('y')
}
function Summary {
  Write-Host ''
  Write-Host '===== SUMMARY =====' -ForegroundColor Cyan
  foreach ($r in $results) { Write-Host $r }
  Write-Host "Folder: $Work"
}

# The newest release's file whose name matches $pattern: @{ Version; Url; Name }.
function LatestAsset($repo, $pattern) {
  $rel = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop -Headers @{ 'User-Agent' = 'PhoenixPortal' } "https://api.github.com/repos/$repo/releases/latest"
  $asset = $rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
  if (-not $asset) { throw "No file like $pattern in the latest $repo release" }
  return @{ Version = ($rel.tag_name -replace '^v', ''); Url = $asset.browser_download_url; Name = $asset.name }
}

# Downloads $asset into $Work unless that version is already there.
function Fetch($asset, $target) {
  $marker = "$target.version"
  if ((Test-Path $target) -and (Test-Path $marker) -and ((Get-Content $marker) -eq $asset.Version)) {
    Ok "$($asset.Name) is current ($($asset.Version))"
    return
  }
  Invoke-WebRequest -UseBasicParsing -ErrorAction Stop $asset.Url -OutFile $target
  Set-Content $marker $asset.Version
  Ok "Downloaded $($asset.Name)"
}

New-Item -ItemType Directory -Force -Path $Work, (Join-Path $Work 'input'), (Join-Path $Work 'out') | Out-Null

Step 'Java 21 or newer (Morphe Desktop needs it)'
$javaOk = $false
try {
  # java prints its version on stderr; under 'Continue' that is just text.
  $v = (& java -version 2>&1 | Out-String)
  if ($v -match 'version "(\d+)') { $javaOk = [int]$Matches[1] -ge 21 }
} catch { }
if (-not $javaOk) {
  if (Ask 'Java 21 is missing. Install Eclipse Temurin 21 JRE with winget now?' $true) {
    winget install --id EclipseAdoptium.Temurin.21.JRE -e --accept-source-agreements --accept-package-agreements
    Warn 'Java was installed: close this window, open a new PowerShell and run this script again.'
  } else {
    Fail 'Java 21 is needed. Install it (https://adoptium.net) and run this again.'
  }
  Summary; exit 1
}
Ok 'Java is ready'

Step 'Morphe Desktop and MicroG-RE (newest releases)'
$jar = Join-Path $Work 'morphe-desktop.jar'
$microg = Join-Path $Work 'microg.apk'
try {
  Fetch (LatestAsset 'MorpheApp/morphe-desktop' '^morphe-desktop-.*-all\.jar$') $jar
  Fetch (LatestAsset 'MorpheApp/MicroG-RE' '^microg-.*\.apk$') $microg
} catch {
  Fail "Could not get Morphe from GitHub: $($_.Exception.Message)"
  Summary; exit 1
}

if (-not $Apk) {
  Step "App versions the newest patches support ($Package)"
  & java -jar $jar list-versions -p $Patches -f $Package
  Write-Host ''
  Write-Host 'Next:' -ForegroundColor Cyan
  Write-Host "  1. On this PC, download exactly one of the versions above for $Package from"
  Write-Host '     https://www.apkmirror.com as an APK (not a BUNDLE), arm or universal (nodpi).'
  Write-Host "  2. Save it in $Work\input"
  Write-Host '  3. Run:  powershell -ExecutionPolicy Bypass -File patch-morphe.ps1 -Apk <that file>'
  Ok 'Listed the supported versions'
  Summary; exit 0
}

if (-not (Test-Path $Apk)) { Fail "No such file: $Apk"; Summary; exit 1 }
if ($Apk -match '\.(apkm|apks|xapk)$') { Warn 'That is a split bundle: Morphe can merge it, but a full APK is more reliable.' }

Step 'Patching (a few minutes)'
$name = [System.IO.Path]::GetFileNameWithoutExtension($Apk)
$out = Join-Path $Work "out\$name-morphe.apk"
Push-Location $Work
try {
  # The Portal is a 32-bit ARM device: keep only that code (a much smaller APK).
  & java -jar $jar patch -p $Patches --striplibs armeabi-v7a -o $out $Apk
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { throw "Morphe exited with $LASTEXITCODE" }
  Ok "Patched: $out"
} catch {
  Fail "Patching failed: $($_.Exception.Message). If it says the version is not supported, run without -Apk to see the supported versions."
  Pop-Location; Summary; exit 1
}
Pop-Location

if ($NoInstall) {
  Ok 'Not installing (-NoInstall). Upload the APK on the Portal''s remote admin: Phoenix page > Install apps > Upload an APK.'
  Summary; exit 0
}

Step 'Installing on the Portal (USB)'
$Adb = $null
$cmd = Get-Command adb -ErrorAction SilentlyContinue
if ($cmd) { $Adb = $cmd.Source } elseif (Test-Path 'C:\platform-tools\adb.exe') { $Adb = 'C:\platform-tools\adb.exe' }
if (-not $Adb) {
  Fail 'adb not found. Run install-phoenix.ps1 once (it sets up C:\platform-tools), or upload the APK on the remote admin instead.'
  Summary; exit 1
}
& $Adb start-server *> $null
$devices = (& $Adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' }
if (-not $devices) { Fail 'No Portal on USB (or it says unauthorized: tap Allow on the Portal and run again).'; Summary; exit 1 }
$serial = ($devices | Select-Object -First 1).Split("`t")[0]

$hasMicrog = (& $Adb -s $serial shell pm list packages app.revanced.android.gms | Out-String) -match 'app.revanced.android.gms'
if ($Package -like 'com.google.android*' -or $Package -like 'com.google.android.apps*') {
  $r = (& $Adb -s $serial install -r $microg 2>&1 | Out-String)
  if ($r -match 'Success') { Ok ($(if ($hasMicrog) { 'MicroG-RE updated' } else { 'MicroG-RE installed' })) } else { Fail "MicroG-RE: $r" }
}
$r = (& $Adb -s $serial install -r $out 2>&1 | Out-String)
if ($r -match 'Success') {
  Ok "Installed $name (Morphe) on the Portal"
} elseif ($r -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
  Fail 'An older patched copy signed with a different key is on the Portal. Uninstall it on the Portal first (ask before doing that), then run again.'
} else {
  Fail "Install: $r"
}
Summary
