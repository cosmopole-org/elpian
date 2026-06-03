# A1 — Release build profile `opt-level "z" → 3`

**Date:** 2026-06-03 · **Host:** cloud container (Linux 6.18.5) · **Bench:** `cargo bench --bench render`
(512×512, 1 frame/iter, Criterion 20 samples / 3 s measurement)

## Result — `opt-level = "z"` (size) vs `opt-level = 3` (speed)

| Scene | `z` (before) | `3` (after) | Speedup |
|-------|-------------:|------------:|--------:|
| single_cube | 2.214 ms | 0.804 ms | **2.75×** |
| fifty_meshes | 4.111 ms | 2.046 ms | **2.01×** |
| fillrate_quad | 9.280 ms | 4.918 ms | **1.89×** |
| sphere_hipoly | 8.585 ms | 5.115 ms | **1.68×** |

Optimizing a per-pixel rasterizer + bytecode interpreter for binary *size* was
leaving 1.7–2.75× of throughput on the table. `opt-level = 3` (with LTO +
single codegen unit retained) is the correct setting.

Did **not** add `panic = "abort"` (no `catch_unwind` at the FFI boundary) nor
`target-cpu=native` (binaries are cross-compiled and must stay portable).

## Post-A1 baseline (reference for A2–A5)

| Scene | p50 (median) |
|-------|-------------:|
| empty | 459.8 µs |
| single_cube | 803.7 µs |
| particles | 1.008 ms |
| fifty_meshes | 2.046 ms |
| fillrate_quad | 4.918 ms |
| sphere_hipoly | 5.115 ms |

Verified: 10 VM tests green, golden pixel hashes unchanged, host + wasm32 builds OK.
