import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// The admin boots by translating the footer: an element it looks for but the
// page no longer has throws, the boot stops before the login token is
// attached, and the page spins forever on 401s. Keep the two in step.
const html = readFileSync(new URL('../remote-ui/index.html', import.meta.url), 'utf8');
const localization = readFileSync(new URL('../remote-ui/static/localization.js', import.meta.url), 'utf8');

test('every footer element the translation writes to exists in the page', () => {
  const footer = localization.slice(localization.indexOf('function localizeFooter'));
  const body = footer.slice(0, footer.indexOf('\n}\n'));
  const selectors = [...body.matchAll(/document\.querySelector\('([^']+)'\)/g)].map((m) => m[1]);
  assert.ok(selectors.length > 0, 'localizeFooter reads the footer');
  for (const selector of selectors) {
    // Only the simple shapes this page uses: ".class" and ".class > tag".
    const [outer, inner] = selector.split('>').map((s) => s.trim());
    const cls = outer.replace(/^\./, '');
    const at = html.indexOf(`class="${cls}"`);
    assert.ok(at >= 0, `index.html has ${outer}`);
    if (inner) {
      const block = html.slice(at, html.indexOf('</div>', at));
      assert.ok(block.includes(`<${inner}`), `index.html has ${selector}`);
    }
  }
});

test('the footer translation does not write through a missing element', () => {
  assert.doesNotMatch(localization, /querySelector\([^)]*\)\.textContent\s*=/,
    'write through a null check, or the boot dies when the element goes');
});
