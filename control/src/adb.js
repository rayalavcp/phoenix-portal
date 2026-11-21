// Phoenix Control's connection to a device: ADB over WebUSB through Tango
// (@yume-chan/adb, MIT). Everything device-facing goes through this module so
// the UI (app.js) stays a thin layer over plan.js.

import { Adb, AdbDaemonTransport } from '@yume-chan/adb';
import { AdbDaemonWebUsbDeviceManager } from '@yume-chan/adb-daemon-webusb';
import AdbWebCredentialStore from '@yume-chan/adb-credential-web';
import { APK_TMP, PKG, STATE_FILE, parseFacts } from './plan.js';

const credentials = new AdbWebCredentialStore('Phoenix Control');

export const webUsbSupported = () => Boolean(AdbDaemonWebUsbDeviceManager.BROWSER);

/**
 * Ask the browser for a device and open ADB on it. The Portal shows an
 * "Allow USB debugging?" prompt the first time; this waits for it.
 */
export async function connect() {
  const manager = AdbDaemonWebUsbDeviceManager.BROWSER;
  if (!manager) throw new Error('This browser has no WebUSB. Use Chrome or Edge on a computer.');
  const device = await manager.requestDevice();
  if (!device) return null;
  let connection;
  try {
    connection = await device.connect();
  } catch (e) {
    // The usual cause: a desktop `adb` server already holds the USB interface.
    throw new Error(
      `Couldn't open the device (${e?.message ?? e}). If adb is running on this computer, run "adb kill-server" and try again.`,
    );
  }
  const transport = await AdbDaemonTransport.authenticate({
    serial: device.serial,
    connection,
    credentialStore: credentials,
  });
  return new Device(new Adb(transport));
}

export class Device {
  constructor(adb) {
    this.adb = adb;
  }

  get serial() {
    return this.adb.serial;
  }

  /** Run a shell command and return its output (stdout and stderr). */
  async shell(command) {
    return this.adb.subprocess.noneProtocol.spawnWaitText(command);
  }

  /** The raw outputs plan.parseFacts reads. */
  async facts() {
    const run = (c) => this.shell(c).catch(() => '');
    const [model, release, sdk, abi, packages, overlays, accessibility, home, snapshot, phoenix, ip] = await Promise.all([
      run('getprop ro.product.model'),
      run('getprop ro.build.version.release'),
      run('getprop ro.build.version.sdk'),
      run('getprop ro.product.cpu.abi'),
      run('pm list packages'),
      run('cmd overlay list 2>/dev/null'),
      run('settings get secure enabled_accessibility_services'),
      run('cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'),
      run(`cat ${STATE_FILE} 2>/dev/null`),
      run(`dumpsys package ${PKG} | grep versionName`),
      run('ip -4 addr show wlan0'),
    ]);
    return parseFacts({ model, release, sdk, abi, packages, overlays, accessibility, home, snapshot, phoenix, ip });
  }

  /** Copy an APK (a File or Blob) to the device's temp folder for `pm install`. */
  async pushApk(blob, onProgress) {
    const sync = await this.adb.sync();
    try {
      let sent = 0;
      const total = blob.size;
      const source = blob.stream().pipeThrough(
        new TransformStream({
          transform(chunk, controller) {
            sent += chunk.byteLength;
            onProgress?.(sent / total);
            controller.enqueue(chunk);
          },
        }),
      );
      await sync.write({ filename: APK_TMP, file: source, permission: 0o644 });
    } finally {
      await sync.dispose();
    }
  }

  /** A PNG screenshot of the screen as a Blob. */
  async screenshot() {
    const bytes = await this.adb.subprocess.noneProtocol.spawnWait('screencap -p');
    return new Blob([bytes], { type: 'image/png' });
  }

  async reboot() {
    await this.adb.power.reboot();
  }

  async close() {
    await this.adb.close();
  }
}

/**
 * The latest Phoenix Portal release from GitHub. Asset downloads need a
 * redirect GitHub doesn't open to other sites, so the UI offers the file from
 * the release page when a direct fetch is refused.
 */
export async function latestRelease(repo) {
  const r = await fetch(`https://api.github.com/repos/${repo}/releases/latest`);
  if (!r.ok) throw new Error(r.status === 404 ? 'No release published yet.' : `GitHub answered ${r.status}.`);
  return r.json();
}

export async function downloadAsset(asset) {
  const r = await fetch(asset.browser_download_url);
  if (!r.ok) throw new Error(`Download failed (${r.status}).`);
  return r.blob();
}
