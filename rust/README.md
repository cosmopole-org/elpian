# The Elpian Rust workspace

A virtual workspace: `Cargo.toml` here defines no package, so every crate sits
under `crates/` on equal footing. Previously `elpian-vm` was both the root
package *and* the workspace root, which put the VM's own `src/` beside its
member crates and read as though the VM contained them.

`target/` stays here, shared by every crate, because the Flutter build wiring
(`rust_builder/`'s CMake and podspecs) looks for
`rust/target/release/libelpian_vm.*`.

## Crates

| Crate | What it is |
|---|---|
| `elpian-vm` | The bytecode VM: executor, compiler, standard library, and the governance model (capabilities, limits, hierarchy, lifecycle). Also the embedding surfaces — the C ABI (`api::ffi`), the wasm-bindgen API (`api::wasm`) and the HTTP server binary. |
| `js2elpian` | JavaScript → Elpian AST / bytecode. |
| `dart2elpian` | Dart → the JS subset `js2elpian` compiles. |
| `elpian-dart-runtime` | The `dart:*` host surface and the Flutter widget layer, plus a Dart-level capability/resource governor. Was named `dart`, which read as a language, a directory and a dependency at once. |
| `elpian-runtime` | The host-neutral multi-VM manager: `vm.spawn`, the sandbox rules, aggregate budgets, per-VM callback namespacing. The embedder supplies the surface (Godot, Flutter, …) through the `HostSurface` trait. |
| `elpian-ffi` | The C ABI Flutter links against. Produces `libelpian_vm.{so,dll,a}` — the artifact name the Dart bindings open — exporting the VM surface, the governance control plane, and the multi-VM manager. |
| `capi` (`elpian-godot-capi`) | The C ABI the Godot GDExtension embeds: `GodotSurface` plus the `elpian_godot_*` exports. |

`cli/` is a separate Cargo project with its own lockfile; CI builds and tests it
alongside this workspace (see `.github/workflows/verify.yml`).

## Common tasks

```bash
cargo test --workspace                 # everything
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all

cargo build --release -p elpian-ffi    # what Flutter links: libelpian_vm
cargo run --bin gen-host-api-catalog -- ../lib/src/vm/host_api_catalog.dart

# The browser VM. wasm-pack needs a package, not the virtual root:
cd crates/elpian-vm && wasm-pack build --release --target web
```

## The guest preludes are not here

The libraries a mini app is written against live in `guest-sdk/` at the
repository root. They are embedded into these crates with `include_str!`, so
editing one needs a Rust rebuild — see `guest-sdk/README.md`.
