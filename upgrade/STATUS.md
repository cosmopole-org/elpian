# Optimization Program — Status Tracker

Update this file at the **end of every session**. Record measured numbers and any
deviations. `[ ]` = todo, `[~]` = in progress, `[x]` = done & verified.

## Progress

### Phase 1 — Rust core (locally verifiable)
- [x] **A1** Build profile `opt-level "z"→3` — `A1-rust-build-profile.md` (1.7–2.75× faster; report in `benchmarks/reports/optimization/A1-build-profile.md`)
- [x] **A2** Mesh-generation cache — `A2-rust-mesh-cache.md` (byte-identical; report in `benchmarks/reports/optimization/A2-mesh-cache.md`)
- [x] **A3** Incremental barycentric rasterizer inner loop — `A3-rust-rasterizer-inner-loop.md` (exact hoist; LLVM already did most of it — see report)
- [x] **Bench checkpoint #1** (after A1–A3) — recorded in `benchmarks/reports/optimization/`

### Phase 2 — Rust parallelism + transfer
- [x] **A4** `rayon` tiled parallel rasterizer (wasm-cfg-gated) — `A4-rust-parallel-rasterizer.md` (1.5–3× on 4 cores, byte-identical; report in `benchmarks/reports/optimization/A4-parallel-rasterizer.md`)
- [x] **A5** Double-buffer + `parking_lot` + `base64` crate — `A5-rust-frame-transfer-deps.md` (no regression; report in `benchmarks/reports/optimization/A5-frame-transfer-deps.md`)
- [x] **Bench checkpoint #2** (after A4–A5) — recorded in `benchmarks/reports/optimization/`

> **Dart note:** No Flutter SDK in this container — Dart changes below are
> inspection-level only and **must** be checked with `flutter analyze` / `flutter
> test` / device profiling before merge (see each workstream's Verification + `V`).

### Phase 3 — Frame transfer (zero-copy / latency)
- [~] **F1** Minimal-copy + synchronous image (native) — `F-zerocopy-lowlatency-frame-transfer.md`
  - Done: A5 double-buffer (Rust) makes the native pointer valid for a whole frame;
    `_BevyScenePainter` now reuses a static Paint + drops FilterQuality medium→none/low (E4).
  - Remaining (needs Flutter verification): reuse a single `Uint8List` in `getFrameDirect`
    instead of `Uint8List.fromList` per frame; replace async `decodeImageFromPixels`+`setState`
    with a `Listenable`-driven repaint. Risky to do un-tested (buffer lifetime vs async decode).
- [ ] **F2** Web fast path (drop base64/JSON) — same file (use existing `get_frame_bytes`; needs web test)

### Phase 4 — Dart renderers
- [~] **B** Dart 3D fallback renderer — `B-dart-3d-fallback.md`
  - Done (safe/mechanical, inspection-level — needs `flutter analyze`/`test` to confirm):
    Path reuse via `path.reset()` in `scene3d/renderer.dart` triangle loop and in
    `bevy/dart_scene_renderer.dart` (also reuses one fill `Paint`); particle update in
    `scene3d/core.dart` now swap-and-pops dead particles (O(1)) instead of `removeAt` (O(n)).
  - Remaining (higher-risk, needs Flutter): view/world matrix cache + node dirty-tracking,
    `Particle` object pool, fixed-size clip buffers, `math.pow` LUT, repaint `Listenable`.
- [~] **C** Canvas 2D allocations — `C-dart-canvas2d.md`
  - Done: `clearRect` now uses `drawRect`+static `BlendMode.clear` paint (no `saveLayer`);
    parsed-font cache (`_ParsedFont`) so the font string isn't re-scanned per `fillText`.
  - Remaining: paint-getter color caching; decide on the dead shadow state (impl vs remove).

### Phase 5 — Flutter UI pipeline
- [~] **D** HTML/CSS/Flutter-DSL pipeline — `D-dart-html-css-dsl.md`
  - Done: **D5** image decode caching (`cacheWidth`/`cacheHeight` from style) in
    `html_img.dart` + `elpian_image.dart`.
  - Remaining (higher-risk, needs Flutter): **D1** CSS parse/computed-style memoization,
    **D2** kill the double parse on merge (needs a verified `CSSStyle.merge`), **D3** `@immutable`
    + `==`/`hashCode` + stable keys, **D4** layout micro-fixes, **D6** animated-widget alloc.
- [~] **E** Impeller config + shader warmup + image cache — `E-flutter-impeller-config.md`
  - Done: **E4** frame-blit paint hint (reused Paint, FilterQuality none/low; RepaintBoundary
    already present in `build`). **E3** pairs with D5.
  - Remaining: **E1/E2/E5** Impeller flags + SkSL warmup + release-build docs (per-device).

### Phase 6 — VM (high risk, optional within scope)
- [~] **A6** VM value model / CoW — `A6-rust-vm-hotpath.md` (locally verifiable but HIGH risk;
  multi-day Val-enum migration across the 4906-line executor — deferred to a focused effort)
  - Done (safe, verified byte-identical): `data.rs` `Object`/`Array` `stringify()` now build into a
    single buffer (`push_str`) instead of re-`format!`ing the accumulator each iteration — was
    O(n²) in value count; this path runs on every `render` host-call that serializes the UI tree
    across FFI. Verified by 10 VM tests + golden tests (output unchanged) + host & wasm32 builds.
  - Remaining (the actual high-risk core): `Val` enum + `Rc`/`make_mut` CoW migration.

### Phase 7 — OPTIONAL true GPU zero-copy
- [ ] **G** wgpu + Flutter external textures — `G-gpu-zerocopy-external-textures.md` (only on explicit go-ahead)

### Cross-cutting (run continuously)
- [x] **X** Cross-platform compat verified (host build + `cargo build --target wasm32-unknown-unknown`) after every Rust change (A1–A5)
- [x] **V** Golden/pixel tests added and green; 10 VM tests still green (also double-buffer test)

## Measured results log

| Date | Change | Scene | p50 ms before | p50 ms after | Notes |
|------|--------|-------|---------------|--------------|-------|
| 2026-06-03 | A1 z→3 | single_cube | 2.214 | 0.804 | 2.75× |
| 2026-06-03 | A1 z→3 | fifty_meshes | 4.111 | 2.046 | 2.01× |
| 2026-06-03 | A1 z→3 | fillrate_quad | 9.280 | 4.918 | 1.89× |
| 2026-06-03 | A1 z→3 | sphere_hipoly | 8.585 | 5.115 | 1.68× |

## Session handoff notes

> Leave a short note for the next session: what you finished, what's half-done,
> any surprises, and the exact next step.

- 2026-06-03: Plan authored and persisted to `upgrade/`. No code changes yet.
  Next step: implement **A1** (lowest risk, highest ROI), then bench.
- 2026-06-03 (session 3): Continued on branch `claude/wonderful-galileo-UySD4`. No Flutter SDK
  in container (still), so Dart work stays inspection-only. Landed the remaining **safe/mechanical**
  pieces: **B** Path-reuse (`scene3d/renderer.dart`, `bevy/dart_scene_renderer.dart`) + particle
  swap-and-pop (`scene3d/core.dart`); and a verifiable **A6 subset** — `data.rs` stringify O(n²)→O(n)
  (byte-identical, confirmed by 10 VM tests + golden tests). Host + wasm32 builds green.
  **Still open (need a Flutter machine or are high-risk multi-day):** F1/F2 (async/web frame path),
  D1–D4/D6 (CSS memoization, CSSStyle `==`/merge, layout, animated alloc), E1/E2/E5 (Impeller/SkSL/
  release docs — per-device), and the real **A6** `Val`-enum + CoW migration. Next: run
  `flutter analyze`/`flutter test` on all Dart edits, then continue B/D/F; A6 enum is its own effort.
- 2026-06-03 (session 2 cont.): **A1–A5 all done & verified** (golden byte-identical,
  double-buffer test, 10 VM tests, host + wasm32 builds, Criterion). Cumulative
  rasterizer speedup vs original `opt-level="z"`: ~3.8–5.6× (4 cores). Reports in
  `benchmarks/reports/optimization/`. Then did the **safe, contained Dart subset by
  inspection** (cannot compile here): E4 blit paint hint, C clearRect+font cache, D5
  image decode caching. **Remaining are unverifiable-here / high-risk:** F1/F2 async
  frame path, B, D1–D4/D6, E1/E2, and A6 (VM). Next session with a Flutter SDK should
  run `flutter analyze`/`flutter test` on the Dart edits, then continue B/D/F; A6 is a
  separate focused effort.
- 2026-06-03 (session 2): Working on branch `claude/affectionate-hypatia-EjllG`
  (not the doc's original branch). **A1 done & verified** (1.7–2.75× faster).
  **V harness landed**: `rust/tests/renderer_golden.rs` (golden FNV-1a framebuffer
  hashes for 6 scenes + determinism test) and `rust/benches/render.rs` (Criterion,
  6 scenes). Added `[profile.bench]` + `criterion` dev-dep. wasm target installed.
  Next: A2 (mesh cache), then A3 (incremental rasterizer) — both must keep golden
  hashes byte-identical.
