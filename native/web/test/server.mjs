// A static server for the browser tests: serves native/web at /, plus a fake
// A2UI agent at POST /apps/demo/agent/assistant that answers NDJSON in small
// chunks split mid-line and records every request body (GET /__agent/requests).
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.json': 'application/json', '.map': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };

const CATALOG = 'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';
const agentRequests = [];

/** The fake agent's turns: the first message builds a form; an action answers through the data model. */
function agentTurn(body) {
  const lines = [{ type: 'conversation', conversationId: 'conv-test' }, { type: 'status', state: 'working' }];
  if (body.action) {
    const name = body.action.context?.name ?? '';
    lines.push({ version: 'v0.9.1', updateDataModel: { surfaceId: 'form', path: '/status', value: `Thanks, ${name}!` } });
    lines.push({ type: 'text', text: 'Submitted.' });
  } else {
    lines.push(
      { version: 'v0.9.1', createSurface: { surfaceId: 'form', catalogId: CATALOG, theme: { primaryColor: '#00796B', agentDisplayName: 'Test Agent' }, sendDataModel: true } },
      {
        version: 'v0.9.1',
        updateComponents: {
          surfaceId: 'form',
          components: [
            { id: 'root', component: 'Card', child: 'col' },
            { id: 'col', component: 'Column', children: ['title', 'name', 'submit', 'status'] },
            { id: 'title', component: 'Text', text: 'Sign up', variant: 'h3' },
            { id: 'name', component: 'TextField', label: 'Your name', value: { path: '/form/name' } },
            { id: 'submit_label', component: 'Text', text: 'Submit' },
            {
              id: 'submit',
              component: 'Button',
              child: 'submit_label',
              variant: 'primary',
              action: { event: { name: 'submitForm', context: { name: { path: '/form/name' }, plan: 'pro' } } },
            },
            { id: 'status', component: 'Text', text: { path: '/status' } },
          ],
        },
      },
      { version: 'v0.9.1', updateDataModel: { surfaceId: 'form', path: '/form', value: { name: '' } } },
      { type: 'text', text: 'Please fill in the form.' },
    );
  }
  lines.push({ type: 'done', stopReason: 'end_turn' });
  return lines.map((l) => JSON.stringify(l)).join('\n') + '\n';
}

async function serveAgent(req, res) {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  const body = JSON.parse(raw || '{}');
  agentRequests.push(body);
  res.writeHead(200, { 'content-type': 'application/x-ndjson' });
  const text = agentTurn(body);
  // Chunks of 37 bytes: boundaries fall mid-line.
  for (let i = 0; i < text.length; i += 37) {
    res.write(text.substring(i, i + 37));
    await new Promise((r) => setTimeout(r, 2));
  }
  res.end();
}

export function serve() {
  return new Promise((resolve) => {
    const server = createServer(async (req, res) => {
      const pathname = new URL(req.url, 'http://x').pathname;
      if (req.method === 'POST' && pathname === '/apps/demo/agent/assistant') return serveAgent(req, res);
      if (pathname === '/__agent/requests') {
        res.writeHead(200, { 'content-type': 'application/json' });
        return res.end(JSON.stringify(agentRequests));
      }
      const path = normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, '');
      try {
        const body = await readFile(join(root, path));
        res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
        res.end(body);
      } catch {
        res.writeHead(404);
        res.end('not found');
      }
    });
    server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` }));
  });
}
