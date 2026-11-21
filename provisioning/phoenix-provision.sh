#!/usr/bin/env bash
# Phoenix Portal provisioning: one command to turn a Meta Portal (or any
# Android 9+ tablet) into a Phoenix Portal, and one to put it back.
#
#   ./phoenix-provision.sh                 set up the connected device
#   ./phoenix-provision.sh --apk app.apk   ... with a local APK instead of the latest release
#   ./phoenix-provision.sh --dry-run       only print the plan (every adb command)
#   ./phoenix-provision.sh --restore       undo: stock launcher, verifier, overlays, OS updates
#   ./phoenix-provision.sh --status        show what is set on the device
#
# Every run builds a plan first: it inspects the device read-only, prints each
# command it is about to run, and asks before touching anything (--yes skips
# the question). Steps that don't apply to the device (a Meta overlay that
# isn't there, Android 10 role APIs on Android 9) are left out of the plan.
#
# Ported from the Immortal provisioning kit (the Gen-1 installer overlay fix,
# verifier and OTA handling, the stock-launcher snapshot for restore) and the
# Portal guide in docs/portal.md. Requires adb on PATH (or ADB=/path/to/adb).
set -uo pipefail

PKG="${PKG:-com.phoenix.portal}"
NS="me.jxl.kiosk_satellite"            # the app's class namespace
MAIN_ACTIVITY="$PKG/$NS.MainActivity"
HOME_ALIAS="$PKG/$NS.HomeAlias"           # the HOME entry point, off until enabled
PROVISION_ACTIVITY="$PKG/$NS.ProvisionActivity"
A11Y_SERVICE="$PKG/$NS.KioskAccessibilityService"
ADMIN_RECEIVER="$PKG/$NS.KioskAdminReceiver"
RELEASE_REPO="${RELEASE_REPO:-rayalavcp/phx-kiosk-satellite}"
STATE_FILE="/sdcard/phoenix_restore.env"

# Meta Portal components (absent on other devices: their steps are skipped).
VERIFIER_PKG="com.facebook.appverifier"
INSTALLER_OVERLAY_PKGS="com.facebook.aloha.rro.niu.android com.facebook.aloha.rro.niu.settings"
OTA_PACKAGES="com.facebook.aloha.alohaotasetup com.facebook.aloha.otaui"
STOCK_HOME_FALLBACK="com.facebook.alohaapps.launcher/com.facebook.aloha.app.home.touch.HomeActivity"

MODE=setup APK="" ASSUME_YES=false DRY_RUN=false BLOCK_OTA=true SET_HOME=true UNINSTALL=false
while [ $# -gt 0 ]; do
  case "$1" in
    --restore) MODE=restore ;;
    --status) MODE=status ;;
    --apk) APK="${2:?--apk needs a path}"; shift ;;
    --yes|-y) ASSUME_YES=true ;;
    --dry-run) DRY_RUN=true ;;
    --keep-ota) BLOCK_OTA=false ;;
    --no-home) SET_HOME=false ;;
    --uninstall) UNINSTALL=true ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' O=$'\e[38;5;208m' N=$'\e[0m'; else B= D= G= Y= R= O= N=; fi
say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$O$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

ADB="${ADB:-$(command -v adb || true)}"
[ -n "$ADB" ] || die "adb not found. Install Android platform-tools or set ADB=/path/to/adb."
a() { "$ADB" "$@"; }
sh_() { a shell "$@" 2>/dev/null | tr -d '\r'; }

# ----- device -----------------------------------------------------------------
wait_for_device() {
  step "Waiting for a device (enable USB debugging and accept the prompt on screen)"
  local state
  for _ in $(seq 1 60); do
    state="$(a get-state 2>/dev/null || true)"
    [ "$state" = device ] && break
    sleep 2
  done
  [ "$(a get-state 2>/dev/null)" = device ] || die "No authorized device. Check the cable and the USB debugging prompt."
  MODEL="$(sh_ getprop ro.product.model)"
  SDK="$(sh_ getprop ro.build.version.sdk)"
  ABI="$(sh_ getprop ro.product.cpu.abi)"
  RELEASE="$(sh_ getprop ro.build.version.release)"
  OVERLAYS="$(sh_ cmd overlay list)"
  PACKAGES="$(sh_ pm list packages)"
  IS_PORTAL=false
  case "$PACKAGES" in *com.facebook.alohaapps*|*com.facebook.aloha*) IS_PORTAL=true ;; esac
  ok "$MODEL · Android $RELEASE (API $SDK) · $ABI$([ "$IS_PORTAL" = true ] && echo ' · Meta Portal')"
}

has_pkg() { printf '%s\n' "$PACKAGES" | grep -qx "package:$1"; }
has_overlay() { printf '%s\n' "$OVERLAYS" | grep -q "$1"; }

# ----- the plan -----------------------------------------------------------------
PLAN_DESC=() PLAN_CMD=()
plan() { PLAN_DESC+=("$1"); PLAN_CMD+=("$2"); }

print_plan() {
  step "Plan: ${#PLAN_CMD[@]} commands"
  local i
  for i in "${!PLAN_CMD[@]}"; do
    printf '  %s%2d.%s %s\n      %sadb %s%s\n' "$B" $((i + 1)) "$N" "${PLAN_DESC[$i]}" "$D" "${PLAN_CMD[$i]}" "$N"
  done
}

confirm() {
  $DRY_RUN && { say; say "${D}Dry run: nothing was changed.${N}"; exit 0; }
  $ASSUME_YES && return
  [ -t 0 ] || die "Not interactive: re-run with --yes to apply the plan."
  printf '\n%sApply this plan?%s [y/N] ' "$B" "$N"
  local ans; read -r ans || ans=""
  case "$ans" in [Yy]*) ;; *) say "Nothing changed."; exit 0 ;; esac
}

run_plan() {
  local i failed=0 out
  for i in "${!PLAN_CMD[@]}"; do
    # shellcheck disable=SC2086 # each plan entry is a word list by design
    if out="$(eval "a ${PLAN_CMD[$i]}" 2>&1)"; then
      ok "${PLAN_DESC[$i]}"
    else
      warn "${PLAN_DESC[$i]} — ${out:-failed}"
      failed=$((failed + 1))
    fi
  done
  return $failed
}

# ----- setup --------------------------------------------------------------------
resolve_apk() {
  [ -n "$APK" ] && { [ -f "$APK" ] || die "APK not found: $APK"; return; }
  step "Finding the latest Phoenix Portal release for $ABI"
  local api="https://api.github.com/repos/$RELEASE_REPO/releases/latest" url
  url="$(curl -fsSL "$api" 2>/dev/null | grep -o '"browser_download_url": *"[^"]*'"$ABI"'\.apk"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$url" ] || die "No $ABI release found in $RELEASE_REPO. Build one or pass --apk path/to/app.apk."
  APK="$(mktemp -t phoenix-XXXXXX).apk"
  curl -fL --progress-bar -o "$APK" "$url" || die "Download failed: $url"
  ok "Downloaded $(basename "$url")"
}

current_home() {
  sh_ cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1
}

build_setup_plan() {
  plan "Install Phoenix Portal ($(basename "$APK"))" "install -r -g \"$APK\""
  # The runtime grants from docs/portal.md (-g covers most at install; these
  # make them explicit and cover the ones install -g skips).
  local p
  for p in RECORD_AUDIO CAMERA ACCESS_COARSE_LOCATION ACCESS_FINE_LOCATION READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE READ_LOGS; do
    plan "Grant $p" "shell pm grant $PKG android.permission.$p"
  done
  [ "${SDK:-0}" -ge 33 ] && plan "Grant POST_NOTIFICATIONS" "shell pm grant $PKG android.permission.POST_NOTIFICATIONS"
  plan "Allow drawing over other apps" "shell appops set $PKG SYSTEM_ALERT_WINDOW allow"
  plan "Allow changing system settings (brightness)" "shell appops set $PKG WRITE_SETTINGS allow"
  plan "Allow usage access (foreground app sensor)" "shell appops set $PKG GET_USAGE_STATS allow"
  plan "Exempt from battery optimisation" "shell dumpsys deviceidle whitelist +$PKG"
  plan "Screen-off device admin" "shell dpm set-active-admin $ADMIN_RECEIVER"

  # Snapshot the stock launcher once, for --restore.
  if ! a shell "[ -f $STATE_FILE ]" >/dev/null 2>&1; then
    local home; home="$(current_home)"
    case "$home" in ""|"$PKG"/*|android/*|*ResolverActivity*) home="$STOCK_HOME_FALLBACK" ;; esac
    plan "Save the stock launcher ($home) for restore" "shell \"echo STOCK_HOME=$home > $STATE_FILE\""
  fi

  # Accessibility: append to the existing list (a Portal runs two Meta
  # services that must stay on), never replace it.
  local current; current="$(sh_ settings get secure enabled_accessibility_services)"
  case "$current" in
    *"$A11Y_SERVICE"*) ;;
    ""|null) plan "Enable the kiosk guard (accessibility)" "shell settings put secure enabled_accessibility_services $A11Y_SERVICE" ;;
    *) plan "Enable the kiosk guard (accessibility, keeping Meta's services)" "shell settings put secure enabled_accessibility_services '$current:$A11Y_SERVICE'" ;;
  esac
  plan "Accessibility on" "shell settings put secure accessibility_enabled 1"
  plan "Skip Android's full-screen hint bubble" "shell settings put secure immersive_mode_confirmations confirmed"

  # Meta Portal fixes.
  if has_pkg "$VERIFIER_PKG"; then
    plan "Disable Meta's install verifier (in-app updates and the app store)" "shell pm disable-user --user 0 $VERIFIER_PKG"
  fi
  plan "Turn off package verification" "shell settings put global package_verifier_enable 0"
  if [ "${SDK:-99}" -lt 29 ]; then
    local ov
    for ov in $INSTALLER_OVERLAY_PKGS; do
      has_overlay "$ov" && plan "Fix the Gen-1 white-on-white installer dialog ($ov)" "shell cmd overlay disable --user 0 $ov"
    done
  fi
  if $BLOCK_OTA; then
    local o
    for o in $OTA_PACKAGES; do
      has_pkg "$o" && plan "Block Meta OS updates ($o), so an OTA can't undo this setup" "shell pm disable-user --user 0 $o"
    done
  fi

  if $SET_HOME; then
    # The app's own Home Launcher setting first, so the app agrees it is the
    # home screen; then the HOME alias on, and HOME pointed at it.
    plan "Turn on the app's Home Launcher setting" "shell \"am start -W -n $PROVISION_ACTIVITY --es ks.provision '{\\\"home.enabled\\\":true}'\""
    plan "Enable the home screen entry point" "shell pm enable $HOME_ALIAS"
    if [ "${SDK:-0}" -ge 29 ]; then
      plan "Make Phoenix Portal the home screen" "shell cmd role add-role-holder android.app.role.HOME $PKG"
    else
      plan "Make Phoenix Portal the home screen" "shell cmd package set-home-activity $HOME_ALIAS"
    fi
  fi
  plan "Restart the app so new grants (READ_LOGS) apply" "shell am force-stop $PKG"
  plan "Open Phoenix Portal" "shell am start -n $MAIN_ACTIVITY"
}

after_setup() {
  step "Starting the update helper (silent in-app updates until the next reboot)"
  local out; out="$(sh_ "content read --uri content://$PKG.update-helper/start | sh")"
  case "$out" in *started*|*running*) ok "Update helper running" ;; *) warn "Update helper not started (open the app once, then re-run with --yes)" ;; esac
  say
  say "${G}${B}✓ Phoenix Portal is set up.${N} Finish the wizard on the screen or at http://$(sh_ ip -4 addr show wlan0 | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1):2324"
  say "${D}Undo any time with: $0 --restore${N}"
}

# ----- restore ------------------------------------------------------------------
build_restore_plan() {
  local home="$STOCK_HOME_FALLBACK" saved
  saved="$(sh_ cat "$STATE_FILE")"
  case "$saved" in STOCK_HOME=*) home="${saved#STOCK_HOME=}"; home="${home%%$'\n'*}" ;; esac
  has_pkg "$VERIFIER_PKG" && plan "Re-enable Meta's install verifier" "shell pm enable $VERIFIER_PKG"
  plan "Turn package verification back on" "shell settings put global package_verifier_enable 1"
  local ov o
  for ov in $INSTALLER_OVERLAY_PKGS; do
    has_overlay "$ov" && plan "Re-enable Meta overlay $ov" "shell cmd overlay enable --user 0 $ov"
  done
  for o in $OTA_PACKAGES; do
    has_pkg "$o" && plan "Re-enable Meta OS updates ($o)" "shell pm enable $o"
  done
  local current rest
  current="$(sh_ settings get secure enabled_accessibility_services)"
  case "$current" in
    *"$A11Y_SERVICE"*)
      rest="$(printf '%s' "$current" | tr ':' '\n' | grep -vx "$A11Y_SERVICE" | paste -sd: -)"
      if [ -n "$rest" ]; then
        plan "Remove the kiosk guard (keeping other services)" "shell settings put secure enabled_accessibility_services '$rest'"
      else
        plan "Remove the kiosk guard" "shell settings delete secure enabled_accessibility_services"
      fi ;;
  esac
  if [ "${SDK:-0}" -ge 29 ]; then
    plan "Give the home screen back to ${home%%/*}" "shell cmd role add-role-holder android.app.role.HOME ${home%%/*}"
  else
    plan "Give the home screen back to $home" "shell cmd package set-home-activity $home"
  fi
  plan "Disable the Phoenix home screen entry point" "shell pm disable $HOME_ALIAS"
  plan "Forget the restore snapshot" "shell rm -f $STATE_FILE"
  if $UNINSTALL; then
    plan "Remove the screen-off device admin" "shell dpm remove-active-admin $ADMIN_RECEIVER"
    plan "Uninstall Phoenix Portal" "uninstall $PKG"
  fi
  plan "Go home" "shell input keyevent KEYCODE_HOME"
}

# ----- status -------------------------------------------------------------------
do_status() {
  step "Phoenix Portal status"
  local v; v="$(sh_ dumpsys package "$PKG" | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1)"
  [ -n "$v" ] && ok "Installed: $PKG $v" || warn "Not installed"
  ok "Home: $(current_home)"
  ok "Package verification: $(sh_ settings get global package_verifier_enable)"
  ok "Accessibility: $(sh_ settings get secure enabled_accessibility_services)"
  local ov; for ov in $INSTALLER_OVERLAY_PKGS; do has_overlay "$ov" && ok "Overlay $(printf '%s\n' "$OVERLAYS" | grep "$ov" | head -1)"; done
  a shell "[ -f $STATE_FILE ]" >/dev/null 2>&1 && ok "Restore snapshot: $(sh_ cat "$STATE_FILE")" || warn "No restore snapshot"
}

# ----- main ---------------------------------------------------------------------
printf '%s%sPhoenix Portal%s %sprovisioning%s\n\n' "$O" "$B" "$N" "$D" "$N"
wait_for_device
case "$MODE" in
  status) do_status ;;
  restore)
    build_restore_plan; print_plan; confirm
    step "Restoring"; run_plan; say; say "${G}${B}✓ Stock settings restored.${N}" ;;
  setup)
    $DRY_RUN && [ -z "$APK" ] && APK="phoenix-portal-latest.$ABI.apk"
    $DRY_RUN || resolve_apk
    build_setup_plan; print_plan; confirm
    step "Applying"
    run_plan || warn "Some steps did not apply (see above); the rest are in place."
    after_setup ;;
esac
