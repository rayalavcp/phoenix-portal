// The Phoenix Home page: everything about the launcher home screen that the
// setting definitions do not cover, kept on the device by PhoenixHomeManager
// and edited here through phoenixHomeGet / phoenixHomeSet. The definitions'
// own rows (home screen, weather location, temperature unit) render above.
import { api, cmd } from './core.js';
import { showToast } from './widgets.js';
import { openDrawerItemsPicker } from './drawer_items.js';

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
  const camera = el('input', { type: 'text', class: 'field', value: (model.cameras || (model.camera ? [model.camera] : [])).join(', '), placeholder: 'camera.front_door, camera.driveway' });
  const bell = model.doorbell || {};
  const trigger = el('input', { type: 'text', class: 'field', value: bell.trigger || '', placeholder: 'binary_sensor.front_door_ding' });
  const bellSecs = el('input', { type: 'number', class: 'field', min: '10', max: '300', value: String(bell.seconds || 30) });
  const wallLink = el('input', { type: 'url', class: 'field', value: (model.wallpaperUrl || '').startsWith('/th?') ? '' : (model.wallpaperUrl || ''), placeholder: 'http://tower/wallpapers/lake.jpg' });
  const haPage = el('input', { type: 'url', class: 'field', value: model.smartHomePage || '', placeholder: 'http://homeassistant.local:8123/lovelace/home' });
  const glass = el('input', { type: 'range', min: '0', max: '100', step: '5', value: String(Math.round((model.glass ?? 0.35) * 100)) });
  glass.addEventListener('change', () => save({ glass: Number(glass.value) / 100 }, 'Glass'));
  return card('Look',
    row('Home layout', 'Today: glass cards over the photo of the day. Tiles: the resizable tile grid.',
      select([['today', 'Today (recommended)'], ['tiles', 'Tiles']], model.layout || 'today', (v) => save({ layout: v }, 'Layout'))),
    row('Wallpaper', 'A built-in 4K photo, all of them rotating, Bing 4K, your photos, a link or plain colours',
      select([['builtin', 'All photos, rotating'], ...(model.wallpapers || []).map((w) => [w.id, w.name]),
        ['bing', 'Bing 4K, rotating'], ['photos', 'My photos (Immich or folder)'], ['url', 'Image link'], ['theme', 'Colours only']],
      model.wallpaper || 'builtin', (v) => save({ wallpaper: v }, 'Wallpaper'))),
    row('Wallpaper link', 'Used when the wallpaper is Image link',
      el('div', { class: 'phx-inline' }, wallLink,
        el('button', { class: 'btn-ghost', type: 'button', text: 'Save', onclick: () => save({ wallpaper: 'url', wallpaperUrl: wallLink.value.trim() }, 'Wallpaper link') }))),
    row('Glass', 'How see-through the cards and tiles are (0 clear, 100 frosted)', glass),
    row('Smart Home button', 'Open your Home Assistant dashboard, or Phoenix\'s own controls',
      select([['ha', 'Home Assistant dashboard'], ['phoenix', 'Phoenix controls']], model.smartHome || 'ha', (v) => save({ smartHome: v }, 'Smart Home button'))),
    row('Home Assistant page', 'The page the Smart Home button opens (your dashboard or HTML page)',
      el('div', { class: 'phx-inline' }, haPage,
        el('button', { class: 'btn-ghost', type: 'button', text: 'Save', onclick: () => save({ smartHomePage: haPage.value.trim() }, 'Home Assistant page') }))),
    row('Cameras', 'Home Assistant cameras on the Today screen, live, in order (doorbell first). Swipe across the card to switch.',
      el('div', { class: 'phx-inline' }, camera,
        el('button', { class: 'btn-ghost', type: 'button', text: 'Save', onclick: () => save({ cameras: camera.value.split(/[\s,]+/).filter(Boolean) }, 'Cameras') }))),
    row('Doorbell', 'When this Home Assistant entity rings, the screen wakes and shows the first camera live',
      el('div', { class: 'phx-inline' }, trigger, bellSecs, el('span', { class: 'desc', text: 'seconds' }),
        el('button', { class: 'btn-ghost', type: 'button', text: 'Save', onclick: () => save({ doorbell: { trigger: trigger.value.trim(), seconds: Number(bellSecs.value) || 30 } }, 'Doorbell') }),
        el('button', { class: 'btn-ghost', type: 'button', text: 'Test', onclick: async () => {
          const r = await cmd('phoenixDoorbell', {}).catch(() => null);
          showToast(r?.ok ? { title: 'Doorbell shown on the Portal', kind: 'success' } : { title: "Couldn't show the doorbell", message: r?.error || '', kind: 'error' });
        } }))),
    row('Menu items', 'What the menu shows when it slides in from the left, and in what order',
      el('button', { class: 'btn-ghost', type: 'button', text: 'Choose menu items…', onclick: async () => {
        const picked = await openDrawerItemsPicker(model.menuItems || '', true);
        if (picked == null) return;
        const r = await api('/api/settings', { method: 'PATCH', body: JSON.stringify({ 'ui.drawer_items': picked }) }).catch(() => null);
        if (r?.ok) { model.menuItems = picked; showToast({ title: 'Menu items saved', kind: 'success' }); }
        else showToast({ title: "Couldn't save the menu items", kind: 'error' });
      } })),
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
  let provider = s.provider || 'schoolcafe';
  const schoolId = el('input', { type: 'text', class: 'field', value: provider === 'schoolcafe' ? (s.school || '') : '', placeholder: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' });
  const line = el('input', { type: 'text', class: 'field', value: s.servingLine && s.servingLine !== 'auto' ? s.servingLine : '', placeholder: 'Found automatically' });
  const grade = el('input', { type: 'text', class: 'field', value: s.grade || '02', placeholder: '02' });
  const calendar = el('input', { type: 'text', class: 'field', value: s.calendar || '', placeholder: 'calendar.frisco_isd or https://… .ics' });
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
    const r = await cmd('phoenixSchoolList', { district: district.value.trim(), provider }).catch(() => null);
    if (!r?.ok) {
      picker.replaceChildren(el('div', { class: 'desc', text: r?.error || "Couldn't load the schools" }));
      return;
    }
    schools = r.data;
    const sel = select([['', 'Choose a school'], ...schools.map((x) => [x.slug, x.name])], s.school, (v) => {
      const pick = schools.find((x) => x.slug === v);
      s.school = v;
      if (provider === 'schoolcafe') schoolId.value = v;
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
    row('Menu source', 'Frisco ISD posts its menus on SchoolCafe',
      select([['schoolcafe', 'SchoolCafe (Frisco ISD)'], ['nutrislice', 'Nutrislice']], provider, (v) => { provider = v; })),
    row('SchoolCafe school ID', 'The school\'s ID from SchoolCafe (the same one your Home Assistant SchoolCafe setup uses)', schoolId),
    row('Serving line', 'Leave empty: found automatically (Frisco ISD: Main (Trayline) and Hot Breakfast)', line),
    row('Grade', 'Two digits, e.g. 02 for 2nd grade', grade),
    row('District', 'friscoisd for Frisco ISD',
      el('div', { class: 'phx-inline' }, district, el('button', { class: 'btn-ghost', type: 'button', text: 'Load schools', onclick: load }))),
    row('School', s.school ? `Picked: ${s.school}` : 'Pick it for its menus', picker),
    row('Menus', 'Which menus to show', menus),
    row('School calendar', 'A Home Assistant calendar (calendar.frisco_isd) or an iCal (.ics) link', calendar),
    row('School starts', null, start),
    row('School ends', null, end),
    el('div', { class: 'phx-actions' }, el('button', {
      class: 'btn-primary', type: 'button', text: 'Save school',
      onclick: () => save({
        school: {
          provider, servingLine: line.value.trim() || 'auto', grade: grade.value.trim() || '02',
          schoolName: name.value.trim(), district: district.value.trim().toLowerCase(),
          school: provider === 'schoolcafe' ? schoolId.value.trim() : (s.school || ''),
          menus: s.menus, calendar: calendar.value.trim(), start: start.value.replace(/^0(\d)/, '$1'), end: end.value.replace(/^0(\d)/, '$1'),
        },
      }, 'School'),
    })));
}

/* ---- Kids Portal ---- */

const KIDS_GAMES = [
  ['Learn', [['math', 'Math Blitz'], ['times', 'Times Tables'], ['clock', 'Telling the Time'], ['flags', 'Flag Quiz'], ['words', 'Word Scramble'],
    ['patterns', 'Patterns'], ['fractions', 'Fractions'], ['money', 'Money'], ['science', 'Science'], ['spelling', 'Spelling'], ['opposites', 'Opposites']]],
  ['Puzzles', [['sudoku', 'Sudoku'], ['maze', 'Maze'], ['wordsearch', 'Word Search'], ['guess', 'Word Guess'], ['memory', 'Memory Pro'], ['g2048', '2048'], ['lights', 'Lights Out']]],
  ['Play', [['snake', 'Snake'], ['mole', 'Whack-a-Mole'], ['simon', 'Simon Says'], ['ttt', 'Tic-Tac-Toe'], ['connect4', 'Connect Four']]],
  ['Arcade', [['munch', 'Munch Maze'], ['bricks', 'Brick Bash']]],
  ['Move (camera)', [['blaster', 'Space Blaster'], ['bubbles', 'Bubble Pop'], ['catcher', 'Fruit Catcher'], ['fingermath', 'Finger Math']]],
  ['Create', [['draw', 'Draw Studio'], ['pixel', 'Pixel Paint'], ['piano', 'Piano']]],
];

function kidsSection() {
  const k = model.kids || {};
  const name = el('input', { type: 'text', class: 'field', value: k.name || '', placeholder: 'Leave empty for "Hi there!"' });
  const pin = el('input', { type: 'password', class: 'field', inputmode: 'numeric', placeholder: k.hasPin ? 'A PIN is set: type a new one, or leave empty' : 'No PIN: leaving is a 3-second press' });
  const minutes = select([['0', 'No limit'], ['15', '15 minutes'], ['30', '30 minutes'], ['45', '45 minutes'], ['60', '1 hour'], ['90', '1.5 hours'], ['120', '2 hours'], ['180', '3 hours']],
    k.minutes || '90', (v) => save({ kids: { minutes: v } }, 'Daily screen time'));
  const bedtime = select([['', 'Off'], ...['19:00', '19:30', '20:00', '20:30', '21:00', '21:30', '22:00'].map((t) => [t, t])],
    k.bedtime || '', (v) => save({ kids: { bedtime: v } }, 'Bedtime'));
  const wake = select(['06:00', '06:30', '07:00', '07:30', '08:00'].map((t) => [t, t]), k.wake || '07:00', (v) => save({ kids: { wake: v } }, 'Wake-up time'));
  const hidden = new Set(k.hiddenGames || []);
  const games = el('div', {}, ...KIDS_GAMES.map(([shelf, list]) => el('div', { class: 'phx-kids-shelf' },
    el('div', { class: 'desc', text: shelf }),
    el('div', { class: 'phx-inline phx-wrap' }, ...list.map(([id, title]) => el('label', { class: 'phx-chip' },
      checkbox(!hidden.has(id), (on) => { if (on) hidden.delete(id); else hidden.add(id); }), ` ${title}`))))));
  const profiles = el('div', { class: 'phx-inline' }, ...[['family', 'Family'], ['kids', 'Kids (locked)'], ['night', 'Night']].map(([id, label]) =>
    el('button', {
      class: (k.profile || 'family') === id ? 'btn-primary' : 'btn-ghost', type: 'button', text: label,
      onclick: async () => {
        const r = await cmd('setProfile', { profile: id }).catch(() => null);
        showToast(r?.ok ? { title: `Profile: ${label}`, kind: 'success' } : { title: "Couldn't change the profile", message: r?.error || '', kind: 'error' });
        if (r?.ok) { model.kids = { ...k, profile: id }; render(); }
      },
    })));
  return card('Kids Portal',
    row('Profile now', 'Family: everything. Kids: the Portal stays on the Kids Portal until a parent unlocks it. Night: the bedtime screen.', profiles),
    row('Kids Portal in the menu', 'Show the Kids Portal button on the home screen and in the menu',
      checkbox(k.enabled !== false, (on) => save({ kids: { enabled: on } }, 'Kids Portal'))),
    row("Child's name", 'Used in the greeting',
      el('div', { class: 'phx-inline' }, name, el('button', { class: 'btn-ghost', type: 'button', text: 'Save', onclick: () => save({ kids: { name: name.value.trim() } }, "Child's name") }))),
    row('Daily screen time', 'When it runs out, an all-done screen shows until tomorrow', minutes),
    row('Bedtime', 'From bedtime until wake-up the Kids Portal shows the bedtime screen', bedtime),
    row('Wake-up time', null, wake),
    row('Parent PIN', 'Asked to leave the Kids Portal or add time. Digits only.',
      el('div', { class: 'phx-inline' }, pin,
        el('button', { class: 'btn-ghost', type: 'button', text: 'Save PIN', onclick: () => {
          const v = pin.value.trim();
          if (v && !/^\d{4,8}$/.test(v)) { showToast({ title: 'Use 4 to 8 digits', kind: 'error' }); return; }
          save({ kids: { pin: v } }, v ? 'Parent PIN' : 'PIN removed');
          pin.value = '';
        } }))),
    row('Activities shown', 'Untick an activity to hide it from the Kids Portal', games),
    el('div', { class: 'phx-actions' },
      el('button', { class: 'btn-primary', type: 'button', text: 'Save activities', onclick: () => save({ kids: { hiddenGames: [...hidden] } }, 'Activities') }),
      el('button', { class: 'btn-ghost', type: 'button', text: 'Reset stars and best scores', onclick: () => {
        if (confirm('Clear every best score, today\'s stars and the daily challenge?')) save({ kids: { resetScores: true } }, 'Scores reset');
      } })));
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
  host.replaceChildren(...deviceSection(), ...lookSection(), ...tilesSection(), ...appsSection(), ...kidsSection(), ...schoolSection(), ...photosSection());
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
