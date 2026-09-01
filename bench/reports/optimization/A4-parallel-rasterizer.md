# A4 — Tiled multithreaded rasterizer (rayon)

**Date:** 2026-06-03 · **Host:** 4 logical cores · **Bench:** `cargo bench --bench render` (512×512, opt-level 3)

## What changed
Scene traversal now **collects** screen-space triangles into `SceneRenderer.projected`
(in scene order) instead of filling immediately. After traversal, `rasterize_all`
fills them:
- **Native:** the framebuffer is split into disjoint 32-row horizontal bands; each
  band owns a contiguous `pixels`/`depth` slice and is rasterized on a rayon worker.
  Threads never alias the same bytes (no locks). Each band walks the triangles in
  collection order, so per-pixel depth resolution matches the serial path.
- **wasm32:** single serial pass (no threads available) — `rayon` is cfg-gated out.

`clear()` is likewise parallelized on native, serial on wasm.

The fill math is shared (`fill_projected`) and bit-identical to the A3 serial form,
so the golden hashes — captured on the serial renderer — still pass with the
parallel path active. That **is** the serial-vs-parallel equality proof.

## Result (median frame time, 4 cores)

| Scene | A3 (serial) | A4 (parallel) | Speedup |
|-------|------------:|--------------:|--------:|
| empty | 456.8 µs | 190.0 µs | 2.40× |
| single_cube | 808.9 µs | 433.0 µs | 1.87× |
| sphere_hipoly | 5.012 ms | 2.261 ms | 2.22× |
| fifty_meshes | 2.032 ms | 0.980 ms | 2.07× |
| particles | 0.988 ms | 0.675 ms | 1.47× |
| fillrate_quad | 4.930 ms | 1.649 ms | 2.99× |

~1.5–3× on 4 cores; scales with core count (more on mobile/desktop with 6–8+).

## Cumulative vs the original `opt-level = "z"` baseline (A1+A2+A3+A4)

| Scene | original `z` | now | total |
|-------|-------------:|----:|------:|
| single_cube | 2.214 ms | 0.433 ms | **5.1×** |
| fillrate_quad | 9.280 ms | 1.649 ms | **5.6×** |
| fifty_meshes | 4.111 ms | 0.980 ms | **4.2×** |
| sphere_hipoly | 8.585 ms | 2.261 ms | **3.8×** |

Verified: golden hashes byte-identical (serial==parallel), 10 VM tests green,
host build OK, **wasm32 build OK** (proves the thread path is cfg-gated).
