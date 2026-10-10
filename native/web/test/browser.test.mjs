// End-to-end: real Chromium renders Elpian content through the web host.
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { serve } from './server.mjs';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch {
  playwright = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
}

const here = new URL('.', import.meta.url).pathname;
const shots = join(here, 'screenshots');
mkdirSync(shots, { recursive: true });
let server, url, browser, page;
const logs = [];

before(async () => {
  ({ server, url } = await serve());
  browser = await playwright.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  page = await browser.newPage({ viewport: { width: 1300, height: 700 }, deviceScaleFactor: 1 });
  page.on('console', (m) => logs.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`pageerror: ${e.message}`));
  await page.goto(`${url}/test/page.html`);
  await page.waitForFunction(() => window.__ready === true);
});

after(async () => {
  if (logs.length) console.log(logs.join('\n'));
  await browser?.close();
  server?.close();
});

const settle = () => page.waitForTimeout(400);

test('JSON view: Flutter + HTML widgets, CSS, icons, canvas', async () => {
  await page.evaluate(async () => {
    const view = {
      type: 'Column',
      props: { style: { padding: 16, gap: 12, backgroundColor: '#fafafa' } },
      children: [
        { type: 'h1', props: { text: 'Hello Elpian', style: { color: '#3247d6' } } },
        { type: 'p', children: [{ type: 'span', props: { text: 'Inline ' } }, { type: 'strong', props: { text: 'bold' } }, { type: 'em', props: { text: ' and italic' } }] },
        { type: 'Row', props: { style: { gap: 8 } }, children: [
          { type: 'Icon', props: { icon: 'favorite', size: 32, style: { color: '#e91e63' } } },
          { type: 'Button', key: 'btn', props: { text: 'Press' }, events: { click: 'noop' } },
          { type: 'Checkbox', props: { value: true } },
        ] },
        { type: 'Container', props: { style: { width: 200, height: 60, borderRadius: 12, background: 'linear-gradient(90deg, #ff9800, #e91e63)', boxShadow: '0 4px 12px rgba(0,0,0,0.3)' } } },
        { type: 'input', props: { placeholder: 'Type here', name: 'q' } },
        { type: 'Canvas', props: { width: 200, height: 80, commands: [
          { type: 'setFillStyle', params: { color: '#4caf50' } },
          { type: 'fillRect', params: { x: 0, y: 0, width: 100, height: 80 } },
          { type: 'setFillStyle', params: { color: '#2196f3' } },
          { type: 'fillPolygon', params: { points: [[110, 70], [150, 10], [190, 70]] } },
        ] } },
        { type: 'table', children: [
          { type: 'tr', children: [{ type: 'th', props: { text: 'A' } }, { type: 'th', props: { text: 'B' } }] },
          { type: 'tr', children: [{ type: 'td', props: { text: '1' } }, { type: 'td', props: { text: '2' } }] },
        ] },
      ],
    };
    window.jsonSession = await window.__elpian.mountElpian(document.getElementById('json'), 'json', { view });
  });
  await settle();
  const texts = await page.$$eval('#json span', (s) => s.map((e) => e.textContent));
  assert.ok(texts.includes('Hello Elpian'), 'heading rendered');
  assert.ok(texts.includes('bold'), 'inline span rendered');
  assert.ok(texts.includes('Press'), 'button label rendered');
  assert.equal(await page.$$eval('#json input[type=checkbox]', (e) => e.length), 1);
  assert.equal(await page.$$eval('#json input[placeholder="Type here"]', (e) => e.length), 1);
  const pixel = await page.$eval('#json canvas', (c) => Array.from(c.getContext('2d').getImageData(10, 10, 1, 1).data));
  assert.deepEqual(pixel.slice(0, 3), [0x4c, 0xaf, 0x50], 'canvas painted');
  const heading = await page.$eval('#json span', (s) => s.getBoundingClientRect().width);
  assert.ok(heading > 50, 'text has width');
  await page.locator('#json').screenshot({ path: join(shots, 'json.png') });
});

test('QuickJS mini app renders and handles taps', async () => {
  const code = readFileSync(new URL('./counter.qjs.js', import.meta.url), 'utf8');
  await page.evaluate(async (code) => {
    const s = await window.__elpian.mountElpian(document.getElementById('qjs'), 'miniapp', { runtime: 'quickjs', code, machineId: 'qjs-counter' });
    window.qjsPrints = [];
    s.on('println', (m) => window.qjsPrints.push(m));
    s.on('error', (m) => window.qjsPrints.push('ERROR ' + m));
  }, code);
  await page.waitForFunction(() => [...document.querySelectorAll('#qjs span')].some((s) => s.textContent.includes('Current value: 0')), null, { timeout: 15000 });
  await page.locator('#qjs span', { hasText: 'Increment in-card' }).click();
  await page.waitForFunction(() => [...document.querySelectorAll('#qjs span')].some((s) => s.textContent.includes('Current value: 1')), null, { timeout: 5000 });
  const prints = await page.evaluate(() => window.qjsPrints);
  assert.ok(prints.some((p) => p.includes('Count changed to 1')), JSON.stringify(prints));
  await page.locator('#qjs').screenshot({ path: join(shots, 'quickjs.png') });
});

test('Elpian VM (wasm) mini app renders and handles taps', async () => {
  const ast = readFileSync(new URL('./counter.ast.json', import.meta.url), 'utf8');
  await page.evaluate(async (ast) => {
    window.vmErrors = [];
    const s = await window.__elpian.mountElpian(document.getElementById('vm'), 'miniapp', { runtime: 'elpian', astJson: ast, machineId: 'vm-counter' });
    s.on('error', (m) => window.vmErrors.push(m));
  }, ast);
  await page.waitForFunction(() => [...document.querySelectorAll('#vm span')].some((s) => /Count: 0/.test(s.textContent)) || window.vmErrors.length, null, { timeout: 15000 });
  assert.deepEqual(await page.evaluate(() => window.vmErrors), []);
  await page.locator('#vm span', { hasText: 'Increment in-card' }).click();
  await page.waitForFunction(() => [...document.querySelectorAll('#vm span')].some((s) => /Count: 1/.test(s.textContent)), null, { timeout: 5000 });
  await page.locator('#vm').screenshot({ path: join(shots, 'vm.png') });
});

test('A2UI agent session: NDJSON stream, two-way binding, action POST, data model update', async () => {
  await page.evaluate(async () => {
    window.agentEvents = [];
    const s = await window.__elpian.mountElpian(document.getElementById('agent'), 'agent', { baseUrl: location.origin, appId: 'demo', agent: 'assistant', prompt: 'start', chat: true });
    for (const e of ['a2uiText', 'a2uiAction', 'error', 'done']) s.on(e, (p) => window.agentEvents.push([e, p]));
    window.agentSession = s;
  });
  await page.waitForFunction(() => [...document.querySelectorAll('#agent span')].some((s) => s.textContent === 'Please fill in the form.'), null, { timeout: 10000 });
  // The surface's field comes first; the chat input is last.
  const input = page.locator('#agent input').first();
  assert.ok(await page.locator('#agent span', { hasText: 'Sign up' }).count(), 'surface rendered');
  assert.ok(await page.locator('#agent span', { hasText: 'Test Agent' }).count(), 'attribution header');
  assert.ok(await page.locator('#agent span', { hasText: 'Please fill in the form.' }).count(), 'agent prose');
  await input.fill('Ada Lovelace');
  await settle();
  const before = Date.now();
  await page.locator('#agent span', { hasText: 'Submit' }).click();
  await page.waitForFunction(() => [...document.querySelectorAll('#agent span')].some((s) => s.textContent.includes('Thanks, Ada Lovelace!')), null, { timeout: 10000 });
  const requests = await (await fetch(`${url}/__agent/requests`)).json();
  assert.equal(requests.length, 2);
  assert.equal(requests[0].message, 'start');
  assert.deepEqual(requests[0].capabilities.supportedCatalogIds, ['https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json']);
  const second = requests[1];
  assert.equal(second.conversationId, 'conv-test');
  assert.equal(second.action.name, 'submitForm');
  assert.equal(second.action.surfaceId, 'form');
  assert.equal(second.action.sourceComponentId, 'submit');
  assert.deepEqual(second.action.context, { name: 'Ada Lovelace', plan: 'pro' });
  const ts = Date.parse(second.action.timestamp);
  assert.ok(Math.abs(ts - before) < 60000, second.action.timestamp);
  assert.deepEqual(second.dataModel, { version: 'v0.9.1', surfaces: { form: { form: { name: 'Ada Lovelace' } } } });
  const events = await page.evaluate(() => window.agentEvents);
  assert.ok(events.some(([e, p]) => e === 'a2uiAction' && p.name === 'submitForm'), JSON.stringify(events));
  assert.ok(events.some(([e, p]) => e === 'a2uiText' && p.text === 'Submitted.'), JSON.stringify(events));
  assert.ok(events.filter(([e]) => e === 'done').length >= 2);
  const inputs = await page.$$eval('#agent input', (els) => els.map((e) => [e.placeholder, JSON.stringify(e.getBoundingClientRect())]));
  assert.equal(inputs.length, 2, JSON.stringify(inputs));
  const conv = await page.evaluate(() => window.agentSession.call('conversation'));
  assert.equal(conv.conversationId, 'conv-test');
  await page.locator('#agent').screenshot({ path: join(shots, 'a2ui-agent.png') });
});

test('A2UISurface widget renders static messages', async () => {
  const messages = JSON.parse(readFileSync(new URL('../../../a2ui/spec/catalogs/basic/examples/05_product-card.json', import.meta.url), 'utf8')).messages;
  await page.evaluate(async (messages) => {
    await window.__elpian.mountElpian(document.getElementById('static'), 'json', { view: { type: 'Column', children: [{ type: 'h3', props: { text: 'Static A2UI' } }, { type: 'a2ui-surface', props: { messages } }] } });
  }, messages);
  await settle();
  const texts = await page.$$eval('#static span', (s) => s.map((e) => e.textContent));
  assert.ok(texts.includes('Static A2UI'));
  assert.ok(texts.length > 3, texts.join('|'));
  await page.locator('#static').screenshot({ path: join(shots, 'a2ui-static.png') });
});
