// Phoenix Control's provisioning plan: pure functions from what a device
// reports to the exact commands that set it up or restore it. Kept in step
// with provisioning/phoenix-provision.sh (the same steps, the same order), so
// the browser and the command line always do the same thing.

export const PKG = 'com.phoenix.portal';
export const NS = 'me.jxl.kiosk_satellite';
export const MAIN_ACTIVITY = `${PKG}/${NS}.MainActivity`;
export const HOME_ALIAS = `${PKG}/${NS}.HomeAlias`;
export const PROVISION_ACTIVITY = `${PKG}/${NS}.ProvisionActivity`;
export const A11Y_SERVICE = `${PKG}/${NS}.KioskAccessibilityService`;
export const ADMIN_RECEIVER = `${PKG}/${NS}.KioskAdminReceiver`;
export const STATE_FILE = '/sdcard/phoenix_restore.env';
export const RELEASE_REPO = 'rayalavcp/phoenix-portal';
export const APK_TMP = '/data/local/tmp/phoenix-portal.apk';

export const VERIFIER_PKG = 'com.facebook.appverifier';
export const INSTALLER_OVERLAY_PKGS = ['com.facebook.aloha.rro.niu.android', 'com.facebook.aloha.rro.niu.settings'];
export const OTA_PACKAGES = ['com.facebook.aloha.alohaotasetup', 'com.facebook.aloha.otaui'];
export const STOCK_HOME_FALLBACK =
  'com.facebook.alohaapps.launcher/com.facebook.aloha.app.home.touch.HomeActivity';

const GRANTS = [
  'RECORD_AUDIO', 'CAMERA', 'ACCESS_COARSE_LOCATION', 'ACCESS_FINE_LOCATION',
  'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'READ_LOGS',
];

/** Single-quote a value for the device shell. */
export function q(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

/**
 * The facts a plan needs, parsed from the raw command outputs the browser
 * collects (see readFacts in adb.js). Pure, so it is tested without a device.
 */
export function parseFacts(raw) {
  const line = (s) => String(s ?? '').trim();
  const packages = new Set(
    String(raw.packages ?? '').split('\n').map((l) => l.trim().replace(/^package:/, '')).filter(Boolean),
  );
  const sdk = Number.parseInt(line(raw.sdk), 10) || 0;
  const a11y = line(raw.accessibility);
  return {
    model: line(raw.model) || 'Android device',
    release: line(raw.release),
    sdk,
    abi: line(raw.abi),
    packages,
    overlays: String(raw.overlays ?? ''),
    accessibility: a11y === 'null' ? '' : a11y,
    home: line(raw.home).split('\n').pop()?.trim() ?? '',
    snapshot: line(raw.snapshot),
    phoenixVersion: (String(raw.phoenix ?? '').match(/versionName=(\S+)/) ?? [])[1] ?? null,
    ip: (String(raw.ip ?? '').match(/inet (\d+\.\d+\.\d+\.\d+)/) ?? [])[1] ?? null,
    isPortal: [...packages].some((p) => p.startsWith('com.facebook.aloha')),
  };
}

const hasOverlay = (facts, pkg) => facts.overlays.includes(pkg);

/** The steps that set a device up. `install` marks the APK step. */
export function buildSetupPlan(facts, { setHome = true, blockOta = true, apkName = 'Phoenix Portal' } = {}) {
  const plan = [];
  const add = (desc, cmd, extra = {}) => plan.push({ desc, cmd, ...extra });
  // Meta's verifier rejects installs it doesn't allowlist, so it goes first.
  if (facts.packages.has(VERIFIER_PKG)) {
    add("Disable Meta's install verifier (it blocks installs it doesn't know)", `pm disable-user --user 0 ${VERIFIER_PKG}`);
  }
  add('Turn off package verification', 'settings put global package_verifier_enable 0');
  add(`Install ${apkName}`, `pm install -r -g ${APK_TMP}`, { install: true });
  for (const g of GRANTS) add(`Grant ${g}`, `pm grant ${PKG} android.permission.${g}`);
  if (facts.sdk >= 33) add('Grant POST_NOTIFICATIONS', `pm grant ${PKG} android.permission.POST_NOTIFICATIONS`);
  add('Allow drawing over other apps', `appops set ${PKG} SYSTEM_ALERT_WINDOW allow`);
  add('Allow changing system settings (brightness)', `appops set ${PKG} WRITE_SETTINGS allow`);
  add('Allow usage access (foreground app sensor)', `appops set ${PKG} GET_USAGE_STATS allow`);
  add('Exempt from battery optimisation', `dumpsys deviceidle whitelist +${PKG}`);
  add('Screen-off device admin', `dpm set-active-admin ${ADMIN_RECEIVER}`);

  if (!facts.snapshot) {
    let home = facts.home;
    if (!home || home.startsWith(`${PKG}/`) || home.startsWith('android/') || home.includes('ResolverActivity')) {
      home = STOCK_HOME_FALLBACK;
    }
    add(`Save the stock launcher (${home}) for restore`, `echo STOCK_HOME=${home} > ${STATE_FILE}`);
  }

  // Append to the existing list: a Portal runs two Meta services that must stay on.
  if (!facts.accessibility.includes(A11Y_SERVICE)) {
    const list = facts.accessibility ? `${facts.accessibility}:${A11Y_SERVICE}` : A11Y_SERVICE;
    add(
      facts.accessibility ? "Enable the kiosk guard (accessibility, keeping Meta's services)" : 'Enable the kiosk guard (accessibility)',
      `settings put secure enabled_accessibility_services ${q(list)}`,
    );
  }
  add('Accessibility on', 'settings put secure accessibility_enabled 1');
  add("Skip Android's full-screen hint bubble", 'settings put secure immersive_mode_confirmations confirmed');

  if (facts.sdk < 29) {
    for (const ov of INSTALLER_OVERLAY_PKGS) {
      if (hasOverlay(facts, ov)) add(`Fix the Gen-1 white-on-white installer dialog (${ov})`, `cmd overlay disable --user 0 ${ov}`);
    }
  }
  if (blockOta) {
    for (const o of OTA_PACKAGES) {
      if (facts.packages.has(o)) add(`Block Meta OS updates (${o}), so an OTA can't undo this setup`, `pm disable-user --user 0 ${o}`);
    }
  }
  if (setHome) {
    add("Turn on the app's Home Launcher setting", `am start -W -n ${PROVISION_ACTIVITY} --es ks.provision ${q('{"home.enabled":true,"launcher.enabled":true}')}`);
    add('Enable the home screen entry point', `pm enable ${HOME_ALIAS}`);
    add(
      'Make Phoenix Portal the home screen',
      facts.sdk >= 29 ? `cmd role add-role-holder android.app.role.HOME ${PKG}` : `cmd package set-home-activity ${HOME_ALIAS}`,
    );
  }
  add('Restart the app so new grants (READ_LOGS) apply', `am force-stop ${PKG}`);
  add('Open Phoenix Portal', `am start -n ${MAIN_ACTIVITY}`);
  return plan;
}

/** The steps that put a device back the way Meta shipped it. */
export function buildRestorePlan(facts, { uninstall = false } = {}) {
  const plan = [];
  const add = (desc, cmd) => plan.push({ desc, cmd });
  let home = STOCK_HOME_FALLBACK;
  const m = facts.snapshot.match(/^STOCK_HOME=(.+)$/m);
  if (m) home = m[1].trim();
  if (facts.packages.has(VERIFIER_PKG)) add("Re-enable Meta's install verifier", `pm enable ${VERIFIER_PKG}`);
  add('Turn package verification back on', 'settings put global package_verifier_enable 1');
  for (const ov of INSTALLER_OVERLAY_PKGS) {
    if (hasOverlay(facts, ov)) add(`Re-enable Meta overlay ${ov}`, `cmd overlay enable --user 0 ${ov}`);
  }
  for (const o of OTA_PACKAGES) {
    if (facts.packages.has(o)) add(`Re-enable Meta OS updates (${o})`, `pm enable ${o}`);
  }
  if (facts.accessibility.includes(A11Y_SERVICE)) {
    const rest = facts.accessibility.split(':').filter((s) => s && s !== A11Y_SERVICE).join(':');
    add(
      rest ? 'Remove the kiosk guard (keeping other services)' : 'Remove the kiosk guard',
      rest ? `settings put secure enabled_accessibility_services ${q(rest)}` : 'settings delete secure enabled_accessibility_services',
    );
  }
  const homePkg = home.split('/')[0];
  add(
    `Give the home screen back to ${facts.sdk >= 29 ? homePkg : home}`,
    facts.sdk >= 29 ? `cmd role add-role-holder android.app.role.HOME ${homePkg}` : `cmd package set-home-activity ${home}`,
  );
  add('Disable the Phoenix home screen entry point', `pm disable ${HOME_ALIAS}`);
  add('Forget the restore snapshot', `rm -f ${STATE_FILE}`);
  if (uninstall) {
    add('Remove the screen-off device admin', `dpm remove-active-admin ${ADMIN_RECEIVER}`);
    add('Uninstall Phoenix Portal', `pm uninstall ${PKG}`);
  }
  add('Go home', 'input keyevent KEYCODE_HOME');
  return plan;
}

/** Switch the Family / Kids / Night profile through the app's provisioning door. */
export function profileCommand(profile) {
  if (!['family', 'kids', 'night'].includes(profile)) throw new Error(`unknown profile ${profile}`);
  return `am start -W -n ${PROVISION_ACTIVITY} --es ks.provision ${q(JSON.stringify({ 'phoenix.profile': profile }))}`;
}

/** Whether a shell command's output reads as a failure (pm, cmd and am print, they don't exit non-zero over adb). */
export function looksFailed(output) {
  return /(^|\n)\s*(Error|Exception|Failure|java\.lang\.|Unknown (command|package)|Security exception)/i.test(String(output ?? ''));
}

/** The release asset that fits a device's ABI from a GitHub releases/latest response. */
export function pickReleaseAsset(release, abi) {
  const assets = release?.assets ?? [];
  return assets.find((a) => a.name.endsWith(`.${abi}.apk`)) ?? assets.find((a) => /\.apk$/.test(a.name) && !/\.(arm64-v8a|armeabi-v7a|x86_64)\.apk$/.test(a.name)) ?? null;
}
