# Elpian dynamic client

This is the standalone Flutter web shell used by `elpian run build` and
`elpian run dev`. It has no dependency on the example project. At runtime it
fetches `/__elpian/elpian.manifest.json`, downloads the declared client
bytecode or AST, and executes it in the Elpian WASM VM.
