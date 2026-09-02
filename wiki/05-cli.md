# 05 — The `elpian` CLI

`elpian` is a **single native Rust executable** — a project manager, TypeScript
compiler and development runner. It uses Oxc's Rust TypeScript front-end, links
directly to the `js2elpian` compiler, and emits Elpian JavaScript, AST and
bytecode **without Node.js, npm, or any JavaScript tooling**.

Source: `cli/rust/main.rs` (the whole CLI is one file).

## Install

```sh
cargo install --path cli
```

The binary is named `elpian` (`[[bin]] name = "elpian"`). It depends on
`js2elpian` at `../rust/crates/js2elpian`, which is vendored in this repository — no
sibling checkout is needed.

## The whole surface

```
elpian create <DIRECTORY> [--template client|server|fullstack|showcase]

elpian run install
elpian run build [--mode js|bytecode|both]
elpian run dev   [--host <HOST>] [--port <PORT>] [--mode <MODE>] [--build-engine]
```

| Flag | Short | Default |
|---|---|---|
| `--template` | `-t` | `client` (also `server`, `fullstack`, `showcase`) |
| `--mode` | `-m` | from `elpian.config.json` (`both`) |
| `--host` | `-H` | `127.0.0.1` |
| `--port` | `-p` | `4173` |
| `--build-engine` | — | off — force a Flutter engine rebuild |

## The five-minute path

```sh
elpian create my-app --template fullstack
cd my-app
elpian run install
elpian run dev
# → [elpian] Rust VM server: http://127.0.0.1:4173
```

---

## `elpian create`

Scaffolds a project. `--template` decides which entries and files exist; see
[`06-templates.md`](06-templates.md) for the generated code.

```
my-app/
├── elpian.json              # project + dependencies
├── elpian.config.json       # build configuration
├── tsconfig.json
├── README.md
├── .gitignore
├── src/
│   ├── client.ts            # client and fullstack
│   └── server.ts            # server and fullstack
└── packages/
    └── elpian-sdk/
        ├── elpian.package.json
        └── index.ts         # the `el` / `render` SDK
```

## `elpian run install`

Links local packages into `.elpian/packages` and writes a lockfile. It does
**not** touch the network.

For each dependency in `elpian.json`:

1. Validate the name (rejects empty, `..`, leading/trailing `/`).
2. Canonicalise the declared path; error if it does not exist.
3. Read the package's `elpian.package.json` and check that its `name` matches
   the dependency key and its `entry` file exists.
4. Create a symlink `.elpian/packages/<name>` → the source directory. An
   existing non-link at that path is a hard error
   (`… exists and is not a managed package link`); a stale link pointing
   elsewhere is replaced.
5. Write `.elpian/elpian.lock.json` with the resolved absolute paths.

```
Installed 1 Elpian package(s)
```

## `elpian run build`

The full pipeline, per target (`client`, then `server` — whichever the config
declares):

1. **Bundle** — `bundle_module` resolves imports depth-first and concatenates
   the transpiled sources into one flat string (see
   [`04-languages.md`](04-languages.md) for the consequences).
2. Write `<outDir>/<target>.elpian.js` — the readable/debug artifact.
3. **Compile to AST** — `js2elpian::compile_js_to_ast` →
   `<target>.elpian.ast.json`. An `error` key in the result fails the build.
4. **Compile to bytecode** (unless `mode: "js"`) —
   `js2elpian::compile_js_to_bytecode` → `<target>.elpian.bc`. `None` means
   `JavaScript is outside the Elpian subset`.
5. Write `<outDir>/elpian.manifest.json`.
6. For client/fullstack, **package the web export** into `<outDir>/web`.

```
Built client: …/dist/client.elpian.bc
Built server: …/dist/server.elpian.bc
Deployable web app: dist/web
```

### The manifest

```json
{
  "version": 1,
  "client": {
    "format": "bytecode",
    "url": "__elpian/client.elpian.bc",
    "sourceUrl": "__elpian/client.elpian.js"
  },
  "server": { "endpoint": "__elpian/api" }
}
```

`format` is `"bytecode"` when a `.bc` was produced, else `"ast"` and `url` points
at the AST JSON. The Flutter shell fetches this first, then the artifact it
names.

### The web export

`dist/web` is a **self-contained static deployment**: the Flutter engine build
plus the application manifest and VM artifacts under `dist/web/__elpian/`.

> Deploy `dist/web` — **not** the Flutter engine's original `build/web`.

Packaging also **disables the service worker**: `flutter_bootstrap.js` has its
`_flutter.loader.load({serviceWorkerSettings: …})` call rewritten to
`_flutter.loader.load();`, so a stale cached engine never shadows a fresh build.

### Engine resolution

The client needs a Flutter web engine. Two config keys control where it comes
from:

| Key | Meaning |
|---|---|
| `engineProject` | A Flutter **project** the CLI may build (`flutter build web --base-href <basePath>`) |
| `engineDir` | An **already-built** Flutter web export — the CLI will not build it |

Defaults to the standalone project at `cli/elpian_client`, whose build
output is `<engineProject>/build/web`. That shell imports no example
application: at runtime it fetches `/__elpian/elpian.manifest.json`, downloads
the declared bytecode or AST, and executes it in the Elpian WASM VM.

The engine is rebuilt only when **stale**, determined by a marker file
`<engine>/.elpian_runtime` holding the base path and a timestamp: it rebuilds if
the marker is missing, if its `basePath=` line does not match, or if
`lib/main.dart`, `elpian_ui`'s `lib/src/vm/elpian_vm_widget.dart`, or
`lib/src/vm/frb_generated/api_web.dart` are newer than the marker.

## `elpian run dev`

1. Builds the project (without packaging the web export).
2. Builds the Flutter engine if stale, or if `--build-engine` was passed.
3. Starts a filesystem watcher on `src/`, `packages/`, `elpian.json` and
   `elpian.config.json`; every change triggers a rebuild and prints
   `[elpian] rebuilt`.
4. Runs the Rust server (`cargo run --bin elpian-server` from `elpian/rust`)
   with the engine as `--web-root`, `dist` as `--artifact-root`, and
   `dist/server.elpian.bc` as `--server-bytecode` when it exists.

```
[elpian] Rust VM server: http://127.0.0.1:4173
```

> **The dev server serves the shared engine directory**
> (`cli/elpian_client/build/web`), not the project's `dist/web`. Building
> a *different* project with a different `basePath` re-bases that shared
> directory out from under a running server. Give each project an explicit
> `engineProject` if you run more than one.

## Configuration: `elpian.config.json`

```json
{
  "basePath": "/",
  "client": { "entry": "src/client.ts" },
  "server": { "entry": "src/server.ts" },
  "mode": "both",
  "outDir": "dist",
  "engineDir": null,
  "engineProject": null
}
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `outDir` | path | `"dist"` | Build output directory |
| `mode` | `js` \| `bytecode` \| `both` | `"both"` | Which artifacts to emit |
| `basePath` | string | `"/"` | Subpath deployment, e.g. `"/myapp/"` |
| `engineDir` | path? | `null` | Prebuilt Flutter web export |
| `engineProject` | path? | `null` | Flutter project the CLI may build |
| `client` | `{ entry }`? | — | Client target; omit for server-only |
| `server` | `{ entry }`? | — | Server target; omit for client-only |

Keys are **camelCase** in JSON. Relative paths resolve against the project root.

### `basePath` and subpath deployment

`normalize_base` coerces the value to `/<trimmed>/`. It is passed to Flutter as
`--base-href`, so `index.html` carries `<base href="/myapp/">` and every asset
URL resolves under that prefix. **If you serve the app under a subpath, you must
set `basePath` and rebuild** — otherwise the page requests `/main.dart.js` at the
domain root and 404s.

## Configuration: `elpian.json`

```json
{
  "spec": 1,
  "name": "my-app",
  "dependencies": {
    "@elpian/sdk": { "path": "./packages/elpian-sdk" }
  }
}
```

A dependency value may be an object `{ "path": "…" }` or a bare path string.

A package declares itself with `elpian.package.json`:

```json
{ "spec": 1, "name": "@elpian/sdk", "version": "0.1.0", "entry": "index.ts" }
```

## Generated project layout after a build

```
my-app/
├── .elpian/
│   ├── elpian.lock.json
│   └── packages/@elpian/sdk -> ../../../packages/elpian-sdk
└── dist/
    ├── client.elpian.js          # readable/debug bundle
    ├── client.elpian.ast.json
    ├── client.elpian.bc          # what the browser actually runs
    ├── server.elpian.{js,ast.json,bc}
    ├── elpian.manifest.json
    └── web/                      # ← deploy this
        ├── index.html  main.dart.js  flutter_bootstrap.js  canvaskit/  assets/
        └── __elpian/             # manifest + VM artifacts
```

## The dev/prod HTTP surface

Served by `elpian-server` (`elpian/rust/crates/elpian-vm/src/bin/elpian-server.rs`):

| Route | Behaviour |
|---|---|
| `/__elpian/api/<fn>` | Invoke an exported server-VM function with the JSON body |
| `/__elpian/<file>` | Served from `--artifact-root` (`dist/`) |
| anything else | Served from `--web-root`; unknown paths fall back to `index.html` (SPA routing) |

Path traversal is rejected (`safe_join` refuses `..`, absolute and prefix
components). `HEAD` is supported. Every connection is handled on its own thread.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `JavaScript is outside the Elpian subset` | Your code uses something `js2elpian` cannot lower — see [`04-languages.md`](04-languages.md) |
| `TypeScript parse failed in <file>` | Syntax error; the diagnostic includes the source snippet |
| `cannot resolve Elpian package X; run 'elpian run install'` | Missing `.elpian/packages` link |
| `source file not found` | Entry path wrong, or the extension is not `.ts/.tsx/.js` and not a directory with `index.ts` |
| `Flutter engine missing at <path>` | `engineDir` points somewhere without `index.html` |
| Assets 404 at the domain root | `basePath` does not match where you serve it — set it and rebuild |
| `Address already in use` | Another dev server holds the port; pass `--port` |
