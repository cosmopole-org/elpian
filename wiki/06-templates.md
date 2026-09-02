# 06 — The project templates

`elpian create <dir> --template client|server|fullstack|showcase` scaffolds one of
four project shapes. They differ in exactly two things: **which entries exist in
`elpian.config.json`**, and **whether the SDK package is generated**.

```rust
let client   = !matches!(template, Template::Server);
let server   = matches!(template, Template::Server | Template::Fullstack);
let showcase = matches!(template, Template::Showcase);
```

| | `client` | `server` | `fullstack` | `showcase` |
|---|---|---|---|---|
| `src/client.ts` | ✅ | — | ✅ | ✅ (rich) |
| `src/server.ts` | — | ✅ | ✅ | — |
| `packages/elpian-sdk/` | ✅ | — | ✅ | ✅ |
| `@elpian/sdk` dependency | ✅ | — | ✅ | ✅ |
| Builds `dist/web` | ✅ | — | ✅ | ✅ |
| `POST /__elpian/api/<fn>` | — | ✅ | ✅ | — |
| `Scene3D` + full 2D GUI | — | — | — | ✅ |

Every template also gets `tsconfig.json`
(`target: ES2015`, `strict: true`, `module: ESNext`, `include: ["src"]`),
a `.gitignore` (`dist/`, `.elpian/`), and a `README.md`.

`create` refuses to overwrite: `<dir> already exists` is a hard error.

---

## 1. The client template — a UI VM in the browser

### What runs where

The **client VM** runs inside the browser, compiled to WASM, hosted by the
standalone Flutter shell at `cli/elpian_client`. That shell:

1. Fetches `/__elpian/elpian.manifest.json` (cache-busted with a nonce).
2. Reads `client.format` (`bytecode` \| `ast`) and `client.url`.
3. Downloads the artifact and constructs an `ElpianVmWidget.fromBytecode(...)`
   (or `.fromAst(...)`) with `machineId: 'elpian-dynamic-client'`.
4. The VM's `askHost("render", json)` calls become Flutter widgets.

The shell imports no example application — it is a generic host.

### `src/client.ts` as generated

```ts
import { el, render } from '@elpian/sdk';
let count: number = 0;
function view() {
  return el('div', { style: { padding: '32', color: '#172033' } }, [
    el('h1', { text: 'Hello from TypeScript' }, []),
    el('p', { text: 'This UI is running as Elpian bytecode.' }, []),
    el('button', { text: 'Count: ' + count, onClick: 'increment' }, []),
  ]);
}
function increment() { count = count + 1; render(view()); }
render(view());
```

Three things to notice, because they generalise to every client program:

- **State is a module-level variable.** `count` persists across turns for the
  lifetime of the VM instance. There is no component state, no hooks.
- **Handlers are closures.** `onClick: () => { … }` captures module state
  directly, and in a list captures the item. The SDK bridges them to the
  string-only wire format; a named top-level function still works too. See
  [`10-events.md`](10-events.md).
- **Re-render is explicit.** Nothing is reactive. The handler mutates state and
  calls `render(view())` itself.

### `packages/elpian-sdk/index.ts` as generated

```ts
export type ElpianNode = { type: string; props: Record<string, unknown>; events?: Record<string, string>; children?: ElpianNode[] };
export function el(type: string, props: Record<string, unknown>, children: ElpianNode[]): ElpianNode {
  // The host reads handlers from a top-level `events` map keyed by the
  // lowercase event name ("click"), not from `onClick` inside props.
  const rest: Record<string, unknown> = {};
  const events: Record<string, string> = {};
  for (const key in props) {
    const value = props[key];
    if (typeof value === 'string' && key.length > 2 && key.slice(0, 2) === 'on') {
      events[key.slice(2).toLowerCase()] = value;
    } else {
      rest[key] = value;
    }
  }
  return { type, props: rest, events, children };
}
declare function askHost(name: string, payload: unknown): unknown;
export function render(node: ElpianNode): void { askHost('render', JSON.stringify(node)); }
```

The SDK is **generated into your project, not vendored from a registry** — it is
ordinary source you own and may extend. Its whole job is to build the node JSON
and hand it to `askHost`.

The `on*` → `events` split is load-bearing. `ElpianNode.fromJson` reads handlers
**only** from a top-level `events` map keyed by lowercase event name; nothing in
the engine maps `props.onClick`. An `el()` that passes `onClick` through as an
ordinary prop produces a button that renders but never responds — see
[`07-ui-model.md`](07-ui-model.md) and [`14-gotchas.md`](14-gotchas.md).

### Deploying

`elpian run build` produces `dist/web`. Serve that directory statically. If it is
not at the domain root, set `basePath` first and rebuild.

---

## 2. The server template — stateless VM functions over HTTP

### What runs where

`elpian-server` (native Rust) exposes every exported function in
`server.elpian.bc` at `POST /__elpian/api/<functionName>`.

**Per request** (`run_api` in `rust/src/bin/elpian-server.rs`):

```rust
let id = format!("elpian-http-{}", REQUEST_ID.fetch_add(1, Ordering::Relaxed));
elpian_vm::api::init_vm_system();
elpian_vm::api::create_vm_from_bytecode(id.clone(), bytecode);
let initial = elpian_vm::api::execute_vm(id.clone());          // run top level
if initial.has_host_call { /* 501 */ }
let input = if method == "GET" { "{}" } else { body };
let result = elpian_vm::api::execute_vm_func_with_input(id.clone(), function, input, 1);
elpian_vm::api::destroy_vm(id);
```

**A fresh VM is created and destroyed for every request.** The consequences are
not negotiable:

- ❌ **No state survives between requests.** Module-level variables reset. Use a
  database or the host, not globals.
- ❌ **No host calls.** An unhandled `askHost` — including `console.log`, which
  lowers to `askHost("log", …)` — returns **HTTP 501** with the host-call data
  as the body. This applies to the top-level too: a program that calls a host
  API while initialising fails before your function is even reached.
- ✅ Functions must be **synchronous and side-effect-free**. The README states
  this plainly: "host-call servicing is a separate production adapter concern."

### `src/server.ts` as generated

```ts
export function hello(input: { name?: string }) {
  const name = input.name || 'world';
  return { message: 'Hello, ' + name + ', from the Elpian server VM!' };
}
```

### Calling it

```sh
curl -X POST http://127.0.0.1:4173/__elpian/api/hello \
     -H 'content-type: application/json' \
     -d '{"name":"Ada"}'
# {"message":"Hello, Ada, from the Elpian server VM!"}
```

`GET` is accepted and passes `{}` as the input. An **unknown function name
currently returns `200` with the body `"[undefined]"`**, not a 404 — check for
that shape rather than relying on the status code.

A server-only project builds no `dist/web`; `elpian run dev` still needs a
`--web-root` with an `index.html`, so the engine is still resolved.

---

## 3. The fullstack template — both, from one project

`elpian.config.json` declares both targets:

```json
{
  "basePath": "/",
  "client": { "entry": "src/client.ts" },
  "server": { "entry": "src/server.ts" },
  "mode": "both",
  "outDir": "dist"
}
```

`build_project` loops over `[("client", …), ("server", …)]` and compiles each
independently — **two separate bundles, two separate VMs, no shared scope.**
Code common to both must live in a package that both import; it will be
duplicated into each bundle.

The manifest declares both:

```json
{
  "version": 1,
  "client": { "format": "bytecode", "url": "__elpian/client.elpian.bc",
              "sourceUrl": "__elpian/client.elpian.js" },
  "server": { "endpoint": "__elpian/api" }
}
```

### The client calling the server

The client VM cannot make network calls on its own — there is no `fetch` in the
subset. Two routes:

1. **A host API.** Register a custom handler (e.g. `app.fetch`) in the embedding
   Flutter app and call `askHost('app.fetch', …)`. See
   [`12-host-apis.md`](12-host-apis.md).
2. **The host does it.** Have the Flutter shell fetch and deliver the result
   into the VM with `deliver_host_message` or a named entry function.

The manifest's `server.endpoint` (`__elpian/api`) is the path the client side
should use, relative to the page's base href.

### Same-origin by construction

Because one server serves both the static engine and the API, there is no CORS
story and no second origin. Behind a reverse proxy, keep them under the same
prefix — a trailing-slash `proxy_pass` that strips your subpath works, provided
the app was built with a matching `basePath`.

---

## Choosing

| You need | Template |
|---|---|
| A dynamic, hot-updatable UI | `client` |
| A pure function endpoint, or untrusted user logic evaluated server-side | `server` |
| An app with both | `fullstack` |
| Server logic with state or I/O | **not the server template** — embed the VM in your own service and service its host calls |

---

## 4. The showcase template — mixed 2D + 3D

`--template showcase` generates a client project whose `src/client.ts` is a
complete mixed application rather than a counter: an embedded Godot `Scene3D`
stage surrounded by a rich 2D GUI, all from one `render()` call.

What it exercises:

- **A full declarative scene** — environment, camera, three light types
  (directional / omni / spot), nested pivot groups so bodies orbit without
  trigonometry, and a floor plane.
- **The 2D catalogue** — header, stat cards, tab pills, a selectable list, and
  action buttons, laid out with the CSS flex engine.
- **Interaction across the boundary** — 2D controls mutate module state, the
  scene is re-derived from it, and `Scene3D` rebuilds the 3D world *only when
  the description actually changes*, so 2D-only interactions cost nothing in 3D.

```sh
elpian create showcase-app --template showcase
cd showcase-app && elpian run install && elpian run dev
```

### Two node vocabularies, one program

The showcase is the clearest place to see that a program builds **two different
kinds of tree**:

```ts
el('div', { style: {...} }, [ ... ])   // the 2D widget tree — goes through el()
{ type: 'mesh', shape: 'torus', ... }  // a 3D scene-DSL node — a plain map
```

`el()` exists to split `on*` props into the `events` map the host reads; scene
nodes have no events and are plain maps. Passing a scene node through `el()`, or
building 2D nodes as bare maps, is the mistake to avoid.

### It is the CI's proof

`.github/workflows/build_showcase.yml` generates this template from the CLI,
compiles it to bytecode, and builds it for **web** and **Android** — so the
template, the toolchain and the `Scene3D` widget are verified together on every
push. The web build folds in the Godot HTML5 export from
`build_godot_artifacts.yml` when one is available, and ships the placeholder when
it is not — so both the live path and the degradation path stay covered.
