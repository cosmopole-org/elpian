# A3 — Rasterizer inner-loop hoisting (exact)

**Date:** 2026-06-03 · **Bench:** `cargo bench --bench render` (512×512, opt-level 3)

## What changed
`fill_triangle` now hoists out of the inner loop:
- per-triangle edge deltas `(b.* - a.*)`,
- per-scanline edge `y`-terms `(p.y - a.y) * (b.x - a.x)`,
- the per-triangle flat-shading color→byte conversion and the alpha-blend
  source-invariant terms (`color*src_a`, `1 - src_a`).

The per-pixel arithmetic keeps the **exact same operations and associativity**
as the original `edge_function(...) * inv_area`, so golden framebuffer hashes are
unchanged (byte-identical output, verified).

## Result (median frame time vs A2)

| Scene | A2 | A3 | Δ |
|-------|----:|----:|---|
| empty | 459.8 µs | 456.8 µs | noise |
| single_cube | 803.7 µs | 808.9 µs | noise |
| sphere_hipoly | 4.968 ms | 5.012 ms | noise |
| fifty_meshes | 2.054 ms | 2.032 ms | noise |
| particles | 0.990 ms | 0.988 ms | noise |
| fillrate_quad | 4.918 ms | 4.930 ms | noise |

## Finding
At `opt-level = 3` + LTO, **LLVM already hoists these loop invariants** — which
is precisely why A1 (`z → 3`) delivered a large speedup in the first place. The
manual refactor therefore yields no additional gain on the host build, but it:
- makes the hoisting explicit and robust on toolchains/targets that optimize
  less aggressively (notably the wasm build, and any non-LTO/debug build),
- restructures the fill loop cleanly ahead of A4's parallel rasterizer.

A genuinely larger rasterizer win would require **inexact** incremental edge
stepping (turning per-pixel multiplies into additions). That was deliberately
**not** taken here because it changes floating-point results and would break the
pixel-identical guarantee that A3's objective requires. The real throughput
multiplier for the fill stage is A4 (multi-core tiled parallelism).

Verified: golden hashes byte-identical, 10 VM tests green, host + wasm32 builds OK.
