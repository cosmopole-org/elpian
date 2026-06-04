# TPS Game — Performance & Visual Cleanup Plan

_Target: the third‑person shooter example (`example/lib/examples/tps_game_program.dart`)
rendered by the pure‑Dart `GameScene` software renderer (`lib/src/scene3d/`)._

**Goal:** make the scene **fast** (steady 30 fps on mobile/web), **clean**
(deliberate composition, no z‑fighting/visual noise), and **well rendered**
(correct, readable lighting) without dropping the "living downtown" feel.

---

## 0. Implementation status

| Phase | Item | Status |
|------|------|--------|
| 1A | Parse the static world once (`staticWorld`/`staticKey`), merge dynamic | ✅ done |
| 1B | Bake static world‑space lit triangles once, re‑project per frame | ✅ done |
| 1C | Throttle GameScene repaint to target fps (fps 60→30) | ✅ done |
| 1D | Opt‑in `renderScale` offscreen downsample (game uses 0.7) | ✅ done |
| 2E | Frustum‑cull static nodes by cached bounding sphere | ✅ done |
| 2F | Tighten depth sort | ⬜ todo |
| 3G | glTF skinning cache (quantized anim time) | ⬜ todo |
| 4H | Drop redundant per‑window emissive boxes; neon as accent | ✅ done |
| 4I | Bake point lights (now baked into static geometry) | ✅ (via 1B) |
| 4J | Trim segment counts / prop density (bollards) | ◑ partial |
| 4K | Fix z‑fighting decals | ⬜ todo (paths toned) |
| 4L | Palette / dusk‑fog pass (fog 62→50) | ✅ done |
| 5M | Perf harness + regression guards | ✅ done |

**Measured:** the static‑baked + frustum‑culled path renders a 288‑mesh city
grid **~2× faster** than the per‑frame dynamic path
(`test/scene3d_static_perf_test.dart`) — on top of eliminating the per‑frame
JSON re‑parse of the whole city (1A), which that benchmark doesn't even count.
A renderer parity test (`test/scene3d_static_render_test.dart`) confirms the
baked output matches the dynamic path within specular tolerance, and a visual
capture harness (`example/integration_test/tps_capture_test.dart`) renders the
in‑game and overhead shots for inspection.

Commits on `claude/beautiful-galileo-G4PzB`: renderer/engine optimizations →
visual declutter → perf harness.

---

## 1. How it works today (and why it lags)

The game runs **two independent loops**:

1. **QuickJS game loop** — `askHost('setInterval', {handler:'gameTick', delay:33})`
   (`tps_game_program.dart:1346`). Each tick runs `updateGame()` + `render()`.
   `render()` (`:1330`) builds the **entire** scene JSON
   (`CITY_FRAGMENT` + dynamic entities) and calls `askHost('render', json)`.
2. **GameScene `Ticker`** — `createTicker(_onTick)`
   (`game_scene_widget.dart:120`, `props.fps:60` at `tps_game_program.dart:1271`).
   Fires every display frame (up to 60 fps), calls `setState` → repaints →
   **re‑rasterizes the whole scene**.

### The core problems

| # | Problem | Where | Cost |
|---|---------|-------|------|
| **P1** | **Static city re‑parsed from JSON every game tick.** `render()` ships the full world string; `didUpdateWidget` sees `sceneJson` changed and calls `_parseScene()` → `jsonDecode` + `SceneParser.parse` of **all** static nodes, 30×/sec. | `game_scene_widget.dart:126‑178`, `scene_parser.dart:28‑76` | O(all nodes) JSON+alloc per tick |
| **P2** | **Static geometry re‑transformed & re‑lit every rasterized frame.** Per‑vertex `_computeLighting` over **5 lights** for every vertex of every static mesh, up to 60×/sec — even though the city never moves and its lights never change. | `renderer.dart:262‑369` (`_emitMeshTris`, `_computeLighting:701‑770`) | O(vertices × lights) per frame |
| **P3** | **No frustum / distance culling.** Every node is transformed, lit and projected each frame regardless of whether it's on‑screen or beyond fog. Only back‑face + near‑plane clipping exist. | `renderer.dart:104‑158`, `262‑369` | processes the whole map every frame |
| **P4** | **Full‑resolution software rasterization.** `CustomPaint` uses `Size.infinite` at native device pixels (e.g. 1080×1920 × DPR 2–3). A CPU rasterizer is fill‑rate bound; this dominates on phones. | `game_scene_widget.dart:221` | pixels × overdraw per frame |
| **P5** | **Raster runs at 60 fps while data updates at 30 fps; double `setState`.** The whole city is re‑drawn twice per data update, and both the VM‑widget render callback and the ticker call `setState`. | `game_scene_widget.dart:153‑165`, `elpian_vm_widget.dart:382‑388` | ~2× redundant raster |
| **P6** | **glTF skinning recomputed every frame.** All skinned models (player, up to 7 enemies, 4 foxes, 3+ trucks, ducks) are re‑skinned per vertex per frame even when `anim_time` is unchanged (ducks use `anim_time:0` — fully static). | `renderer.dart:451‑668`, `gltf_model.dart:221‑282` | O(verts × bones) per model/frame |
| **P7** | **Scene is visually "messy."** Redundant detail (per‑window emissive boxes on top of the windowed checkerboard texture), overlapping neon, coplanar decals (road paint at `y≈0.11` over asphalt) causing z‑fighting, and a high prop density that reads as noise rather than composition. | `tps_game_program.dart:942‑1035` | also feeds P2/P3 |

### Measured complexity (static city)

~80 source `cnPush` calls, but most run **inside loops**, so the runtime node
count is far higher: **32 buildings** (6×6 grid minus the plaza,
`:980‑997`), **~28 street lamps** (`:1005‑1010`), **28 bollards**
(`:1016‑1019`), 8 park trees (3 spheres each), 4 traffic lights, benches,
hydrants, planters, cones, dumpsters, bus stops, dashed lane markings + zebra
crosswalks, plus 7 streamed glTF models. Spheres/cylinders expand to ~100–220
tris each → an estimated **~10k–20k triangles**, every one transformed, lit and
depth‑sorted on **every** frame.

---

## 2. What's already good (keep it)

- **`CITY_FRAGMENT`**: the city is JSON‑*encoded* once in JS (`:1046‑1052`) —
  good. (The Dart side still re‑*decodes/parses* it; that's P1.)
- **Mesh geometry cache**: `Scene3DRenderer._meshCache` (`renderer.dart:860‑891`)
  builds each primitive shape once. Keep and lean on it (share descriptors).
- **`localTransform()` identity cache** (`core.dart:1387‑1401`) — but dynamic
  nodes thrash it by allocating new `Vec3`s each frame (see P2 follow‑up).
- **glTF model cache + placeholders** (`model_cache.dart`) — streaming is fine.

---

## 3. Optimization plan (phased, by impact ÷ effort)

> Legend — **Impact**: 🟥 huge · 🟧 high · 🟨 medium. **Effort**: S/M/L.
> Each item lists the **layer**: `engine` = `lib/src/scene3d/…`,
> `content` = `tps_game_program.dart`.

### Phase 1 — Stop redoing static work (the big wins)

**1A. Parse the static world once. 🟥 / M — engine + content**
Introduce a `"static": true` flag on nodes (set it on every `CITY_FRAGMENT`
node in JS). In `GameScene`/`SceneParser`, cache the parsed static node list
keyed by a `staticKey`/hash the game passes once; each frame only
`jsonDecode` + parse the **dynamic** array and concatenate with the cached
static `ParsedScene` nodes. Kills P1.
- Content: tag city nodes (`buildCity`/`cnPush`) with `static:true`; pass a
  constant `props.staticKey` on the `GameScene` node (`:1271`) plus a separate
  `dynamicWorld`. Or keep one `world` but split arrays: `staticWorld` (parsed
  once) + `world` (dynamic).
- Engine: `game_scene_widget.dart:126‑178` (don't reparse static on
  `didUpdateWidget`), `scene_parser.dart:28‑76` (parse static vs dynamic
  separately, memoize static by key).

**1B. Cache transformed + lit triangles for static nodes. 🟥 / L — engine**
For `static:true` mesh nodes, the world‑space vertex positions, normals and
**diffuse+ambient+emissive vertex colors are frame‑invariant** (geometry and
lights don't move). Compute them **once** and cache per node; each frame only
re‑project to screen, fog, cull and depth‑sort. Removes per‑vertex lighting and
world transforms for the whole city from the hot path. Kills the bulk of P2.
- Engine: in `_processNodes`/`_emitMeshTris` (`renderer.dart:104‑369`), add a
  per‑node cache of world‑space lit triangles, invalidated only when the static
  set changes.
- Nuance: Blinn‑Phong **specular** is view‑dependent (`_computeLighting` uses
  `cameraPos`, `:701‑770`). City materials are high‑roughness/low‑metallic, so
  **bake diffuse+ambient+emissive** and either skip specular for static geometry
  or approximate it — visually negligible, large speedup.

**1C. Decouple raster fps from display; repaint only on new data. 🟧 / S — engine + content**
Drive repaints from the data loop (30 fps) instead of a free‑running 60 fps
ticker; or cap the ticker and skip repaint when the scene is unchanged. Removes
the ~2× redundant rasterization and one of the two `setState`s. Kills P5.
- Content: lower `props.fps` to `30` (`:1271`) and the loop `delay` stays `33`.
- Engine: only `setState` in `_onTick` when `_renderer` has new content, or
  repaint on `didUpdateWidget` rather than every ticker tick
  (`game_scene_widget.dart:153‑178`).

**1D. Cap internal render resolution. 🟥 / S — engine**
Render the software scene to a fixed internal resolution (e.g. cap the long
edge to ~720–900 px, DPR ≈ 1.0) and let Flutter upscale the texture. For a CPU
rasterizer this is often the single biggest mobile win (fill‑rate ∝ pixels).
Kills P4.
- Engine: introduce a `renderScale`/`maxRenderDimension` and rasterize at that
  size inside `_GameScenePainter`/`Scene3DRenderer.render`
  (`game_scene_widget.dart:221`, `renderer.dart:82‑158`).
- Content: optionally expose via `props.renderScale` on the `GameScene` node.

### Phase 2 — Draw less

**2E. View‑frustum + fog‑distance culling. 🟧 / M — engine**
Give each node/static batch a cached world AABB; before processing, reject nodes
fully outside the camera frustum or beyond `fog_far` (62, `:735`). With a
third‑person camera you only ever see a slice of the map, so this can cut the
processed/sorted set by a large factor. Kills P3.
- Engine: `renderer.dart:104‑158` (cull before `_processNodes`), AABB test vs
  the view‑projection planes built at `:93‑97`.

**2F. Tighten depth sorting. 🟨 / M — engine**
Today all drawables merge into one global `sort` each frame
(`renderer.dart:114`). Once 2E shrinks the set this is cheaper; additionally,
keep static batches pre‑sorted by node and only merge‑sort the (small) dynamic
set against them, or bucket by coarse depth to reduce comparisons.

### Phase 3 — Skin smarter

**3G. Cache glTF skinning by (model, anim, quantized time). 🟧 / M — engine**
Skip re‑skinning when `anim_time` hasn't advanced past a small epsilon; cache
the skinned vertex buffer. Ducks (`anim_time:0`) and any idle model become
free. Kills P6.
- Engine: `renderer.dart:451‑668` (`_emitPrimitive`/`_skinPoint`),
  `gltf_model.dart:221‑282` (`computeGlobalTransforms`).
- Content: optionally quantize `anim_time` in JS so the cache hits
  (`addAmbientModels`/`addEnemyModel`, `:628‑670`).

### Phase 4 — Clean & well‑rendered (also reduces triangles)

**4H. Remove redundant detail. 🟧 / S — content**
The building facade already paints a **windowed checkerboard texture**
(`buildBuilding:945`), yet 0–4 extra emissive **window boxes** are stacked on
each near building (`:968‑977`). Drop these (or keep ≤1 accent) — big triangle
and overdraw win, cleaner read. Similarly thin the neon/awning layering
(`:965‑966`).

**4I. Bake the point lights into static vertex colors. 🟨 / S — engine/content**
Three point lights (fountain + 2 lamps, `:741‑743`) are evaluated per vertex
across the whole city every frame. With 1B these become a one‑time bake; keep
**one** directional key + ambient as the only *dynamic* lights so moving
entities still light correctly. Fewer lights in the per‑vertex loop
(`_computeLighting:720`).

**4J. Reduce primitive segment counts & prop density. 🟨 / S — content**
Trees use 3 spheres each (`buildParkTree:820`), finials/bulbs are spheres,
fountain uses 20‑segment cylinders (`:811‑818`). Drop segment counts where the
silhouette allows (spheres 12→8, cylinders 20→12), and **thin out** repeated
props (bollard loop `:1016`, cones `:1027`) — fewer, better‑placed objects read
as composition, not clutter.

**4K. Fix z‑fighting / coplanar decals. 🟨 / S — content + engine**
Road paint, crosswalks and lane markings sit ~0.01–0.11 above the asphalt
(`:765‑786`) and can shimmer. Give decals a clear, consistent y‑offset and/or a
small polygon‑offset bias in the renderer; ensure the grass/path/sidewalk slabs
don't overlap on the same plane.

**4L. Palette & atmosphere pass. 🟨 / S — content**
With baked lighting and fewer neon sources, retune the dusk fog
(`fog_near/fog_distance`, `:735`) and ambient (`:733`) so the skyline reads
cleanly into fog, the plaza is the bright focal point, and emissive accents are
intentional rather than competing. This is the "looks clean / well rendered"
deliverable.

### Phase 5 — Measure & guard

**5M. Frame‑time harness + regression guard. 🟧 / M — test**
- Extend the existing benchmark integration test
  (`example/integration_test/elpian_benchmark_test.dart`) with a **TPS scenario**
  that drives the real game loop and records FPS / p90 / p99 / jank, before vs
  after each phase.
- Keep the existing runtime smoke test
  (`example/integration_test/tps_smoke_test.dart`) green so optimizations don't
  reintroduce runtime errors.
- Add a cheap in‑HUD frame‑time readout (debug‑only) for manual checks.

---

## 4. Suggested order of execution

```
1D  render‑resolution cap        (engine, S)  ── instant mobile win, low risk
1C  decouple/cap raster fps      (engine, S)
1A  parse static world once      (engine+content, M)
1B  cache static transformed+lit (engine, L)  ── removes city from hot path
2E  frustum + fog‑distance cull  (engine, M)
4H  drop redundant window boxes  (content, S)  ── clean + fast
4I/4J/4K/4L  lighting/segments/z‑fight/palette cleanup (content, S each)
3G  skinning cache               (engine, M)
2F  tighten depth sort           (engine, M)
5M  perf harness + guards        (test, M)     ── run throughout
```

Rationale: ship the two low‑risk engine knobs (1D, 1C) first for an immediate
feel improvement, then the structural static‑caching (1A→1B→2E) that removes the
city from the per‑frame budget, then the content cleanup that makes it both
prettier and lighter, then skinning and final polish — measuring at every step.

---

## 5. Expected outcome / acceptance criteria

- **Per‑tick JSON parse** cost drops from O(all nodes) to O(dynamic entities)
  (P1 gone).
- **Per‑frame lighting/transform** of the static city goes to ~0 after the first
  frame (P2 gone); only dynamic entities + visible static batches are processed.
- **Rasterized pixels/frame** cut ~2–9× by the resolution cap (P4) and the
  60→30 fps decoupling (P5).
- **Processed/sorted triangles** cut substantially by frustum+fog culling (P3)
  and by removing redundant window/neon geometry (P7/4H).
- **Result:** steady **30 fps** with stable frame times (low p99/jank) on a
  mid mobile/web target, a **cleaner, more readable** dusk downtown, and no new
  runtime errors (smoke test still green).

---

## 6. Risks & mitigations

- **Static caching correctness** — if anything in `CITY_FRAGMENT` actually needs
  to change, the cache must invalidate. Mitigate: derive the static cache key
  from a content hash/version the game bumps only when the city changes.
- **Baked specular loss** — negligible for high‑roughness city materials; keep
  specular for dynamic entities. Verify visually in the palette pass (4L).
- **Resolution cap softness** — tune the cap so HUD/text (drawn by the 2D layer,
  not GameScene) stays crisp; only the 3D layer is downscaled.
- **Engine changes affect other scenes** — gate new behavior behind opt‑in props
  (`staticKey`, `renderScale`) so non‑game `GameScene` users are unaffected.
- Keep each phase a separate, independently revertable commit; re‑run the perf
  harness (5M) and smoke test after each.

---

## 7. File/Function index (quick reference)

| Area | File:line |
|------|-----------|
| Game loop / render emit | `example/lib/examples/tps_game_program.dart:1330‑1346` |
| GameScene node + props | `example/lib/examples/tps_game_program.dart:1271` |
| Static city builders | `example/lib/examples/tps_game_program.dart:693‑1053` |
| Buildings + redundant windows | `…:942‑997` |
| Lights (1 dir + 3 point) | `…:730‑744` |
| Widget loop / reparse / ticker | `lib/src/scene3d/game_scene_widget.dart:114‑178, 221, 242‑266` |
| Scene JSON parse (per frame) | `lib/src/scene3d/scene_parser.dart:28‑76` |
| Render + depth sort | `lib/src/scene3d/renderer.dart:82‑158` |
| Per‑vertex lighting | `lib/src/scene3d/renderer.dart:701‑770` |
| Mesh emit / clip / cull | `lib/src/scene3d/renderer.dart:262‑369` |
| Mesh geometry cache | `lib/src/scene3d/renderer.dart:860‑891` |
| glTF skinning | `lib/src/scene3d/renderer.dart:451‑668` |
| glTF transforms/anim | `lib/src/scene3d/gltf/gltf_model.dart:221‑282` |
| Node transform cache | `lib/src/scene3d/core.dart:1387‑1401` |
| Perf benchmark harness | `example/integration_test/elpian_benchmark_test.dart` |
| Runtime smoke test | `example/integration_test/tps_smoke_test.dart` |
