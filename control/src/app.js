// Phoenix Control's page: connect, read the device, show the plan, run it.
import { connect, downloadAsset, latestRelease, webUsbSupported } from './adb.js';
import { DemoDevice } from './demo.js';
import {
  RELEASE_REPO, buildRestorePlan, buildSetupPlan, looksFailed, pickReleaseAsset, profileCommand,
} from './plan.js';

const $ = (id) => document.getElementById(id);
let device = null;
let facts = null;
let apk = null; // { name, blob }
let pending = null; // { kind: 'setup' | 'restore', plan }

function setStatus(text, on) {
  $('statusText').textContent = text;
  $('status').classList.toggle('on', Boolean(on));
}

function show(connected) {
  $('connectView').hidden = connected;
  $('deviceView').hidden = !connected;
}

function renderFacts() {
  const rows = [
    ['Model', facts.model + (facts.isPortal ? ' · Meta Portal' : '')],
    ['Android', `${facts.release} (API ${facts.sdk})`],
    ['CPU', facts.abi],
    ['Phoenix Portal', facts.phoenixVersion
      ? `<span class="pill ok">Installed ${facts.phoenixVersion}</span>`
      : '<span class="pill no">Not installed</span>'],
    ['Home screen', facts.home || '—'],
    ['Wi-Fi address', facts.ip ?? '—'],
  ];
  $('facts').innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('');
  const admin = $('adminLink');
  admin.hidden = !facts.ip || !facts.phoenixVersion;
  if (facts.ip) admin.href = `http://${facts.ip}:2324`;
  for (const b of $('profiles').querySelectorAll('button')) b.disabled = !facts.phoenixVersion;
}

async function refresh() {
  facts = await device.facts();
  renderFacts();
}

async function onConnect() {
  $('connectNote').textContent = 'Waiting for the device… tap Allow on its screen if asked.';
  $('connectBtn').disabled = true;
  try {
    device = new URLSearchParams(location.search).has('demo') ? new DemoDevice() : await connect();
    if (!device) { $('connectNote').textContent = ''; return; }
    setStatus(`Connected · ${device.serial}`, true);
    await refresh();
    show(true);
    $('connectNote').textContent = '';
  } catch (e) {
    $('connectNote').textContent = e.message ?? String(e);
  } finally {
    $('connectBtn').disabled = false;
  }
}

function renderPlan(kind, plan) {
  pending = { kind, plan };
  $('planTitle').textContent = kind === 'setup'
    ? `Setup plan · ${plan.length} steps`
    : `Restore plan · ${plan.length} steps`;
  $('uninstallOpt').hidden = kind !== 'restore';
  $('plan').innerHTML = plan.map((p) => `<li><span class="desc"></span><span class="mark"></span><code></code></li>`).join('');
  [...$('plan').children].forEach((li, i) => {
    li.querySelector('.desc').textContent = plan[i].desc;
    li.querySelector('code').textContent = `adb shell ${plan[i].cmd}`;
  });
  $('applyBtn').disabled = false;
  $('planCard').hidden = false;
  $('planCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function applyPlan() {
  const { plan, kind } = pending;
  $('applyBtn').disabled = true;
  const items = [...$('plan').children];
  let failed = 0;
  for (let i = 0; i < plan.length; i++) {
    const li = items[i];
    li.className = 'run';
    try {
      if (plan[i].install) {
        await device.pushApk(apk.blob, (f) => { li.querySelector('.desc').textContent = `${plan[i].desc} — copying ${Math.round(f * 100)}%`; });
        li.querySelector('.desc').textContent = plan[i].desc;
      }
      const out = await device.shell(plan[i].cmd);
      if (looksFailed(out)) throw new Error(out.trim().split('\n').pop());
      li.className = 'ok';
    } catch (e) {
      li.className = 'fail';
      failed++;
      const msg = document.createElement('span');
      msg.className = 'out';
      msg.textContent = e.message ?? String(e);
      li.append(msg);
    }
  }
  $('planTitle').textContent = failed
    ? `${kind === 'setup' ? 'Setup' : 'Restore'} finished · ${failed} step${failed > 1 ? 's' : ''} need attention`
    : `${kind === 'setup' ? 'Setup' : 'Restore'} complete`;
  if (kind === 'setup') {
    await device.shell('content read --uri content://com.phoenix.portal.update-helper/start | sh').catch(() => {});
  }
  await refresh().catch(() => {});
}

async function useLatest() {
  const btn = $('latestBtn');
  btn.disabled = true;
  $('apkName').textContent = 'Looking up the latest release…';
  try {
    const release = await latestRelease(RELEASE_REPO);
    const asset = pickReleaseAsset(release, facts.abi);
    if (!asset) throw new Error('That release has no APK for this device.');
    $('apkName').textContent = `Downloading ${asset.name}…`;
    try {
      apk = { name: asset.name, blob: await downloadAsset(asset) };
      $('apkName').textContent = `${asset.name} · ${(apk.blob.size / 1e6).toFixed(1)} MB`;
    } catch {
      // GitHub's download redirect isn't open to other sites from every
      // browser: hand over the file instead.
      $('apkName').innerHTML = `Download <a href="${asset.browser_download_url}">${asset.name}</a>, then choose it with “Choose APK file”.`;
    }
  } catch (e) {
    $('apkName').textContent = e.message ?? String(e);
  } finally {
    btn.disabled = false;
  }
}

function wire() {
  const demo = new URLSearchParams(location.search).has('demo');
  if (demo) $('connectBtn').textContent = 'Connect demo Portal+';
  if (!webUsbSupported() && !demo) { $('noUsb').hidden = false; $('connectBtn').disabled = true; }
  $('connectBtn').addEventListener('click', onConnect);
  $('refreshBtn').addEventListener('click', () => refresh());
  $('disconnectBtn').addEventListener('click', async () => {
    await device?.close().catch(() => {});
    device = null;
    setStatus('Not connected', false);
    $('planCard').hidden = true;
    show(false);
  });
  $('apkFile').addEventListener('change', (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    apk = { name: file.name, blob: file };
    $('apkName').textContent = `${file.name} · ${(file.size / 1e6).toFixed(1)} MB`;
  });
  $('latestBtn').addEventListener('click', useLatest);
  $('planBtn').addEventListener('click', () => {
    if (!apk) { $('apkName').textContent = 'Choose an APK first (latest release or a file).'; return; }
    renderPlan('setup', buildSetupPlan(facts, {
      setHome: $('optHome').checked,
      blockOta: $('optOta').checked,
      apkName: apk.name,
    }));
  });
  $('restoreBtn').addEventListener('click', () => renderPlan('restore', buildRestorePlan(facts, { uninstall: $('optUninstall').checked })));
  $('optUninstall').addEventListener('change', () => renderPlan('restore', buildRestorePlan(facts, { uninstall: $('optUninstall').checked })));
  $('applyBtn').addEventListener('click', applyPlan);
  $('cancelPlanBtn').addEventListener('click', () => { $('planCard').hidden = true; pending = null; });
  $('profiles').addEventListener('click', async (e) => {
    const profile = e.target.closest('button')?.dataset.profile;
    if (!profile) return;
    await device.shell(profileCommand(profile));
    for (const b of $('profiles').querySelectorAll('button')) b.classList.toggle('on', b.dataset.profile === profile);
  });
  $('shotBtn').addEventListener('click', async () => {
    const img = $('shot');
    const blob = await device.screenshot();
    if (img.src) URL.revokeObjectURL(img.src);
    img.src = URL.createObjectURL(blob);
    img.hidden = false;
  });
  $('rebootBtn').addEventListener('click', async () => {
    if (!confirm('Reboot the device?')) return;
    await device.reboot().catch(() => {});
    setStatus('Rebooting… reconnect when it is back', false);
    show(false);
  });
}

wire();
