// The Phoenix Home page: everything about the launcher home screen that the
// setting definitions do not cover, kept on the device by PhoenixHomeManager
// and edited here through phoenixHomeGet / phoenixHomeSet. The definitions'
// own rows (home screen, weather location, temperature unit) render above.
import { api, cmd } from './core.js';
import { showToast } from './widgets.js';

const TILE_NAMES = {
  telugu: 'Telugu calendar', kids: 'Kids Portal', photos: 'Photos', school: 'School', apps: 'All apps',
  smart: 'Smart Home', timers: 'Timers', alarms: 'Alarms', store: 'App Store', settings: 'Settings',
  calendar: 'Calendar (Home Assistant)', cameras: 'Cameras',
};
const THEME_NAMES = { ember: 'Ember', ocean: 'Ocean', forest: 'Forest', midnight: 'Midnight', sunset: 'Sunset', graphite: 'Graphite' };

let model = null;

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null) node.setAttribute(k, v);
  }
  for (const c of children) if (c) node.append(c);
  return node;
}

function row(name, desc, control) {
  return el('div', { class: 'row' },
    el('div', { class: 'info' }, el('div', { class: 'name', text: name }), desc ? el('div', { class: 'desc', text: desc }) : null),
    control);
}

function card(title, ...rows) {
  return [el('h2', { class: 'card-title', text: title }), el('div', { class: 'card' }, ...rows)];
}

async function save(patch, what) {
  const r = await cmd('phoenixHomeSet', patch).catch(() => null);
  if (r?.ok) {
    model = r.data;
    showToast({ title: `${what} saved`, kind: 'success' });
    render();
  } else {
    showToast({ title: `Couldn't save ${what.toLowerCase()}`, message: r?.error || '', kind: 'error' });
  }
}

function select(options, value, onChange) {
  const s = el('select', { onchange: () => onChange(s.value) });
  for (const [v, label] of options) {
    const o = el('option', { value: v, text: label });
    if (String(v) === String(value)) o.selected = true;
    s.append(o);
  }
  return s;
}

function checkbox(checked, onChange) {
  const c = el('input', { type: 'checkbox', onchange: () => onChange(c.checked) });
  c.checked = !!checked;
  return c;
}

/* ---- Tiles and look ---- */

function tilesSection() {
  const tiles = model.tiles.map((t) => ({ ...t }));
  const list = el('div');
  const draw = () => {
    list.replaceChildren(...tiles.map((t, i) => {
      const size = (n, max, key) => select(Array.from({ length: max }, (_, k) => [k + 1, `${k + 1}`]), t[key], (v) => { t[key] = Number(v); });
      const up = el('button', { class: 'btn-text', type: 'button', title: 'Move up', text: '↑', onclick: () => { if (i > 0) { [tiles[i - 1], tiles[i]] = [tiles[i], tiles[i - 1]]; draw(); } } });
      const down = el('button', { class: 'btn-text', type: 'button', title: 'Move down', text: '↓', onclick: () => { if (i < tiles.length - 1) { [tiles[i + 1], tiles[i]] = [tiles[i], tiles[i + 1]]; draw(); } } });
      return row(TILE_NAMES[t.id] || t.id, null, el('div', { class: 'phx-tile-controls' },
        el('label', {}, checkbox(!t.hidden, (on) => { t.hidden = !on; }), ' Shown'),
        el('span', { text: ' Width ' }), size(t.w, 6, 'w'),
        el('span', { text: ' Height ' }), size(t.h, 4, 'h'),
        up, down));
    }));
  };
  draw();
  const saveBtn = el('button', {
    class: 'btn-primary', type: 'button', text: 'Save tiles',
    onclick: () => save({
      tiles: tiles.map(({ id, w, h }) => ({ id, w, h })),
      hiddenTiles: tiles.filter((t) => t.hidden).map((t) => t.id),
    }, 'Tiles'),
  });
  const reset = el('button', {
    class: 'btn-ghost', type: 'button', text: 'Reset layout',
    onclick: () => save({
      tiles: ['telugu', 'kids', 'photos', 'school', 'apps', 'smart', 'timers', 'alarms', 'store', 'settings', 'calendar', 'cameras']
        .map((id) => ({ id, w: ['telugu', 'school', 'kids', 'photos'].includes(id) ? 2 : 1, h: ['kids', 'photos'].includes(id) ? 2 : 1 })),
      hiddenTiles: [],
    }, 'Layout'),
  });
  return card('Tiles',
    el('div', { class: 'desc', text: 'Order, size (in grid cells: six columns wide on a landscape Portal) and which tiles show.' }),
    list,
    el('div', { class: 'phx-actions' }, saveBtn, reset));
}

function lookSection() {
  return card('Look',
    row('Theme', 'Colours of the background and the tiles',
      select(model.themes.map((id) => [id, THEME_NAMES[id] || id]), model.theme, (v) => save({ theme: v }, 'Theme'))),
    row('Weather in the background', 'Rain, snow, clouds, sun or stars from the current weather',
      checkbox(model.weatherEffects, (on) => save({ weatherEffects: on }, 'Weather effects'))));
}

/* ---- Apps ---- */

function appsSection() {
  const fav = new Set(model.favorites), kids = new Set(model.kidsApps), hidden = new Set(model.hiddenApps);
  const filter = el('input', { type: 'text', class: 'field', placeholder: 'Search apps' });
  const list = el('div');
  const draw = () => {
    const q = filter.value.trim().toLowerCase();
    list.replaceChildren(...model.apps
      .filter((a) => !q || a.label.toLowerCase().includes(q) || a.package.toLowerCase().includes(q))
      .map((a) => row(a.label, a.package, el('div', { class: 'phx-tile-controls' },
        el('label', {}, checkbox(fav.has(a.package), (on) => (on ? fav.add(a.package) : fav.delete(a.package))), ' Dock'),
        el('label', {}, checkbox(kids.has(a.package), (on) => (on ? kids.add(a.package) : kids.delete(a.package))), ' Kids Portal'),
        el('label', {}, checkbox(hidden.has(a.package), (on) => (on ? hidden.add(a.package) : hidden.delete(a.package))), ' Hidden')))));
    if (!model.apps.length) list.append(el('div', { class: 'desc', text: 'The app list loads once Phoenix Home has started on the Portal.' }));
  };
  filter.addEventListener('input', draw);
  draw();
  return card('Apps',
    el('div', { class: 'desc', text: 'The dock shows the checked apps in order (most used when none are). Kids Portal apps appear under My apps for the kids. Hidden apps leave the app drawer.' }),
    filter, list,
    el('div', { class: 'phx-actions' }, el('button', {
      class: 'btn-primary', type: 'button', text: 'Save apps',
      onclick: () => save({
        favorites: [...model.favorites.filter((p) => fav.has(p)), ...[...fav].filter((p) => !model.favorites.includes(p))],
        kidsApps: [...model.kidsApps.filter((p) => kids.has(p)), ...[...kids].filter((p) => !model.kidsApps.includes(p))],
        hiddenApps: [...hidden],
      }, 'Apps'),
    })));
}

/* ---- School ---- */

function hhmm(v) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(v || '');
  return m ? `${m[1].padStart(2, '0')}:${m[2]}` : '';
}

function schoolSection() {
  const s = { ...model.school, menus: [...(model.school.menus || [])] };
  const name = el('input', { type: 'text', class: 'field', value: s.schoolName || '', placeholder: 'Miller Elementary' });
  const district = el('input', { type: 'text', class: 'field', value: s.district || 'friscoisd', placeholder: 'friscoisd' });
  const calendar = el('input', { type: 'url', class: 'field', value: s.calendar || '', placeholder: 'https://… .ics or webcal://…' });
  const start = el('input', { type: 'time', class: 'field', value: hhmm(s.start) });
  const end = el('input', { type: 'time', class: 'field', value: hhmm(s.end) });
  const picker = el('div');
  const menus = el('div');
  let schools = [];
  const drawMenus = () => {
    const pick = schools.find((x) => x.slug === s.school);
    const offered = pick ? pick.menus : s.menus;
    menus.replaceChildren(...offered.map((m) => el('label', { class: 'phx-chip' },
      checkbox(s.menus.some((x) => x.slug === m.slug), (on) => {
        s.menus = s.menus.filter((x) => x.slug !== m.slug);
        if (on) s.menus.push(m);
      }), ` ${m.name}`)));
  };
  const load = async () => {
    picker.replaceChildren(el('div', { class: 'desc', text: 'Loading schools…' }));
    const r = await cmd('phoenixSchoolList', { district: district.value.trim() }).catch(() => null);
    if (!r?.ok) {
      picker.replaceChildren(el('div', { class: 'desc', text: r?.error || "Couldn't load the schools" }));
      return;
    }
    schools = r.data;
    const sel = select([['', 'Choose a school'], ...schools.map((x) => [x.slug, x.name])], s.school, (v) => {
      const pick = schools.find((x) => x.slug === v);
      s.school = v;
      if (pick) {
        name.value = pick.name;
        s.menus = pick.menus.filter((m) => /breakfast|lunch/.test(m.slug));
        if (!s.menus.length) s.menus = [...pick.menus];
      }
      drawMenus();
    });
    picker.replaceChildren(sel);
    drawMenus();
  };
  drawMenus();
  return card('School',
    row('School name', 'Shown on the School tile and page', name),
    row('District menu site', 'friscoisd for Frisco ISD (friscoisd.nutrislice.com)',
      el('div', { class: 'phx-inline' }, district, el('button', { class: 'btn-ghost', type: 'button', text: 'Load schools', onclick: load }))),
    row('School', s.school ? `Picked: ${s.school}` : 'Pick it for its menus', picker),
    row('Menus', 'Which menus to show', menus),
    row('Calendar link', 'The school or district calendar as iCal (.ics)', calendar),
    row('School starts', null, start),
    row('School ends', null, end),
    el('div', { class: 'phx-actions' }, el('button', {
      class: 'btn-primary', type: 'button', text: 'Save school',
      onclick: () => save({
        school: {
          schoolName: name.value.trim(), district: district.value.trim().toLowerCase(), school: s.school || '',
          menus: s.menus, calendar: calendar.value.trim(), start: start.value.replace(/^0(\d)/, '$1'), end: end.value.replace(/^0(\d)/, '$1'),
        },
      }, 'School'),
    })));
}

/* ---- Photos ---- */

function photosSection() {
  const p = { ...model.photos };
  const folder = el('input', { type: 'url', class: 'field', value: p.folder || '', placeholder: 'http://tower.local:8080/photos/' });
  const seconds = el('input', { type: 'number', class: 'field', min: '4', max: '600', value: String(p.seconds || 12) });
  const source = select([['immich', 'Immich'], ['folder', 'Network folder (http)']], p.source, (v) => { p.source = v; });
  const screensaver = el('input', { type: 'checkbox' });
  return card('Photos',
    row('Source', p.immichConfigured ? 'Immich is set up' : 'Immich server and API key: Screensaver > Immich Media screensaver', source),
    row('Network folder', 'A folder your server lists over http (nginx, Apache, Caddy, rclone serve http). Add a login as http://user:password@host/…', folder),
    row('Seconds per photo', null, seconds),
    row('Use as the screensaver', 'The Phoenix Photo Frame starts after the idle time under Screensaver', screensaver),
    el('div', { class: 'phx-actions' }, el('button', {
      class: 'btn-primary', type: 'button', text: 'Save photos',
      onclick: async () => {
        if (screensaver.checked) {
          await api('/api/settings', { method: 'PATCH', body: JSON.stringify({ 'screensaver.mode': 'phoenix_photos', 'screensaver.enabled': true }) }).catch(() => null);
        }
        await save({ photos: { source: p.source, folder: folder.value.trim(), seconds: Number(seconds.value) || 12 } }, 'Photos');
      },
    })));
}

/* ---- On the Portal now ---- */

function deviceSection() {
  const go = (name, label) => el('button', {
    class: 'btn-ghost', type: 'button', text: label,
    onclick: async () => {
      const r = await cmd(name, {}).catch(() => null);
      showToast({ title: r?.ok ? `${label}: done` : `${label} failed`, message: r?.error || '', kind: r?.ok ? 'success' : 'error' });
    },
  });
  return card('On the Portal now',
    el('div', { class: 'phx-actions' },
      go('openHome', 'Show Phoenix Home'), go('openAllApps', 'Open all apps'), go('openSchool', 'Open School'),
      go('openSmartHome', 'Open Smart Home'), go('openKids', 'Open Kids Portal'), go('startScreensaver', 'Start photo frame / screensaver')));
}

function render() {
  const tab = document.getElementById('tab-phoenix');
  if (!tab || !model) return;
  let host = document.getElementById('phoenix-editor');
  if (!host) {
    host = el('div', { id: 'phoenix-editor' });
    tab.append(host);
  }
  host.replaceChildren(...deviceSection(), ...lookSection(), ...tilesSection(), ...appsSection(), ...schoolSection(), ...photosSection());
}

/** The Phoenix Home tab was opened: read the device's state and draw. */
export async function phoenixShown() {
  const r = await cmd('phoenixHomeGet', {}).catch(() => null);
  if (!r?.ok) {
    const tab = document.getElementById('tab-phoenix');
    if (tab && !document.getElementById('phoenix-editor')) {
      tab.append(el('div', { id: 'phoenix-editor', class: 'desc', text: 'Phoenix Home is not running on this device yet.' }));
    }
    return;
  }
  model = r.data;
  render();
}
