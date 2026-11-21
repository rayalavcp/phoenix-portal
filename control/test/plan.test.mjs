import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  A11Y_SERVICE, HOME_ALIAS, STOCK_HOME_FALLBACK, buildRestorePlan, buildSetupPlan,
  looksFailed, parseFacts, pickReleaseAsset, profileCommand, q,
} from '../src/plan.js';

const portalGen1 = parseFacts({
  model: 'Portal+\n', release: '9', sdk: '28\n', abi: 'arm64-v8a',
  packages: 'package:com.facebook.appverifier\npackage:com.facebook.alohaapps.launcher\npackage:com.facebook.aloha.otaui\n',
  overlays: 'com.facebook.aloha.rro.niu.android\n  [x] com.facebook.aloha.rro.niu.android',
  accessibility: 'com.facebook.aloha.system.device/x.KeyEventAccessibilityService',
  home: 'priority=0 preferredOrder=0\ncom.facebook.alohaapps.launcher/com.facebook.aloha.app.home.touch.HomeActivity',
  snapshot: '', phoenix: '', ip: '    inet 192.168.1.40/24 brd 192.168.1.255 scope global wlan0',
});

const emulator = parseFacts({
  model: 'Android SDK built for x86_64', release: '9', sdk: '28', abi: 'x86_64',
  packages: 'package:com.android.launcher3\n', overlays: '', accessibility: 'null',
  home: 'com.android.launcher3/.Launcher', snapshot: '', phoenix: 'versionName=2026.11.23', ip: '',
});

test('parseFacts reads a Gen-1 Portal', () => {
  assert.equal(portalGen1.sdk, 28);
  assert.equal(portalGen1.isPortal, true);
  assert.equal(portalGen1.ip, '192.168.1.40');
  assert.equal(portalGen1.home, STOCK_HOME_FALLBACK);
  assert.equal(emulator.isPortal, false);
  assert.equal(emulator.accessibility, '');
  assert.equal(emulator.phoenixVersion, '2026.11.23');
});

test('setup on a Gen-1 Portal fixes the overlay, the verifier and OTA, keeps Meta accessibility', () => {
  const plan = buildSetupPlan(portalGen1);
  const cmds = plan.map((p) => p.cmd);
  const install = plan.findIndex((p) => p.install);
  const verifier = cmds.indexOf('pm disable-user --user 0 com.facebook.appverifier');
  assert.ok(verifier >= 0 && verifier < install, 'the verifier is off before the install');
  assert.ok(cmds.indexOf('settings put global package_verifier_enable 0') < install);
  assert.ok(cmds.includes('cmd overlay disable --user 0 com.facebook.aloha.rro.niu.android'));
  assert.ok(!cmds.some((c) => c.includes('rro.niu.settings')), 'only overlays present on the device');
  assert.ok(cmds.includes('pm disable-user --user 0 com.facebook.appverifier'));
  assert.ok(cmds.includes('pm disable-user --user 0 com.facebook.aloha.otaui'));
  assert.ok(cmds.some((c) => c.includes(`'com.facebook.aloha.system.device/x.KeyEventAccessibilityService:${A11Y_SERVICE}'`)));
  assert.ok(cmds.includes(`cmd package set-home-activity ${HOME_ALIAS}`));
  assert.ok(cmds.some((c) => c.startsWith(`echo STOCK_HOME=${STOCK_HOME_FALLBACK}`)));
});

test('setup leaves out what a device does not have, and honours the options', () => {
  const cmds = buildSetupPlan(emulator, { setHome: false, blockOta: false }).map((p) => p.cmd);
  assert.ok(!cmds.some((c) => c.includes('overlay') || c.includes('appverifier') || c.includes('aloha')));
  assert.ok(!cmds.some((c) => c.includes('set-home-activity') || c.includes('role')));
  assert.ok(cmds.includes(`settings put secure enabled_accessibility_services '${A11Y_SERVICE}'`));
});

test('Android 10 takes the HOME role instead of set-home-activity', () => {
  const cmds = buildSetupPlan({ ...emulator, sdk: 29 }).map((p) => p.cmd);
  assert.ok(cmds.includes('cmd role add-role-holder android.app.role.HOME com.phoenix.portal'));
});

test('restore uses the saved launcher and removes only our accessibility entry', () => {
  const facts = { ...portalGen1, snapshot: 'STOCK_HOME=com.example/.Home', accessibility: `a/b.C:${A11Y_SERVICE}` };
  const cmds = buildRestorePlan(facts).map((p) => p.cmd);
  assert.ok(cmds.includes('cmd package set-home-activity com.example/.Home'));
  assert.ok(cmds.includes("settings put secure enabled_accessibility_services 'a/b.C'"));
  assert.ok(cmds.includes('pm enable com.facebook.appverifier'));
  assert.ok(!cmds.some((c) => c.includes('uninstall')));
  assert.ok(buildRestorePlan(facts, { uninstall: true }).some((p) => p.cmd === 'pm uninstall com.phoenix.portal'));
});

test('profile command quotes its JSON for the device shell', () => {
  assert.equal(
    profileCommand('kids'),
    `am start -W -n com.phoenix.portal/me.jxl.kiosk_satellite.ProvisionActivity --es ks.provision '{"phoenix.profile":"kids"}'`,
  );
  assert.throws(() => profileCommand('party'));
  assert.equal(q("it's"), `'it'\\''s'`);
});

test('failure detection and release asset choice', () => {
  assert.equal(looksFailed('Success'), false);
  assert.equal(looksFailed('Error: Unknown option'), true);
  assert.equal(looksFailed('java.lang.IllegalArgumentException: no'), true);
  const release = { assets: [{ name: 'kiosk-satellite-v1.apk' }, { name: 'kiosk-satellite-v1.arm64-v8a.apk' }] };
  assert.equal(pickReleaseAsset(release, 'arm64-v8a').name, 'kiosk-satellite-v1.arm64-v8a.apk');
  assert.equal(pickReleaseAsset(release, 'mips').name, 'kiosk-satellite-v1.apk');
  assert.equal(pickReleaseAsset({}, 'x86_64'), null);
});
