# Elpian TypeScript CLI

`elpian` is a native Rust executable. It uses Oxc's Rust TypeScript frontend,
links directly to Victor's `js2elpian` compiler, and emits Elpian JavaScript,
AST, and bytecode without Node.js, npm, or JavaScript tooling.

```sh
cargo install --path /home/ubuntu/test-space/elpian-cli
elpian create my-app --template client   # or server / fullstack
cd my-app
elpian run install
elpian run dev --build-engine
```

## Commands

- `elpian create <dir> --template client|server|fullstack`
- `elpian run install`
- `elpian run build --mode js|bytecode|both`
- `elpian run dev --host 127.0.0.1 --port 4173 [--build-engine]`

Configuration lives in `elpian.config.json`. `engineDir` can point at an
existing Flutter web export, while `engineProject` points at a Flutter project
that the CLI may build. `basePath` configures subpath deployments such as
`/myapp/`.

The default web engine is the standalone Flutter project at
`elpian-cli/elpian_client`; it does not import or compile the example application.

For client and full-stack projects, `elpian run build` creates a self-contained
static deployment in `dist/web`. Deploy that directory—not the Flutter
engine's original `build/web` directory. It contains the engine plus the
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
