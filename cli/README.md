# Elpian TypeScript CLI

`elpian` is a native Rust executable. It uses Oxc's Rust TypeScript frontend,
links directly to Victor's `js2elpian` compiler, and emits Elpian JavaScript,
AST, and bytecode without Node.js, npm, or JavaScript tooling.

```sh
cargo install --path cli   # from the elpian repo root
elpian create my-app --template client   # or server / fullstack / showcase
cd my-app
elpian run install
elpian run dev --build-engine
```

## Renderers

The client runs on the Elpian VM in either web host — pick one per project
with `"renderer"` in `elpian.config.json` (or `--renderer` on `create`, `run
build` and `run dev`):

| `renderer` | Web host | Built with |
|---|---|---|
| `flutter` (default) | The Flutter engine — `cli/elpian_client`, a standalone Flutter web shell | `flutter build web` (Flutter SDK) |
| `native` | The native DOM host — `native/web` (`@elpian/web`): real DOM elements, Canvas2D, the Elpian VM's wasm build | `npm ci` + `npm run build` in `native/` (Node.js) |

```sh
elpian create my-app --renderer native
elpian run dev                       # serves the native host
elpian run build --renderer flutter  # or build for Flutter instead
```

Both read the same `__elpian/elpian.manifest.json` and run the same client
AST / bytecode, so switching renderers needs no change to the app. The CLI
builds and caches each host per base path (`cli/elpian_client/build/
elpian-engine/` for Flutter, `native/web/build/elpian-engine/` for native).
The same apps run in the native Android, iOS and Expo hosts — see
[wiki/23-native-hosts.md](../wiki/23-native-hosts.md).

## Commands

- `elpian create <dir> --template client|server|fullstack [--renderer flutter|native]`
- `elpian run install`
- `elpian run build --mode js|bytecode|both [--renderer flutter|native]`
- `elpian run dev --host 127.0.0.1 --port 4173 [--build-engine] [--renderer flutter|native]`

Configuration lives in `elpian.config.json`. `renderer` selects the web host
(above). `engineDir` can point at an already-built web root for either
renderer, while `engineProject` points at a Flutter project that the CLI may
build (Flutter renderer). `basePath` configures subpath deployments such as
`/myapp/`.

The default web engine is the standalone Flutter project at
`cli/elpian_client` (resolved relative to this crate); it does not import or compile the example application.

For client and full-stack projects, `elpian run build` creates a self-contained
static deployment in `dist/web` for the chosen renderer. Deploy that
directory—not the engine's own build directory. It contains the engine plus the
application manifest and VM artifacts under `dist/web/__elpian`.

The server/fullstack development endpoint is
`POST /__elpian/api/<exportedFunction>` with a JSON body. Server VM functions
must be synchronous and side-effect-free for now; host-call servicing is a
separate production adapter concern.

The `.elpian.js` file is a readable/debug artifact. The browser runs the
compiled AST in `js` mode and the `.elpian.bc` file in `bytecode`/`both` mode,
so the runtime never needs a TypeScript or JavaScript parser.

Application dependencies are declared in `elpian.json`. Local packages declare
an `elpian.package.json`; `elpian run install` links them efficiently into
`.elpian/packages`. Application projects do not need npm manifests,
`node_modules`, or npm lifecycle commands.
