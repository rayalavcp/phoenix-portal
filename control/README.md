# Phoenix Control

Set up and manage Phoenix Portal devices from the browser: no software to
install. Phoenix Control talks ADB over WebUSB (Chrome or Edge on a computer),
through [Tango ADB](https://github.com/yume-chan/ya-webadb) (MIT).

- **Device:** model, Android version, CPU, whether Phoenix Portal is installed,
  the home screen and the Wi-Fi address.
- **Set up:** installs the latest release (or an APK you choose), grants the
  permissions, fixes the Gen-1 Portal's white-on-white installer dialog,
  disables Meta's verifier, blocks Meta OS updates (optional) and makes Phoenix
  Portal the home screen. **Every command is listed before anything runs.**
- **Restore:** puts the stock launcher, verifier, overlays and OS updates back;
  optionally uninstalls.
- **Profile:** Family / Kids / Night, the same switch Home Assistant flips.
- **Tools:** screenshot, reboot, and a link to the device's remote admin
  (`http://<device>:2324`) for everything after setup, over Wi-Fi.

The same plan runs from a terminal with
[`provisioning/phoenix-provision.sh`](../provisioning/phoenix-provision.sh);
both read the same steps (`src/plan.js` mirrors the script).

## Use

Published to GitHub Pages by `.github/workflows/control-pages.yml`. Open the
page, connect the Portal with USB-C (ADB enabled), click **Connect device** and
tap **Allow** on the Portal. If `adb` runs on the same computer, run
`adb kill-server` first: only one program can hold the USB connection.

Try it without a device: add `?demo` to the address.

## Develop

```bash
npm install
npm test          # plan unit tests (node:test)
npm run build     # bundles src/ into dist/app.js
npx serve .       # then open http://localhost:3000/?demo
```
