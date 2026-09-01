# 13 — Recipes

Working patterns to copy. Every guest snippet here is inside the `js2elpian`
subset and compiles to bytecode.

---

## 1. Scaffold, build, run

```sh
elpian create my-app --template fullstack
cd my-app
elpian run install
elpian run build --mode both
elpian run dev --host 127.0.0.1 --port 4173
```

Verify:

```sh
curl -s http://127.0.0.1:4173/__elpian/elpian.manifest.json
curl -s -X POST http://127.0.0.1:4173/__elpian/api/hello \
     -H 'content-type: application/json' -d '{"name":"Ada"}'
```

---

## 2. A counter (the canonical client shape)

```ts
import { el, render } from '@elpian/sdk';

let count: number = 0;

function view() {
  return el('div', { style: { padding: '32' } }, [
    el('h1', { text: 'Count: ' + count }, []),
    el('button', { key: 'inc', text: '+1', onClick: 'increment' }, []),
    el('button', { key: 'reset', text: 'Reset', onClick: 'reset' }, []),
  ]);
}

function increment() { count = count + 1; render(view()); }
function reset()     { count = 0;         render(view()); }

render(view());
```

The three-part shape — **module state · a `view()` builder · handlers that mutate
then `render()`** — is every client program.

---

## 3. A form with input

```ts
import { el, render } from '@elpian/sdk';

let name: string = '';
let greeting: string = '';

function view() {
  return el('div', { style: { padding: '24', display: 'flex',
                              flexDirection: 'column', gap: 12 } }, [
    el('label', { text: 'Your name' }, []),
    el('input', { key: 'name-field', value: name,
                  placeholder: 'Ada Lovelace', onInput: 'onName' }, []),
    el('button', { key: 'go', text: 'Greet', onClick: 'greet' }, []),
    el('p', { text: greeting }, []),
  ]);
}

function onName(event) {
  name = event.value;              // ElpianInputEvent carries `value`
}

function greet() {
  greeting = name.length > 0 ? 'Hello, ' + name + '!' : 'Type a name first.';
  render(view());
}

render(view());
```

> `onInput` does **not** re-render. Re-rendering on every keystroke would reset
> the field's cursor. Keep the model in sync and render on commit.

---

## 4. A list with per-item identity

Handlers are names, not closures, so read the item id out of the event.

```ts
import { el, render } from '@elpian/sdk';

type Todo = { id: number; text: string; done: boolean };
let todos: Todo[] = [
  { id: 1, text: 'Write the wiki', done: false },
  { id: 2, text: 'Ship it',        done: false },
];

function view() {
  const items = [];
  for (let i = 0; i < todos.length; i++) {
    const t = todos[i];
    items.push(el('li', {
      key: 'todo-' + t.id,
      text: (t.done ? '[x] ' : '[ ] ') + t.text,
      onClick: 'toggle',
      style: { cursor: 'pointer', padding: '8' },
    }, []));
  }
  return el('div', { style: { padding: '24' } }, [
    el('h2', { text: 'Todos' }, []),
    el('ul', {}, items),
  ]);
}

function toggle(event) {
  const id = parseInt(event.currentTarget.slice(5), 10);   // "todo-<id>"
  for (let i = 0; i < todos.length; i++) {
    if (todos[i].id === id) { todos[i].done = !todos[i].done; }
  }
  render(view());
}

render(view());
```

---

## 5. Event delegation for a long list

One handler on the container instead of one per row:

```ts
function view() {
  return el('ul', { key: 'list', onClick: 'onRowClick' }, rows.map(rowNode));
}

function onRowClick(event) {
  const id = event.target;      // the child that was actually hit
  // …
}
```

`event.target` is where it originated; `event.currentTarget` is where the
handler is attached.

---

## 6. An animation loop with timers

There is no `requestAnimationFrame` and no `async`.

```ts
import { el, render } from '@elpian/sdk';

let angle: number = 0;
let running: boolean = true;

function view() {
  return el('div', { style: { padding: '32' } }, [
    el('div', {
      key: 'box',
      style: {
        width: 80, height: 80, backgroundColor: '#2196F3',
        borderRadius: 12,
        transform: 'rotate(' + angle + 'deg)',
      },
    }, []),
    el('button', { key: 'toggle', text: running ? 'Pause' : 'Play',
                   onClick: 'toggleRun' }, []),
  ]);
}

function frame() {
  if (!running) { return; }
  angle = (angle + 3) % 360;
  render(view());
}

function toggleRun() { running = !running; render(view()); }

askHost('setInterval', ['frame', 16]);
render(view());
```

---

## 7. A server endpoint

`src/server.ts` — every exported function becomes `POST /__elpian/api/<name>`.

```ts
export function sum(input: { values?: number[] }) {
  const values = input.values || [];
  let total = 0;
  for (let i = 0; i < values.length; i++) { total = total + values[i]; }
  return { total: total, count: values.length };
}

export function validate(input: { email?: string }) {
  const email = input.email || '';
  const ok = email.indexOf('@') > 0 && email.indexOf('.') > 0;
  return { ok: ok, email: email };
}
```

```sh
curl -X POST http://127.0.0.1:4173/__elpian/api/sum \
     -H 'content-type: application/json' -d '{"values":[1,2,3,4]}'
# {"total":10,"count":4}
```

**Constraints, restated because they are absolute:** a fresh VM per request, so
no state carries over; and no host calls, so no logging, no I/O, no timers — an
unserviced `askHost` returns HTTP 501.

---

## 8. A shared package between client and server

```
my-app/
├── elpian.json
├── packages/
│   ├── elpian-sdk/
│   └── shared/
│       ├── elpian.package.json     { "name": "@app/shared", "entry": "index.ts" }
│       └── index.ts
└── src/{client,server}.ts
```

```json
{ "dependencies": {
    "@elpian/sdk": { "path": "./packages/elpian-sdk" },
    "@app/shared": { "path": "./packages/shared" } } }
```

```ts
// packages/shared/index.ts
export function formatMoney(cents: number): string {
  return '$' + (cents / 100).toFixed(2);
}
```

```ts
import { formatMoney } from '@app/shared';   // works in both entries
```

Run `elpian run install` after adding it. The module is **duplicated into each
bundle** — client and server are separately compiled.

> Because the bundler produces one flat scope, prefix names in shared packages
> to avoid collisions.

---

## 9. Embedding a VM in your own Flutter app

```dart
import 'package:elpian_ui/elpian_ui.dart';

class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = ElpianEngine()
      ..registerWidget('Sparkline', Sparkline.build);

    return ElpianVmWidget.fromBytecode(
      machineId: 'feature-panel',
      bytecode: bytecodeBytes,
      engine: engine,
      stylesheet: designTokens,
      loadingWidget: const Center(child: CircularProgressIndicator()),
      errorBuilder: (error) => ErrorPanel(message: error),
      onPrintln: (msg) => debugPrint('[guest] $msg'),
      hostHandlers: {
        'app.fetch': (name, payload) async {
          final args = jsonDecode(payload) as List;
          final res = await http.get(Uri.parse(args.first as String));
          return jsonEncode({'type': 'string', 'data': {'value': res.body}});
        },
      },
    );
  }
}
```

---

## 10. Sandboxing an untrusted child VM

```rust
use elpian_vm::api::*;
use elpian_vm::sdk::capabilities::Capability;
use elpian_vm::sdk::limits::ResourceLimits;

init_vm_system();

create_vm_from_bytecode("plugin-a".into(), plugin_bytes);
adopt_vm("app", "plugin-a");                       // inherits the ancestor intersection

set_local_capability("plugin-a", Capability::Logging,  true);
set_local_capability("plugin-a", Capability::Network,  false);
set_local_capability("plugin-a", Capability::VmManage, false);   // no grandchildren
set_limits("plugin-a", ResourceLimits::sandboxed());

// per frame
for (root, axis, destroyed) in enforce_tree_budgets() {
    eprintln!("subtree {root} exceeded {axis}; destroyed {destroyed:?}");
}

// metering
if let Some(u) = subtree_usage("app") {
    println!("instructions={} peak_mem={}", u.instructions, u.peak_memory_bytes);
}
```

---

## 11. Deploying behind a reverse proxy at a subpath

Set `basePath` **and rebuild** — this is not a proxy-only change:

```json
{ "basePath": "/myapp/", "client": { "entry": "src/client.ts" } }
```

```sh
elpian run build          # index.html now has <base href="/myapp/">
```

nginx, stripping the prefix with a trailing-slash `proxy_pass`:

```nginx
location = /myapp { return 301 /myapp/; }

location /myapp/ {
    proxy_pass http://127.0.0.1:4173/;   # trailing slash strips /myapp/
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
}
```

The base href makes the browser request `/myapp/main.dart.js`; the proxy strips
the prefix; the server sees `/main.dart.js`. Serve `dist/web` for a static
deployment, or proxy to `elpian-server` when you need the API.

---

## 12. Partial re-render with `Scope`

When one region updates far more often than the rest:

```ts
function view() {
  return el('div', {}, [
    el('Scope', { key: 'hud__scope' }, [ hudView() ]),   // repaints every frame
    el('Scope', { key: 'menu__scope' }, [ menuView() ]), // stays cached
  ]);
}
```

A scoped render targets the inner key and bumps only that wrapper's token. A
scoped render whose key is absent is **dropped, not escalated** to a full
re-render — you will see
`scoped render targeted missing scope "…"; keeping current view` in the log.
