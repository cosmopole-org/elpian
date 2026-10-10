#!/usr/bin/env node
/**
 * End to end: an agentic mini app on the native web renderer.
 *
 *   elpian create <tmp>/shop --template agentic --renderer native
 *   elpian run install && ELPIAN_AGENT_PROVIDER=scripted elpian run dev
 *
 * then, in Chromium: the static UI renders; the A2UISurface's prompt reaches the
 * agent, which calls the app's `listProducts` server function and answers with
 * A2UI; clicking a product's Order button sends an A2UI action whose context is
 * resolved from the template item; the agent's updateDataModel re-renders the
 * surface; static Elpian UI keeps working beside it.
 *
 * Needs: cargo, node, and Playwright with Chromium (npm i -g playwright).
 * Usage: node scripts/e2e-agentic.mjs [--port 4199]
 */
import { execFileSync, execSync, spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.argv[process.argv.indexOf('--port') + 1]) || 4199;
const require = createRequire(import.meta.url);
let pw;
try {
  pw = require('playwright');
} catch {
  pw = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
}

const fail = (message) => {
  console.error(`e2e-agentic: FAIL — ${message}`);
  process.exitCode = 1;
};

execFileSync('cargo', ['build', '--quiet'], { cwd: join(repo, 'cli'), stdio: 'inherit' });
const elpian = join(repo, 'cli', 'target', 'debug', 'elpian');
const work = mkdtempSync(join(tmpdir(), 'elpian-e2e-'));
const app = join(work, 'shop');
execFileSync(elpian, ['create', app, '--template', 'agentic', '--renderer', 'native'], { stdio: 'inherit' });
execFileSync(elpian, ['run', 'install'], { cwd: app, stdio: 'inherit' });

const dev = spawn(elpian, ['run', 'dev', '--port', String(port)], {
  cwd: app,
  env: { ...process.env, ELPIAN_AGENT_PROVIDER: 'scripted' },
  stdio: ['ignore', 'inherit', 'inherit'],
  detached: true,
});
const stop = () => {
  try {
    process.kill(-dev.pid, 'SIGTERM');
  } catch {
    /* already gone */
  }
};
process.on('exit', stop);

try {
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; ; i++) {
    try {
      if ((await fetch(`${base}/health`)).ok) break;
    } catch {
      /* not up yet */
    }
    if (i > 600) throw new Error('dev server did not start');
    await new Promise((r) => setTimeout(r, 1000));
  }

  const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const page = await browser.newPage({ viewport: { width: 900, height: 1100 } });
  const errors = [];
  const posts = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('request', (r) => {
    if (r.method() === 'POST' && r.url().includes('/agent/')) posts.push(JSON.parse(r.postData() || '{}'));
  });
  const text = () => page.evaluate(() => document.getElementById('app').innerText);
  const tap = async (label, nth = 0) => {
    const box = await page.getByText(label, { exact: true }).nth(nth).boundingBox();
    if (!box) throw new Error(`no "${label}" on screen`);
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  };
  const waitFor = async (pattern) => {
    for (let i = 0; i < 100; i++) {
      if (pattern.test(await text())) return;
      await page.waitForTimeout(100);
    }
    throw new Error(`timed out waiting for ${pattern}; screen:\n${await text()}`);
  };

  await page.goto(`${base}/`);
  await waitFor(/Tea & Coffee/);
  await waitFor(/Last order: nothing yet/);
  for (const name of ['Sencha', 'Assam', 'Espresso blend', 'Filter roast']) {
    if (!(await text()).includes(name)) fail(`product ${name} missing`);
  }
  if (posts[0]?.message !== 'Show me what you have.') fail(`first agent request was ${JSON.stringify(posts[0])}`);

  await tap('Order', 1); // Assam
  await waitFor(/Last order: Assam/);
  await waitFor(/Ordered Assam/);
  const action = posts[1]?.action;
  if (!action || action.name !== 'order' || action.surfaceId !== 'products' || action.context?.id !== 'assam') {
    fail(`order action was ${JSON.stringify(posts[1])}`);
  }
  if (posts[1]?.conversationId == null) fail('the action did not continue the conversation');

  await tap('Static UI still works: 0');
  await waitFor(/Static UI still works: 1/);
  if (!/Last order: Assam/.test(await text())) fail('static re-render lost the agent surface state');

  if (errors.length) fail(`page errors: ${errors.join('; ')}`);
  await page.screenshot({ path: join(work, 'agentic.png'), fullPage: true });
  await browser.close();
  if (!process.exitCode) console.log('e2e-agentic: ok');
  else console.error(`e2e-agentic: screenshot and app kept in ${work}`);
} catch (e) {
  fail(e instanceof Error ? e.message : String(e));
} finally {
  stop();
  if (!process.exitCode) rmSync(work, { recursive: true, force: true });
}
