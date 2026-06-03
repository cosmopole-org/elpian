# A4 — `rayon` tiled multithreaded rasterizer

**Risk:** Med · **Verifiable here:** ✅ · **Effort:** 1–2 days · **ROI:** Very high on multi-core (2.5–7×)

## Objective
Parallelize rasterization across CPU cores using a **tile-based** scheme that avoids
shared-mutable aliasing, with a **serial fallback for web (wasm)** where threads are
unavailable.

## ⚠️ Cross-platform headline risk
`rayon` and `std::thread` **do not work on `wasm32-unknown-unknown`** (no threads
without the atomics/bulk-memory + cross-origin-isolation setup, which this project
does not have). **You MUST cfg-gate the parallel path** and keep the existing serial
rasterizer for wasm. The repo already uses this pattern (`rust/src/api/bevy_wasm_ffi.rs:5`).

## Files
- `rust/Cargo.toml` — add `rayon` as a **non-wasm** dependency.
- `rust/src/bevy_scene/renderer.rs` — `clear()` (`:54`), the triangle dispatch
  (`render_scene`/`rasterize_triangles`), and `fill_triangle` (`:546`).

## Cargo dependency (cfg-gated)
```toml
[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
rayon = "1.10"
```

## Design — screen tiles (recommended; correct & cache-friendly)
1. Divide the framebuffer into fixed tiles (e.g. 64×64 px). Each tile owns a disjoint
   region of `pixels`/`depth` → threads never touch the same bytes → no locks, no UB.
2. Per frame: project & light all triangles into a flat `Vec<ProjectedTri>` (screen-space
   verts + interpolated depth + final RGBA). This stays serial (cheap relative to fill).
3. **Bin** each projected triangle into the tiles its bbox overlaps (store indices).
4. `pixels.par_chunks_mut(tile_row_bytes)` / a tile iterator with `rayon`: each tile
   rasterizes only its triangles, clipped to the tile rect, writing into its own slice
   with a tile-local depth slice.

```rust
#[cfg(not(target_arch = "wasm32"))]
fn rasterize_all(&mut self, tris: &[ProjectedTri]) {
    use rayon::prelude::*;
    // split pixels+depth into tiles; for each tile in parallel:
    //   for each tri overlapping tile: fill within tile bounds
}

#[cfg(target_arch = "wasm32")]
fn rasterize_all(&mut self, tris: &[ProjectedTri]) {
    for t in tris { self.fill_triangle_serial(t); } // existing path
}
```

- `clear()`: `#[cfg(not(wasm))]` use `pixels.par_chunks_mut(...)` to zero in parallel;
  wasm keeps the serial loop.

## Alternative (simpler, smaller win): scanline split
Parallelize a single large triangle across rows with `par_iter` over `min_y..=max_y`,
each row writing a disjoint pixel span. Easier but less effective for many small tris.
Prefer tiles.

## Steps
- [ ] Refactor `rasterize_triangles` to **two phases**: (1) project+light → `Vec<ProjectedTri>`
      (serial), (2) `rasterize_all(&projected)`.
- [ ] Add `ProjectedTri { v: [Vec2;3], z: [f32;3], color: [u8;4], alpha: f32 }`.
- [ ] Implement tile binning + parallel fill behind `cfg(not(wasm32))`; serial fallback behind `cfg(wasm32)`.
- [ ] Parallelize `clear()` similarly.
- [ ] Ensure determinism: depth test resolves overlaps; with disjoint tiles the result is
      order-independent **per pixel** (one writer per pixel), so output is deterministic.

## Cross-platform notes (see `X`)
- Native (Android/iOS/Win/Mac/Linux): full parallel path.
- Web (wasm): serial fallback — **must compile**. Verify with the wasm target build.
- `rayon` global threadpool is fine; do not spawn per-frame threads.

## Verification
- [ ] Golden pixel-checksum test: parallel output **byte-identical** to serial (run the same
      scenes through both code paths in a test using a feature flag or direct call).
- [ ] `cargo build --release` (host) AND `cargo build --release --target wasm32-unknown-unknown`
      both succeed (the latter proves cfg-gating).
- [ ] 10 VM tests green.
- [ ] Bench multi-tri scene on a multi-core host; record speedup vs A3 baseline.

## Rollback
Remove `rasterize_all`/binning, restore direct `fill_triangle` calls, drop `rayon` dep.
