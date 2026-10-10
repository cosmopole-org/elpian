import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const pw = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const root = new URL('.', import.meta.url).pathname;
const types = { '.html': 'text/html', '.js': 'text/javascript' };
const server = createServer(async (req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  try { res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' }); res.end(await readFile(join(root, p))); }
  catch { res.writeHead(404); res.end(); }
}).listen(0);
const [query, out, w, h] = process.argv.slice(2);
const browser = await pw.chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: Number(w), height: Number(h) } });
const errs = [];
page.on('pageerror', (e) => errs.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
await page.goto(`http://localhost:${server.address().port}/scene.html?w=${w}&h=${h}&${query}`);
await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
await page.screenshot({ path: out, omitBackground: true });
console.log('rendered', out, errs.join(' | '));
await browser.close(); server.close();
