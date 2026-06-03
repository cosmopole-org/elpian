# Optimization Program — Status Tracker

Update this file at the **end of every session**. Record measured numbers and any
deviations. `[ ]` = todo, `[~]` = in progress, `[x]` = done & verified.

## Progress

### Phase 1 — Rust core (locally verifiable)
- [ ] **A1** Build profile `opt-level "z"→3` — `A1-rust-build-profile.md`
- [ ] **A2** Mesh-generation cache — `A2-rust-mesh-cache.md`
- [ ] **A3** Incremental barycentric rasterizer inner loop — `A3-rust-rasterizer-inner-loop.md`
- [ ] **Bench checkpoint #1** (after A1–A3) — record p50/throughput in `benchmarks/reports/`

### Phase 2 — Rust parallelism + transfer
- [ ] **A4** `rayon` tiled parallel rasterizer (wasm-cfg-gated) — `A4-rust-parallel-rasterizer.md`
- [ ] **A5** Double-buffer + `parking_lot` + `base64` crate — `A5-rust-frame-transfer-deps.md`
- [ ] **Bench checkpoint #2** (after A4–A5)

### Phase 3 — Frame transfer (zero-copy / latency)
- [ ] **F1** Minimal-copy + synchronous image (native) — `F-zerocopy-lowlatency-frame-transfer.md`
- [ ] **F2** Web fast path (drop base64/JSON) — same file

### Phase 4 — Dart renderers
- [ ] **B** Dart 3D fallback renderer — `B-dart-3d-fallback.md`
- [ ] **C** Canvas 2D allocations — `C-dart-canvas2d.md`

### Phase 5 — Flutter UI pipeline
- [ ] **D** HTML/CSS/Flutter-DSL pipeline — `D-dart-html-css-dsl.md`
- [ ] **E** Impeller config + shader warmup + image cache — `E-flutter-impeller-config.md`

### Phase 6 — VM (high risk, optional within scope)
- [ ] **A6** VM value model / CoW — `A6-rust-vm-hotpath.md`

### Phase 7 — OPTIONAL true GPU zero-copy
- [ ] **G** wgpu + Flutter external textures — `G-gpu-zerocopy-external-textures.md` (only on explicit go-ahead)

### Cross-cutting (run continuously)
- [ ] **X** Cross-platform compat verified (host build + `cargo build --target wasm32-unknown-unknown`) after every Rust change
- [ ] **V** Golden/pixel tests added and green; 10 VM tests still green

## Measured results log

| Date | Change | Scene | p50 ms before | p50 ms after | Notes |
|------|--------|-------|---------------|--------------|-------|
| | | | | | |

## Session handoff notes

> Leave a short note for the next session: what you finished, what's half-done,
> any surprises, and the exact next step.

- 2026-06-03: Plan authored and persisted to `upgrade/`. No code changes yet.
  Next step: implement **A1** (lowest risk, highest ROI), then bench.
