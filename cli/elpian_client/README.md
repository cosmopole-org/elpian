# Elpian dynamic client

This is the standalone Flutter web shell used by `elpian run build` and
`elpian run dev` when the project's renderer is `flutter` (the default). It has
no dependency on the example project. At runtime it fetches
`/__elpian/elpian.manifest.json`, downloads the declared client bytecode or
AST, and executes it in the Elpian WASM VM.

With `"renderer": "native"` in `elpian.config.json` (or `--renderer native`),
the CLI uses the `@elpian/web` DOM host in `native/web` instead of this shell:
`dist/web` then holds an `index.html`, `elpian-web.js` and `assets/` that read
the same manifest and run the same client artifact. See
[`wiki/05-cli.md`](../../wiki/05-cli.md) and
[`wiki/23-native-hosts.md`](../../wiki/23-native-hosts.md).
