// Demo mode (?demo): a pretend first-gen Portal+ that answers like a real one,
// so the whole flow can be tried, and tested, without a device.
import { parseFacts } from './plan.js';

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

export class DemoDevice {
  serial = 'DEMO-PORTAL-PLUS';
  installed = false;

  async shell(command) {
    await wait(60);
    if (command.startsWith('pm install')) { this.installed = true; return 'Success'; }
    if (command.startsWith('am start -W')) return 'Status: ok\nComplete';
    return '';
  }

  async facts() {
    return parseFacts({
      model: 'Portal+', release: '9', sdk: '28', abi: 'arm64-v8a',
      packages: ['com.facebook.appverifier', 'com.facebook.alohaapps.launcher', 'com.facebook.aloha.otaui',
        'com.facebook.aloha.alohaotasetup', ...(this.installed ? ['com.phoenix.portal'] : [])]
        .map((p) => `package:${p}`).join('\n'),
      overlays: 'com.facebook.aloha.rro.niu.android\n  [x] com.facebook.aloha.rro.niu.android',
      accessibility: 'com.facebook.aloha.system.device/com.facebook.aloha.system.device.accessibility.KeyEventAccessibilityService',
      home: 'com.facebook.alohaapps.launcher/com.facebook.aloha.app.home.touch.HomeActivity',
      snapshot: '',
      phoenix: this.installed ? 'versionName=2026.11.23' : '',
      ip: 'inet 192.168.1.40/24 brd 192.168.1.255 scope global wlan0',
    });
  }

  async pushApk(_blob, onProgress) {
    for (let f = 0.25; f <= 1; f += 0.25) { await wait(80); onProgress?.(f); }
  }

  async screenshot() {
    const r = await fetch('mark.svg');
    return r.blob();
  }

  async reboot() {}
  async close() {}
}
