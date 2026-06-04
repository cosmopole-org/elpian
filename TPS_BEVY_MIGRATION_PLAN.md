# TPS → Bevy Widget Migration Plan

> **Goal.** Rewrite the third‑person shooter (TPS) example so it runs **entirely on the
> `BevyScene` widget** (the Rust/Bevy software‑renderer path of Elpian) instead of the
> Flutter‑Impeller `GameScene` widget (the pure‑Dart `scene3d` renderer). Along the way,
> bring the Bevy/Rust rendering path up to **feature parity** with everything the TPS
> needs, so the migration is clean, professional, and loses no visual or gameplay fidelity.
>
> This document is the **multi‑session execution plan**. Each *Phase* is a self‑contained
> chunk of work with concrete subtasks, file targets, and acceptance criteria. **Commit and
> push at the end of every phase.** A new session can resume by reading the "Status board"
> and the next unchecked phase.

---

## 0. How to use this plan in a fresh session

1. Read **§1 Architecture snapshot** and **§2 Capability gap matrix** to reload context.
2. Open the **Status board** (§4) and find the first phase not marked ✅.
3. Execute that phase's subtasks in order; respect its **Acceptance criteria**.
4. Run the phase's **Verification** commands. Rust is fully buildable/testable here
   (`cargo`); Flutter is **not** installed in the web sandbox, so Dart/widget verification
   is by `dart analyze`/CI/the user's machine — note this in the commit if you could not run it.
5. **Commit + push** to the working branch `claude/affectionate-noether-Zd8WS`, then tick the
   box on the Status board (also in the same commit when possible).

**Working branch:** `claude/affectionate-noether-Zd8WS` &nbsp;•&nbsp; **Repo:** `cosmopole-org/elpian`

---

## 1. Architecture snapshot

### 1.1 The two 3D paths today

| | `GameScene` (source of truth for TPS today) | `BevyScene` (migration target) |
|---|---|---|
| Widget | `lib/src/scene3d/game_scene_widget.dart` | `lib/src/bevy/bevy_scene_widget.dart` |
| Renderer | `lib/src/scene3d/renderer.dart` (`Scene3DRenderer`, ~1135 LOC, pure Dart) | **Rust** `rust/src/bevy_scene/renderer.rs` (FFI native + WASM web) **+** Dart fallback `lib/src/bevy/dart_scene_renderer.dart` |
| Parser | `lib/src/scene3d/scene_parser.dart` (rich) | `rust/src/bevy_scene/schema.rs` (serde) / Dart fallback inline parse |
| glTF | `lib/src/scene3d/gltf/*` (loader, model, cache, net fetch per‑platform) | **none** |
| Registered as | `GameScene`, `Game3D` | `BevyScene`, `Bevy3D`, `Scene3D` (see `lib/src/core/elpian_engine.dart:87‑93`) |

`BevySceneWidget` chooses a path at runtime: it tries the **FFI/WASM Rust renderer**
(`BevySceneController` → `BevySceneApi`), and silently falls back to the **Dart**
`DartSceneRenderer` when the native/WASM library is unavailable. To keep web/GitHub‑Pages
working, **both the Rust path and the Dart fallback must reach parity** (the Dart fallback
is the safety net; the Rust path is the "real" Bevy implementation the user is asking for).

### 1.2 What the TPS actually drives the renderer with

The TPS (`example/lib/examples/tps_game_program.dart`, a single QuickJS program) emits, per
frame, a scene JSON with this shape:

```jsonc
{ "staticKey": "downtown-v1",
  "staticWorld": [ /* the whole baked city, serialized once at boot */ ],
  "world":       [ /* camera, player, enemies, fx, pickups — re‑encoded each tick */ ] }
```

Node/material features it relies on (the parity checklist):

- **Nodes:** `camera` (Perspective fov/near/far), `light` (Directional + Point **with `range`**),
  `environment`, `group` (transform + children), `mesh3d`, and **`model3d`** (streamed glTF/GLB).
- **Meshes:** `Cube`, `Sphere {radius,segments}`, `Cylinder {radius,height,segments}`,
  `Cone {radius,height,segments}`, `Plane {size}`.
- **Materials:** `base_color`, `metallic`, `roughness`, `emissive`, **`emissive_strength`**,
  **`unlit`**, scalar **`alpha` + `alpha_mode:"blend"`**, `double_sided`, and **procedural
  textures** `texture:"noise"|"checkerboard"` with **`texture_color2`** and **`texture_scale`**.
- **Models (`model3d`):** `model` (GLB URL), `anim_time`, `animation` (clip name/index),
  `tint`, `emissive`/`emissive_strength`, full transform; CPU **skeletal skinning** + textured draw.
- **Environment:** `ambient_light`, `ambient_intensity`, **`sky_color_top`/`sky_color_bottom`**
  (vertical sky gradient), **`fog_type:"linear"`**, `fog_color`, **`fog_near`**, `fog_distance`.
- **Performance:** **static‑world bake/cache** keyed by `staticKey` (parse+light once, reuse
  every frame), per‑frame splice of only the dynamic `world`, **`renderScale`** down‑raster,
  fps throttle, frustum cull.

---

## 2. Capability gap matrix (parity checklist)

Legend: ✅ present · ⚠️ partial · ❌ missing. "Rust" = `bevy_scene` renderer/schema;
"Dart‑fb" = `DartSceneRenderer` fallback; "ref" = `scene3d` GameScene (reference impl).

| Feature | ref (`scene3d`) | Rust (`bevy_scene`) | Dart‑fb | Action phase |
|---|:--:|:--:|:--:|:--:|
| Cube/Sphere/Plane/Cylinder/Cone | ✅ | ✅ | ✅ | — |
| Mesh `segments`/`subdivisions` parity | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Material emissive | ✅ | ✅ | ✅ | — |
| Material `emissive_strength` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Material `unlit` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Scalar `alpha` + `alpha_mode:"blend"` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Procedural texture noise/checkerboard | ✅ | ✅ *(P1: per‑pixel)* | ✅ *(P1: centroid)* | P1 |
| `texture_color2`, `texture_scale` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Sky gradient `sky_color_top/bottom` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| `fog_type:"linear"`, `fog_near` | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| Point light `range` attenuation | ✅ | ✅ *(P1)* | ✅ *(P1)* | P1 |
| `model3d` glTF/GLB streaming | ✅ | ✅ *(P2: GLB+data‑URI)* | ⚠️ *(P2: capsule placeholder)* | P2 |
| CPU skeletal skinning + clip sampling | ✅ | ✅ *(P2)* | ❌ | P2 |
| Model `tint` / per‑node emissive | ✅ | ✅ *(P2)* | ⚠️ *(P2: tint on placeholder)* | P2 |
| Model embedded **texture images** (PNG/JPEG) | ✅ | ❌ *(deferred: needs image decoder)* | ❌ | P2+ |
| Static‑world bake/cache (`staticKey`) | ✅ | ✅ *(P3: manager cache)* | n/a | P3 |
| `renderScale` down‑raster | ✅ | ✅ *(P3: widget buffer scale)* | ⚠️ | P3 |
| fps throttle / non‑interactive overlay | ✅ | ✅ *(P3: ticker throttle)* | ✅ | P3/P4 |
| Host viewport env read | ✅ (JS) | n/a (widget) | n/a | P4 |

---

## 3. Strategy & key decisions

- **Primary path = Rust/Bevy.** The user explicitly wants the *Bevy Rust implementation*
  enhanced. So foundational features land **first in `rust/src/bevy_scene/` + `schema.rs`**
  (native FFI **and** WASM), then are mirrored in the Dart fallback so web stays functional
  even when the WASM module is missing.
- **Schema is shared contract.** Keep the JSON field names **identical** to what the TPS
  already emits (so the same DSL works for both widgets). Where the Rust schema differs
  (`subdivisions` vs `segments`), accept **both** via serde aliases rather than changing the game.
- **glTF in Rust is the hard part (P2).** Software‑renderer glTF needs a GLB parser +
  skinning math + a **network bridge**:
  - *Native FFI:* fetch on a background thread (add a small, vetted dep — `ureq` — or call back
    into the host). Cache decoded models by URL.
  - *WASM:* the sandbox can't block on `fetch`; route downloads through the **JS host**
    (the same `askHost` channel the VM already uses) → feed bytes back into Rust → decode →
    cache. Show a capsule placeholder until the model resolves (mirrors the current TPS behavior).
  - *Fallback:* if a model can't load, draw a tinted capsule so gameplay never breaks.
- **Don't fork the game logic.** Re‑use the existing QuickJS program; only the 3D **node type**
  (`GameScene` → `BevyScene`) and any schema‑field shims change. Gameplay, HUD, controls,
  AI, city builder stay byte‑for‑byte where possible.
- **DECIDED (user, 2026‑06‑04):** **Full Rust everywhere via JS‑bridge.** P2 implements the GLB +
  skeletal‑skinning pipeline in Rust for *all* platforms; on **web/WASM**, model downloads are
  bridged through the **JS host** (`askHost`/FFI callback) and fed back into Rust to decode/cache.
  The Dart‑fallback glTF remains only as a last‑resort safety net when the WASM module is absent.
- **DECIDED (user, 2026‑06‑04):** **Keep both TPS variants with an A/B toggle.** The Bevy TPS
  becomes the showcase, but the original Impeller `GameScene` TPS stays selectable for visual A/B
  comparison (kept until P6 confirms parity; do not delete it).

---

## 4. Status board

- [x] **P0 — Analysis, gap matrix & this plan** ✅ *(done)*
- [x] **P1 — Material, environment, light & mesh parity (Rust + Dart‑fb)** ✅ *(done)*
  - [x] Rust schema: `emissive_strength`, `unlit`, scalar `alpha`, lowercase `alpha_mode`,
        `texture*` (parsed), sky gradient, `fog_type`/`fog_near`, light `range`, `segments`.
  - [x] Rust renderer: unlit bypass, emissive strength, alpha blend, sky‑gradient clear,
        linear fog + near, point‑light range falloff, segment tessellation.
  - [x] Rust tests: `rust/tests/feature_parity.rs` (9 behavioral tests) + golden stable.
  - [x] Rust renderer: **procedural texture sampling** (noise/checkerboard/stripes/gradient) —
        per‑vertex UVs on mesh generators + `Triangle`; **per‑pixel** UV‑interpolated sampling
        in the rasterizer (untextured fast path stays byte‑identical).
  - [x] Dart fallback (`dart_scene_renderer.dart`): mirrors all the above (sky gradient clear,
        linear fog + near, point‑light range, `unlit`/`emissive_strength`/scalar `alpha`,
        `segments`, and procedural textures sampled at the triangle centroid).
- [x] **P2 — `model3d` glTF/GLB streaming + skeletal skinning (Rust + bridge)** ✅ *(core done; texture images deferred)*
  - [x] Schema `Model3DNode` (`model`/`anim_time`/`animation`/`tint`/`emissive`/transform/children); `"model3d"`+`"gltf"`.
  - [x] GLB container + embedded base64‑buffer glTF parse; accessor/bufferView decode.
  - [x] Node hierarchy, skins (inverse‑bind), animation channels (T/R/S, STEP/LINEAR+slerp).
  - [x] CPU linear‑blend skinning → posed triangles; tint × baseColorFactor + emissive.
  - [x] Per‑renderer model cache + capsule placeholder until bytes arrive.
  - [x] **Bridge:** host‑feed of model bytes via manager + native FFI (`elpian_bevy_feed_model`,
        base64) and WASM FFI (`elpian_bevy_wasm_feed_model`, typed array); Dart `BevySceneApi`
        (native+web) + `BevySceneController.feedModel`/`hasModel`.
  - [x] Tests: `rust/tests/gltf_skinning.rs` (synthetic skinned GLB; parse/skinning/anim/integration).
  - [x] Dart fallback: `model3d` draws a tinted capsule placeholder (full glTF in the fallback
        deferred — the Rust path is the real implementation).
  - [ ] *Deferred:* embedded **texture images** (PNG/JPEG) — needs a wasm‑safe image decoder.
- [x] **P3 — Static‑world bake/cache, renderScale & frame splicing** ✅
  - [x] Manager bakes `staticWorld` once (keyed by `staticKey`), splices the dynamic
        `world` each frame via `renderer.render_split` (`rust/tests/static_world.rs`).
  - [x] `renderScale` down‑raster: widget renders the FFI buffer at `size*renderScale`,
        upscaled to fill (parity with scene3d). `BevySceneWidget.build` reads `renderScale`.
  - [x] fps throttle: the render ticker only renders once per `1/fps` interval (so a
        non‑60 cap actually saves CPU); `interactive:false` already disables gestures.
  - [x] Off‑screen geometry is rejected at the fill stage (bbox clamp) + native rayon
        tiled rasterizer retained (broad‑phase frustum cull left as a future tuning).
- [x] **P4 — Widget/registry, viewport & overlay wiring for the Bevy path** ✅
  - [x] `BevyScene`/`Bevy3D`/`Scene3D` registered → `BevySceneWidget.build`
        (`lib/src/core/elpian_engine.dart`).
  - [x] `BevySceneWidget.build` reads `scene`(+`staticWorld`/`staticKey`), `width`,
        `height`, `fps`, `interactive`, `renderScale`, `sceneKey`/`sceneId`, `fit`.
  - [x] Scene doc flows through `loadScene`→manager→`SceneDoc` (static world preserved).
- [x] **P5 — Rewrite the TPS example on `BevyScene`** ✅
  - [x] Parameterized `tps_game_program.dart` with a single `SCENE_WIDGET` constant;
        the 3D node emits `type: SCENE_WIDGET` (kept `renderScale:0.7`, `fps:30`,
        `interactive:false`, the `__SCENE__` splice + `staticWorld` payload).
  - [x] `tpsGameProgramBevy` flips that one line to `'BevyScene'` — shared logic.
  - [x] Verified every material/mesh/env/light/model field the program emits is
        honored by the Bevy schema (P1/P2): no DSL shims needed (`segments` aliased).
  - [x] New page `example/lib/examples/tps_game_bevy_example.dart` (`TpsGameBevyPage`),
        reusing `GameLoading`; A/B launcher in `main.dart` (Bevy = showcase, Impeller kept).
  - [x] Bevy widget streams `model3d` URLs via `fetchModelBytes`→`controller.feedModel`
        (host side of the P2 bridge), so streamed glTF characters/vehicles load on the
        Bevy path; capsule placeholder until bytes arrive.
- [x] **P6 — Build (WASM+native), verify, optimize, document** ✅ *(native+tests+docs; WASM build deferred to CI — target not installed in this sandbox)*
  - [x] `cargo build --release` (shipped LTO config) clean; `cargo build` clean.
  - [x] `cargo test` all green: feature_parity (9), gltf_skinning (4), static_world (2),
        renderer_golden (golden stable), mesh_winding (7), vm_ast_integration (10), double_buffer.
  - [x] Docs: `3D_GRAPHICS.md` (Bevy parity note on materials/textures + Rust glTF note),
        `README.md` (two-backend / A/B TPS note); this plan's matrix updated.
  - [ ] *Deferred to CI/user:* WASM build (`wasm32-unknown-unknown` not installed here),
        `flutter analyze`/`flutter test` (Flutter not in sandbox), embedded glTF image
        textures on the Rust path.

- [x] **P7 — FPS optimization pass (web Flutter + Rust/Bevy WASM, and Impeller)** ✅ *(2026-06-04)*
  - [x] **Back-face culling** (`renderer.rs`): single-sided materials drop screen-space
        clockwise (back-facing) triangles at projection time, matching the scene3d
        reference the TPS was authored against. ~**1.6× faster** on closed geometry
        (native bench `sphere_hipoly` 2.16 ms → 1.32 ms); visible output byte-identical
        (golden stable — back-faces were already depth-occluded). This required fixing
        **inconsistent generator winding**: a central winding-normalization pass in
        `generate_mesh_triangles` (flip triangles whose vertex order disagrees with their
        assigned normal) plus a torus winding fix (it had inward normals — a latent
        lighting bug). Guarded by `tests/mesh_winding.rs` (7 tests).
  - [x] **Off-screen triangle rejection** (`renderer.rs`): triangles whose screen-space
        bbox is wholly outside the viewport are dropped before the fill stage, shrinking
        the projected set every (native) band re-iterates. Byte-identical.
  - [x] **WASM SIMD128** (`.cargo/config.toml` + `Cargo.toml` wasm-opt `--enable-simd`):
        compile the web module with `target-feature=+simd128` so LLVM auto-vectorizes the
        per-pixel rasterizer fill loop — a large win for the CPU rasterizer on web. Native
        builds unchanged (target-scoped). *(WASM build itself runs in CI.)*
  - [x] **Web frame transfer** (`bevy_scene_api_web.dart` + controller): the per-frame
        `_wasmGetFrame` metadata roundtrip (a JSON encode in Rust + `jsonDecode` in Dart on
        every frame) is gone — the controller passes its cached dimensions/frame-count, so
        only the pixel bytes cross the boundary. Native path elides two extra FFI calls too.
  - [x] **Impeller/Flutter** (`bevy_scene_widget.dart`): per-frame `setState` (which rebuilt
        the widget subtree every frame) replaced by a `ValueNotifier<ui.Image>` that repaints
        *only* the `CustomPaint` layer via the painter's `repaint:` listenable — fewer layer
        mutations on the Impeller path.

---

## 5. Phases

### P0 — Analysis, gap matrix & plan  ✅ deliverable: this file
**Subtasks**
1. Inventory both 3D paths, the TPS program, the Rust schema/renderer, the FFI/WASM bridge,
   and the glTF pipeline. *(done — see §1/§2)*
2. Produce the **capability gap matrix** (§2) and **strategy/decisions** (§3).
3. Persist this plan as `TPS_BEVY_MIGRATION_PLAN.md`; commit + push.

**Acceptance:** plan file present on the branch; gap matrix complete; decisions logged.

---

### P1 — Material, environment, light & mesh parity
Bring the **non‑glTF** rendering features to parity so static city + fx + primitives look right.

**Subtasks (Rust — `rust/src/bevy_scene/`)**
1. **`schema.rs` — `MaterialDef`:** add `emissive_strength: Option<f32>`, `unlit: bool`,
   `alpha: Option<f32>`, `texture: Option<TextureKind>` (`None|Noise|Checkerboard`),
   `texture_color2: Option<ColorDef>`, `texture_scale: Option<f32>`. Map `alpha_mode` string
   `"blend"`. Keep serde `#[serde(default)]` + aliases.
2. **`schema.rs` — `EnvironmentNode`:** add `sky_color_top`, `sky_color_bottom`,
   `fog_type: Option<String>` (`"linear"`), `fog_near: Option<f32>`. Keep `fog_distance`.
3. **`schema.rs` — `LightNode`:** add `range: Option<f32>` (point‑light cutoff).
4. **`schema.rs` — `MeshTypeParam`:** accept `segments` as an alias for `subdivisions`; ensure
   `Cylinder`/`Cone`/`Sphere` honor a tessellation count.
5. **`renderer.rs`:**
   - Sky **vertical gradient** clear (top→bottom) using env colors; fall back to flat.
   - **Emissive strength:** `emissive *= emissive_strength`.
   - **Unlit:** bypass Blinn‑Phong, output `base_color*tex` (+ emissive) directly.
   - **Alpha blend:** honor scalar `alpha` + `alpha_mode:Blend` in the rasterizer's src‑over.
   - **Procedural texture:** per‑triangle/per‑pixel sample of noise & checkerboard between
     `base_color` and `texture_color2`, scaled by `texture_scale` (UV from object/world coords).
   - **Point‑light range:** distance attenuation clamped to `range`.
   - **Linear fog:** `t = clamp((dist-fog_near)/(fog_distance-fog_near),0,1)` lerp to `fog_color`.
6. **Tests:** extend `rust/tests/renderer_golden.rs` (or add cases) for unlit, emissive_strength,
   alpha blend, checkerboard, sky gradient, fog_near, point range. `cargo test` green.

**Subtasks (Dart fallback — `lib/src/bevy/dart_scene_renderer.dart`)**
7. Mirror the same material/env/light handling so the web fallback matches (reuse helpers from
   `scene3d/renderer.dart` where practical; do **not** regress the existing fallback).

**Verification:** `cd rust && cargo build && cargo test`; `dart analyze` on changed Dart (best‑effort).
**Acceptance:** golden/unit tests pass; a primitive‑only TPS frame (no models) renders with
correct sky, fog, neon (emissive), windows (checkerboard), asphalt (noise), translucent water.
**Commit + push.**

---

### P2 — `model3d` glTF/GLB streaming + skeletal skinning
The largest phase. Add the streamed, skinned, textured character/vehicle pipeline to the Rust path.

**Subtasks (Rust)**
1. **Schema:** add `JsonNode::Model3D(Model3DNode)` with `model: String`, `anim_time: f32`,
   `animation: Option<StringOrIndex>`, `tint: Option<ColorDef>`, `emissive`,
   `emissive_strength`, `transform`. Register `"model3d"` (+ alias `"gltf"`).
2. **GLB container parser:** read the binary `glTF` header + JSON chunk + BIN chunk; parse glTF
   2.0 JSON (accessors, bufferViews, meshes/primitives, materials+textures, nodes, skins,
   animations). Decode accessor data (positions, normals, UVs, joints, weights, indices).
3. **Skinning:** build the node hierarchy + inverse‑bind matrices; sample animation channels
   (translation/rotation/scale) at `anim_time` with interpolation; compute joint matrices; apply
   linear‑blend skinning on the CPU to produce posed world‑space vertices each frame.
4. **Textured rasterization:** sample the primitive's base‑color texture (decode embedded
   PNG/JPEG → add a tiny image decoder dep, e.g. `image`, native‑only; for WASM prefer
   pre‑decoded RGBA via host or a minimal PNG path) and feed UV‑interpolated texels into the
   existing triangle rasterizer; apply `tint`, per‑node `emissive`.
5. **Network bridge + cache (`rust/src/bevy_scene/gltf/`):**
   - Abstraction `ModelSource` with two impls: **native** (background‑thread fetch via `ureq`,
     or a host callback) and **wasm** (request bytes from the **JS host** through a new FFI
     callback; resolve asynchronously).
   - **Model cache** keyed by URL; decode once, reuse posed buffers per `anim_time`.
   - **Placeholder:** until a model resolves, render a tinted capsule at the node transform.
6. **FFI/WASM surface (`rust/src/api/bevy_ffi.rs`, `bevy_wasm_ffi.rs` + Dart
   `lib/src/bevy/bevy_scene_api*.dart`):** add the model‑bytes feed/poll calls needed for the
   bridge; thread them through `BevySceneController`.
7. **Tests:** unit‑test GLB parse + skinning math against a tiny fixture (e.g. a 2‑bone clip);
   golden‑test a posed frame. `cargo test` green.

**Subtasks (Dart fallback)**
8. The Dart fallback already has a glTF pipeline (`lib/src/scene3d/gltf/*`). Ensure
   `DartSceneRenderer` can consume `model3d` nodes by **reusing** that pipeline (or delegating),
   so web without WASM still shows skinned models.

**Verification:** `cargo test`; manual native render of one `model3d` (CesiumMan) posed by `anim_time`.
**Acceptance:** a single streamed GLB renders skinned, textured, tinted, lit, with placeholder→model
transition and URL cache; no crash when offline (capsule fallback).
**Commit + push** (consider sub‑commits per subtask given size).

---

### P3 — Static‑world bake/cache, renderScale & frame splicing
Make the Bevy path cheap enough to run the TPS at interactive fps.

**Subtasks**
1. **Controller/manager `staticWorld`+`staticKey`:** in `BevySceneController` (and the Rust
   `manager.rs`/`renderer.rs`), accept a scene with `staticWorld`+`staticKey`; **parse + light‑bake
   the static nodes once**, cache by key, and on each `updateScene`/frame only parse the dynamic
   `world` and render `static ∪ dynamic`. Mirror `scene3d`'s `isStatic` bake.
2. **`renderScale`:** render the Rust/Dart frame into a smaller buffer and upscale (param already
   conceptually supported by sizing; expose `renderScale` on `BevySceneWidget` + `BevyScene.build`).
3. **fps throttle + `interactive:false`:** ensure the widget can run at a target fps and disable
   its own gesture handling (the TPS drives the camera from JS), so HUD/controls overlay on top.
4. **Frustum cull / tiled raster:** confirm the Rust renderer culls off‑screen static geometry;
   keep the native `rayon` tiled rasterizer path.

**Verification:** `cargo test`; micro‑bench via `rust/benches/render.rs` (static‑bake win).
**Acceptance:** re‑sending only the dynamic `world` each frame does **not** re‑bake the city;
frame time with the full downtown is within budget; `renderScale<1` visibly reduces fill cost.
**Commit + push.**

---

### P4 — Widget/registry, viewport & overlay wiring
Make `BevyScene` a drop‑in for `GameScene` in the JSON DSL.

**Subtasks**
1. **`BevySceneWidget.build` props:** accept `scene` (with `staticWorld`/`staticKey`), `width`,
   `height`, `fps`, `interactive`, `renderScale`, `sceneKey`, transparent background — matching
   `GameSceneWidget.build`'s prop surface.
2. **Registry:** confirm `BevyScene`/`Bevy3D` map to the enhanced widget
   (`lib/src/core/elpian_engine.dart`); optionally add a `BevyGameScene` alias for clarity.
3. **Transparent layering:** ensure the 3D layer composes under the 2D HUD `Stack` (no opaque
   background swallowing the overlay), matching the current `GameScene` usage.
4. **Viewport:** the JS reads `__ELPIAN_HOST_ENV__.viewport`; verify the Bevy path sizes its
   buffer from the same width/height the JS passes (it already passes `width`/`height`).

**Verification:** `dart analyze` (best‑effort); render the `bevy_scene_example` mixed‑UI demo.
**Acceptance:** swapping `type:"GameScene"` → `type:"BevyScene"` in a scene node renders the same
content with the HUD intact.
**Commit + push.**

---

### P5 — Rewrite the TPS example on `BevyScene`
**Subtasks**
1. **New program/page:** create `example/lib/examples/tps_game_bevy_example.dart` (page) and
   either (a) parameterize `tps_game_program.dart` to emit `BevyScene` instead of `GameScene`,
   or (b) fork a `tps_game_program_bevy.dart`. **Prefer (a)** with a single constant
   (`SCENE_WIDGET = 'BevyScene'`) so logic stays shared and maintained in one place.
2. **DSL field shims:** verify every material/mesh/env/light/model field the program emits is now
   honored by the Bevy schema (P1/P2). Add serde aliases rather than editing the game where names
   differ (e.g. `segments`↔`subdivisions`).
3. **Scene node:** change the `buildTree()` 3D node from
   `{type:'GameScene', props:{scene:'__SCENE__', ... renderScale:0.7, fps:30, interactive:false}}`
   to `{type:'BevyScene', props:{...same...}}`. Keep the `__SCENE__` splice + `staticWorld` payload.
4. **Wire route:** add the new page to `example/lib/main.dart` (and, if appropriate, make it the
   home route or a sibling toggle next to the existing impeller TPS for A/B comparison).
5. **Loading/UX parity:** reuse `_GameLoading`; keep the dusk look, controls, minimap, banners.

**Verification:** `dart analyze` (best‑effort); build the example (CI/user machine); visual A/B
vs the original `GameScene` TPS.
**Acceptance:** the TPS plays identically (movement, auto‑aim, firing, waves, pickups, ambient
life, streamed models) using **only** `BevyScene`. The original impeller version still builds.
**Commit + push.**

---

### P6 — Build, verify, optimize, document
**Subtasks**
1. **Builds:** `cargo build --release` (native) and the **WASM** build used by web
   (`.github/workflows/` shows the wasm‑pack/deploy pipeline — keep it green).
2. **Tests:** `cargo test` all green; `flutter analyze` + `flutter test` (CI/user machine);
   update/extend `test/` and `rust/tests/` for new features.
3. **Performance pass:** profile the full downtown on the Bevy path; tune static bake, frustum
   cull, `renderScale`, tiled raster; record numbers in `benchmarks/` like the existing
   `TPS_OPTIMIZATION_PLAN.md` did.
4. **Docs:** update `README.md`, `3D_GRAPHICS.md` (new material/env/light/model3d fields),
   and add a short "Bevy TPS" note; cross‑link this plan. Update the capability matrix to all‑✅.
5. **Cleanup:** remove dead shims, ensure no regression to the impeller `GameScene` path.

**Acceptance:** native + WASM build; all tests green; docs updated; gap matrix fully ✅;
the Bevy TPS is the showcase example.
**Commit + push.**

---

## 6. File inventory (where work lands)

**Rust (primary path)**
- `rust/src/bevy_scene/schema.rs` — material/env/light/mesh fields, `Model3DNode` *(P1,P2)*
- `rust/src/bevy_scene/renderer.rs` — shading, textures, sky, fog, skinning, raster *(P1,P2,P3)*
- `rust/src/bevy_scene/manager.rs` — static bake/cache, scene lifecycle *(P3)*
- `rust/src/bevy_scene/gltf/` *(new)* — GLB parse, skinning, model cache, net bridge *(P2)*
- `rust/src/api/bevy_ffi.rs`, `rust/src/api/bevy_wasm_ffi.rs` — model‑bytes bridge calls *(P2)*
- `rust/tests/renderer_golden.rs`, new tests — feature/golden coverage *(P1,P2,P3)*
- `rust/Cargo.toml` — add deps (`ureq` native fetch, `image` native decode) behind cfg *(P2)*

**Dart (widget + fallback + glue)**
- `lib/src/bevy/bevy_scene_widget.dart` — props (`renderScale`,`sceneKey`,transparent), overlay *(P3,P4)*
- `lib/src/bevy/bevy_scene_controller.dart` — `staticWorld`/`staticKey`, model bridge *(P2,P3)*
- `lib/src/bevy/bevy_scene_api.dart`, `bevy_scene_api_web.dart` — FFI/WASM surface *(P2)*
- `lib/src/bevy/dart_scene_renderer.dart` — fallback parity (materials/env/model3d) *(P1,P2)*
- `lib/src/core/elpian_engine.dart` — registry aliases *(P4)*

**Example**
- `example/lib/examples/tps_game_program.dart` — `SCENE_WIDGET` switch + field shims *(P5)*
- `example/lib/examples/tps_game_bevy_example.dart` *(new)* — Bevy TPS page *(P5)*
- `example/lib/main.dart` — route wiring *(P5)*

**Docs/bench**
- `README.md`, `3D_GRAPHICS.md`, `benchmarks/` *(P6)* · this plan *(P0)*

---

## 7. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| glTF streaming in WASM can't block on `fetch` | High (P2) | Bridge downloads through JS host; async cache; capsule placeholder. |
| New Rust deps (`ureq`,`image`) break WASM build | Med | `cfg(not(target_arch="wasm32"))`‑gate them; WASM gets bytes pre‑decoded via host. |
| Visual drift between Rust path and impeller `GameScene` | Med | Golden tests + side‑by‑side A/B page; tune shading constants to match. |
| Flutter not runnable in sandbox | Med | Lean on `cargo test` + `dart analyze`; defer widget runtime checks to CI/user; state this in commits. |
| Static‑cache invalidation bugs (stale city) | Med | Key by `staticKey`; bump version on geometry change; unit‑test re‑splice path. |
| Scope creep in P2 | High | Allow web to keep the Dart‑fallback glTF while native uses the new Rust pipeline (see §3 open question). |

---

## 8. Conventions

- One phase ≈ one logical PR's worth of work; **commit + push at each phase boundary** (sub‑commits
  welcome inside P2).
- Keep JSON DSL field names stable; extend the **schema**, not the game, via serde aliases.
- Match surrounding code style (Rust idioms in `bevy_scene`, Dart idioms in `lib/src`).
- Update the **Status board** (§4) and the **gap matrix** (§2) as features land.
- Never regress the existing impeller `GameScene` TPS — it stays as the A/B baseline until P6.
