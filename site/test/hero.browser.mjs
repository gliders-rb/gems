// The hero stepper's behaviour in a real browser: autoplay, the reader taking over, keys, visibility, reduced motion
// and scripts off. Run with `npm run test:hero-browser` (it builds the site first) or, after a build,
// `node --test test/hero.browser.mjs`. Needs Playwright's headless Chromium. Not part of check:hero: the fast lane
// has no browser.
//
// Timers run on Playwright's fake clock, so a 6 s hold takes no time. CSS transitions and intersection reports
// still run in real time, so the tests wait briefly in real time after a scroll.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const dist = resolve(fileURLToPath(new URL('../dist', import.meta.url)));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };

// A small static server for dist/, so the test needs nothing else running.
async function file(path) {
  const full = join(dist, decodeURIComponent(path));
  if (!full.startsWith(dist)) return null;
  const info = await stat(full).catch(() => null);
  if (info?.isFile()) return full;
  if (info?.isDirectory()) return file(join(path, 'index.html'));
  return null;
}

let server;
let base;
let browser;

before(async () => {
  server = createServer(async (req, res) => {
    const found = await file(new URL(req.url, 'http://x').pathname);
    if (!found) return res.writeHead(404).end();
    res.writeHead(200, { 'content-type': types[extname(found)] ?? 'application/octet-stream' });
    res.end(await readFile(found));
  });
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  base = `http://127.0.0.1:${server.address().port}/`;
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  await new Promise((ok) => server.close(ok));
});

async function home(t, { width = 1440, height = 900, clock = true, ...options } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height }, reducedMotion: 'no-preference', ...options });
  t.after(() => ctx.close());
  const page = await ctx.newPage();
  if (clock) await page.clock.install();
  await page.goto(base, { waitUntil: 'networkidle' });
  return page;
}

const step = (page) => page.locator('[data-hx]').getAttribute('data-step');
const current = (page) => page.locator('.hx-step[aria-current="step"]').innerText();
const scroll = async (page, y) => {
  await page.evaluate((top) => window.scrollTo(0, top), y);
  await page.waitForTimeout(300); // the intersection report arrives in real time
};

test('in view, autoplay walks the steps, holds the last, and rests there after three rounds', async (t) => {
  const page = await home(t);
  await page.clock.runFor(100);
  assert.equal(await step(page), '1', 'starts at step 1 once in view');
  await page.clock.runFor(3100);
  assert.equal(await step(page), '2', 'advances after the dwell');
  assert.equal(await current(page), '2', 'aria-current follows');
  await page.clock.runFor(4000 * 3 + 100);
  assert.equal(await step(page), '5', 'reaches the last step');
  await page.clock.runFor(6100);
  assert.equal(await step(page), '1', 'holds about 6 s, then round two');
  await page.clock.runFor((15 + 6) * 1000 * 2 + 500);
  assert.equal(await step(page), '5', 'after three rounds, the last step');
  await page.clock.runFor(30000);
  assert.equal(await step(page), '5', 'and it stays');
  assert.equal(await page.locator('.hx-play').getAttribute('aria-label'), 'Play autoplay');
});

test('the reader drives: a step, the keys and the play button', async (t) => {
  const page = await home(t);
  await page.clock.runFor(100);
  await page.locator('.hx-step[data-to="3"]').click();
  assert.equal(await step(page), '3');
  assert.match(await page.locator('.hx-live').innerText(), /fail!/, 'the live caption announces the step');
  await page.clock.runFor(20000);
  assert.equal(await step(page), '3', 'autoplay stays stopped');
  await page.locator('.hx-next').focus();
  await page.keyboard.press('ArrowLeft');
  assert.equal(await step(page), '2');
  await page.keyboard.press('End');
  assert.equal(await step(page), '5');
  assert.ok(await page.locator('.hx-next').isDisabled(), 'next is disabled on the last step');
  await page.locator('.hx-play').click();
  assert.equal(await step(page), '1', 'play from the last step starts again at 1');
  await page.clock.runFor(3100);
  assert.equal(await step(page), '2', 'play resumes autoplay');
  await page.locator('.hx-play').click();
  await page.clock.runFor(20000);
  assert.equal(await step(page), '2', 'pause holds');
});

test('autoplay pauses out of view and resumes back in view', async (t) => {
  const page = await home(t);
  await page.clock.runFor(100);
  await scroll(page, 2000);
  await page.clock.runFor(500);
  const away = await step(page);
  await page.clock.runFor(20000);
  assert.equal(await step(page), away, 'paused while scrolled away');
  await scroll(page, 0);
  await page.clock.runFor(4300);
  assert.notEqual(await step(page), away, 'resumed');
});

test('on a phone with the figure below the fold, it stays on the finished picture', async (t) => {
  const page = await home(t, { width: 390, height: 600 });
  await page.clock.runFor(10000);
  assert.equal(await step(page), '5');
});

test('reduced motion: no autoplay and no play button, but the steps work, instantly', async (t) => {
  const page = await home(t, { reducedMotion: 'reduce' });
  await page.clock.runFor(20000);
  assert.equal(await step(page), '5');
  assert.ok(await page.locator('.hx-play').isHidden());
  await page.locator('.hx-step[data-to="2"]').click();
  assert.equal(await step(page), '2');
  assert.equal(await page.locator('.hx-a2').evaluate((e) => getComputedStyle(e).transitionDuration), '0s');
});

test('scripts off: the finished picture and no controls', async (t) => {
  const page = await home(t, { clock: false, javaScriptEnabled: false });
  assert.ok(await page.locator('.hx-steps').isHidden());
  assert.equal(await step(page), null);
  const shown = await page.locator('.hx-result').evaluateAll((els) => els.map((e) => getComputedStyle(e).opacity));
  assert.deepEqual(shown, ['1', '1', '1']);
});
