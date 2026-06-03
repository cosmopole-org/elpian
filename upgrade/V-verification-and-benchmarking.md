# V — Verification & benchmarking harness

How to prove each change is correct (no visual regression) and faster. Set this up
**before/with A2–A3** so you have golden baselines from the start.

## 1. Keep the existing safety net
- `rust/tests/vm_ast_integration.rs` — **10 tests, must stay green** after every Rust change:
  ```bash
  cargo test --release --manifest-path rust/Cargo.toml
  ```

## 2. Golden pixel-checksum tests (REQUIRED for A3/A4)
Add `rust/tests/renderer_golden.rs`:
- Build a handful of representative `SceneDef`s (cube, sphere, multi-mesh, particles,
  translucent, lit) at fixed size (e.g. 256×256), render N frames at fixed `delta_time`.
- Hash the framebuffer (`pixels`) — e.g. FNV/CRC32 or `format!("{:x}", seahash)`.
- **Capture baseline hashes BEFORE A3** (commit them as constants/fixtures).
- A3/A4 must reproduce the **same hashes** (byte-identical output). If FP reassociation makes
  hashes differ by a few pixels, either reorder ops to match exactly or switch to an
  allowed-tolerance compare (max per-channel delta ≤ 1) and document it.
- For A4: run the **same scenes through serial and parallel** paths and assert equal hashes.

```rust
// sketch
fn render_hash(scene: &SceneDef, w: u32, h: u32, frames: usize) -> u64 { /* ... */ }
#[test] fn cube_is_stable() { assert_eq!(render_hash(&cube(),256,256,3), CUBE_BASELINE); }
```

## 3. Criterion benchmarks (REQUIRED for A1–A5)
Add `rust/benches/render.rs` + to `rust/Cargo.toml`:
```toml
[dev-dependencies]
criterion = "0.5"

[[bench]]
name = "render"
harness = false
```
- Bench `render_scene` for: empty, single cube, sphere(hi-poly), 50 meshes, particle system,
  large translucent quad (fill-rate). Report time per frame.
- Run and record:
  ```bash
  cargo bench --manifest-path rust/Cargo.toml
  ```
- Save before/after into `benchmarks/reports/optimization/<workstream>.md` and the
  `STATUS.md` results table (p50 / mean per scene).
- Note: Criterion uses the `bench` profile — ensure it inherits release-level opts (A1).

## 4. WASM compatibility build (REQUIRED — see X)
```bash
rustup target add wasm32-unknown-unknown
cargo build --release --manifest-path rust/Cargo.toml --target wasm32-unknown-unknown
```
Must succeed on the same commit as any new dep / parallel code (proves cfg-gating).

## 5. Rebuild the committed web WASM artifact (when Rust changes ship to web)
The repo ships a prebuilt `assets/web_runtime/wasm/elpian_vm/elpian_vm_bg.wasm`. Rust changes
do not reach web until this is regenerated. Document & run the project's wasm build (wasm-bindgen/
wasm-pack) and re-commit the artifact. Verify in a browser that 3D + VM still work.

## 6. Dart verification (on a machine with Flutter SDK — NOT in the cloud container)
- `flutter analyze` (zero new issues) and `flutter test` (add unit tests noted in B/C/D).
- `flutter run --profile` the example apps; use **DevTools**:
  - Performance/timeline: UI thread (build) + raster thread per frame.
  - Memory: allocation rate / GC during animation (verify pooling/caching reduced churn).
  - "Track Widget Builds" + shader-compilation overlay (for E).
- Compare against prior `benchmarks/reports/presentmon/` numbers (trust p50/p99, not avg fps —
  Flutter is demand-driven so idle gaps inflate averages).
- Visual regression sweep across web + mobile + desktop for B/C/D/F.

## 7. Per-change checklist (paste into each commit)
- [ ] 10 VM tests green
- [ ] Golden hashes match (or documented tolerance) — for renderer changes
- [ ] Host release build OK
- [ ] wasm32 build OK
- [ ] Criterion before/after recorded in STATUS.md
- [ ] (Dart) flutter analyze/test + profile on a real machine — recorded
- [ ] STATUS.md ticked + handoff note written
- [ ] Committed + pushed to `claude/funny-tesla-vzF9A`
