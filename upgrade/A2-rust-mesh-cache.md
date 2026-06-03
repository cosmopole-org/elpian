# A2 — Cache per-frame mesh generation

**Risk:** Low · **Verifiable here:** ✅ · **Effort:** 1–2 h · **ROI:** High (esp. particles & multi-mesh scenes)

## Objective
Generate primitive mesh triangle lists **once** and reuse them, instead of
regenerating every frame (and 100×/frame inside the particle loop).

## Why
In `rust/src/bevy_scene/renderer.rs`, `generate_mesh_triangles(...)` is invoked for
every mesh node each frame, and inside the particle emitter loop it is called per
spawned particle — up to `count.min(100)` cubes **per particle system per frame**
(`renderer.rs:401`, cap at `:383`). Mesh geometry for a given (type, params) is
invariant; only the transform changes per frame. Caching removes a large amount of
trig + allocation from the hot path.

## Files
- `rust/src/bevy_scene/renderer.rs` — `SceneRenderer` struct (`:25`), `render_scene` (`:68`),
  particle path (`:380-411`), and wherever `generate_mesh_triangles` is defined/called.
- `rust/src/bevy_scene/schema.rs` — `MeshType` / `MeshTypeName` enums (cache key source).

## Design
Add a mesh cache on `SceneRenderer` (the renderer instance lives behind the global
`Mutex`, so single-threaded access — no extra locking needed):

```rust
use std::collections::HashMap;
use std::sync::Arc;

pub struct SceneRenderer {
    // ...existing fields...
    mesh_cache: HashMap<MeshCacheKey, Arc<Vec<Triangle>>>,
}
```

- **Key** (`MeshCacheKey`): derive `Hash, Eq` from the mesh descriptor. For parametric
  meshes include subdivisions/segments/size etc. For procedural primitives without
  params, the `MeshTypeName` enum discriminant suffices. Quantize any `f32` params
  (e.g. `(radius * 1000.0) as i64`) so floats are hashable and stable.
- **Value:** `Arc<Vec<Triangle>>` so clones are cheap pointer bumps (no triangle copy).
- **Lookup helper:**
```rust
fn mesh_for(&mut self, mesh: &MeshType) -> Arc<Vec<Triangle>> {
    let key = MeshCacheKey::from(mesh);
    if let Some(m) = self.mesh_cache.get(&key) { return m.clone(); }
    let tris = Arc::new(generate_mesh_triangles(mesh));
    self.mesh_cache.insert(key, tris.clone());
    tris
}
```

## Steps
- [ ] Add `MeshCacheKey` (derive `Clone, PartialEq, Eq, Hash`) + `From<&MeshType>`.
      Quantize floats; cover every variant used by `generate_mesh_triangles`.
- [ ] Add `mesh_cache: HashMap<MeshCacheKey, Arc<Vec<Triangle>>>` to `SceneRenderer`,
      init empty in `new()` and `resize()` (resize need not clear it).
- [ ] Replace direct `generate_mesh_triangles(...)` calls in `render_scene`/mesh path and
      the **particle loop** with `self.mesh_for(...)`. Particles use a single cached unit cube.
- [ ] Ensure `rasterize_triangles` accepts `&[Triangle]` (it already does) so `&*arc` works.
- [ ] Bound the cache if scenes can define unbounded unique meshes (optional LRU / clear on
      `update_scene`). For the current fixed primitive set, unbounded is fine.

## Cross-platform notes
- Pure logic, single-threaded behind existing mutex. Works on all native + wasm.
- `Arc` is wasm-safe.

## Verification
- [ ] Golden/pixel-checksum test (see `V`): output must be **byte-identical** to pre-A2.
- [ ] 10 VM tests green; host + wasm builds succeed.
- [ ] Bench a particle-heavy scene; expect large drop in frame time.

## Rollback
Remove the cache field + helper; restore direct calls. Output identical either way.
