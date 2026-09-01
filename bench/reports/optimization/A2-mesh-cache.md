# A2 — Per-frame mesh-generation cache

**Date:** 2026-06-03 · **Bench:** `cargo bench --bench render` (512×512, opt-level 3)

## What changed
`SceneRenderer` now caches generated primitive triangle lists in a
`HashMap<MeshCacheKey, Arc<Vec<Triangle>>>`. Geometry depends only on the mesh
descriptor (not the per-frame transform), so it is generated once and reused
across frames and across all particles (previously regenerated every frame, and
up to 100×/frame inside the particle loop). Key uses exact `f32::to_bits()` so
output is provably byte-identical (golden hashes unchanged).

## Result (median frame time)

| Scene | A1 baseline | A2 | Δ |
|-------|------------:|----:|---|
| sphere_hipoly (48 subdiv) | 5.115 ms | 4.968 ms | −3% |
| fifty_meshes | 2.046 ms | 2.054 ms | ~0 |
| particles | 1.008 ms | 0.990 ms | −2% |

The frame-time delta is small because these scenes are **fill-rate bound** —
rasterization dominates, not mesh generation (that is what A3/A4 attack). A2's
real value: it removes redundant trig + per-frame heap allocation (lower GC/alloc
churn, larger win for off-screen/culled or tiny meshes where generation would
otherwise dominate), and is a prerequisite for keeping the particle path cheap.

Verified: golden hashes byte-identical, 10 VM tests green, host + wasm32 builds OK.
