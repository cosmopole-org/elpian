# X — Cross-platform compatibility matrix & checks

Run these checks **after every Rust change** and review the matrix before any change.
Targets: **Android, iOS, Windows, macOS, Linux, Web**.

## Platform delivery model (audited)
- **Native FFI** (`dart:ffi`): `libelpian_vm.so` (Android/Linux), `elpian_vm.dll` (Windows),
  `DynamicLibrary.process()` (iOS/macOS static). Loaders: `bevy_scene_api.dart:68`,
  `vm/frb_generated/api.dart:55`.
- **Web**: prebuilt **WASM** (`assets/web_runtime/wasm/elpian_vm/`) via JS-interop
  (`elpian_wasm_loader.js`). **Web does NOT use the native FFI path.** Rust cfg-gates wasm
  already: `api/bevy_wasm_ffi.rs:5`, `api/wasm_ffi.rs:3`.
- Example app enables all 6 platforms (`example/{android,ios,linux,macos,windows,web}`).
- Native build: `rust_builder/{android(build.gradle),ios(.podspec),linux(CMakeLists),
  macos(.podspec),windows(CMakeLists)}` → each runs `cargo build --release`.

## Compatibility verdict per workstream
| Change | Native (5) | Web (wasm) | Action required |
|--------|-----------|-----------|-----------------|
| A1 opt-level=3 | ✅ | ✅ | none (bigger binary) |
| A2 mesh cache | ✅ | ✅ | none (single-thread safe) |
| A3 inner loop | ✅ | ✅ | golden test (identical pixels) |
| **A4 rayon** | ✅ | ❌ **no threads** | **cfg-gate parallel path; serial fallback for wasm** |
| A5 parking_lot | ✅ | ⚠️ | **cfg: std Mutex on wasm**; base64 crate ok everywhere |
| A6 VM model | ✅ | ✅ | none (Rc, single-thread) |
| B/C/D Dart | ✅ | ✅ | pure Flutter |
| E Impeller/warmup | ✅ | ✅ | per-platform config; measure each |
| F1 frame transfer | native only | n/a | FFI path |
| F2 web fast path | n/a | web only | raw bytes, no base64 |
| G external textures | per-platform | ✗ web differs | optional; CPU fallback required |

## The one trap: threads on web
`rayon`/`std::thread`/`std::sync::Mutex` blocking semantics do **not** work on
`wasm32-unknown-unknown` without atomics+shared-memory+COOP/COEP (not configured here).
Every parallel or thread-sync addition MUST be `#[cfg(not(target_arch = "wasm32"))]` with a
serial/`std` fallback under `#[cfg(target_arch = "wasm32")]`. This mirrors existing repo code.

## Mandatory local checks after each Rust change
```bash
# host build + tests
cargo build --release --manifest-path rust/Cargo.toml
cargo test  --release --manifest-path rust/Cargo.toml          # 10 VM tests must stay green

# WEB compatibility (proves cfg-gating compiles for wasm)
rustup target add wasm32-unknown-unknown        # once
cargo build --release --manifest-path rust/Cargo.toml --target wasm32-unknown-unknown
```
- [ ] Both builds succeed; tests green. If the wasm build fails, a non-gated thread/dep leaked in.

## Checks that need real machines/CI (Dart + per-platform)
- [ ] `flutter analyze` + `flutter test` on a machine with the SDK.
- [ ] Smoke-run the example on as many of the 6 platforms as available (at minimum: one mobile,
      web, one desktop).
- [ ] Rebuild the **web WASM artifact** in `assets/web_runtime/wasm/` from the updated Rust and
      confirm 3D + VM still work in a browser (the committed `.wasm` is prebuilt — Rust changes
      require regenerating it; document the wasm-pack/wasm-bindgen build command used).
- [ ] Native libs load on each platform (no missing-symbol/ABI regressions from new deps).

## Notes
- New crates (`rayon`, `parking_lot`, `base64`) must keep the wasm build green via cfg — verify
  with the wasm target command above on the same commit.
- Do not add `panic="abort"` (no `catch_unwind` at FFI). Do not add `target-cpu=native` (portability).
