# 🎮 Elpian Game Platform Roadmap

**Goal:** evolve Elpian from a JSON-driven UI + 3D scene renderer into a complete, high-performance
game platform capable of hosting Roblox-class games (user-created multiplayer 3D experiences with
scripting, physics, audio, avatars, and an asset economy).

This document contains three parts:

1. **State of the engine** — what exists today, verified against the code (June 2026).
2. **Audit results** — bugs found and fixed in the 3D pipeline (both renderers).
3. **The roadmap** — a phased, complete plan to Roblox-class feature parity, with acceptance
   criteria and performance budgets per phase.

---

## Part 1 — State of the Engine

### 1.1 The three rendering paths (and an important clarification)

| Path | Code | What it actually is |
|---|---|---|
| **scene3d / GameScene** | `lib/src/scene3d/` | Pure-Dart software rasterizer drawing through Flutter `Canvas` (Impeller-backed on the GPU only for final blit/compositing). CPU vertex transform, CPU lighting, CPU triangle fill. The *reference implementation* — richest feature set: physics, particles, glTF + skeletal skinning, static-world baking. |
| **"Bevy" Rust renderer** | `rust/src/bevy_scene/` | **Not Bevy.** Despite the module name and docs ("rendered via Bevy (Rust/GPU)"), `rust/Cargo.toml` has no Bevy dependency. It is a custom multithreaded **CPU software rasterizer** (glam + rayon tiled fill, double-buffered RGBA output) delivered to Flutter via FFI pixel buffers (native) or WASM (web). Fast for what it is, but it is not GPU scene rendering. |
| **Dart fallback** | `lib/src/bevy/dart_scene_renderer.dart` | A second, simpler pure-Dart rasterizer used by `BevyScene` when the Rust library is unavailable. |

**Consequence:** every triangle in an Elpian 3D scene today is shaded on the CPU. This is the
single biggest gap between Elpian and any production game platform, and it drives Phase 1 of the
roadmap. The documentation should stop describing the Rust path as "Bevy/GPU" until it is.

### 1.2 Verified capability inventory

| Category | Have today | Missing for Roblox-class |
|---|---|---|
| **Rendering** | 13 mesh primitives, PBR-ish materials (base color/metallic/roughness/emissive/alpha), procedural textures, gradient sky, linear+exp fog, glTF/GLB streaming, static-world baking, frustum culling, render-scale | **GPU pipeline**, real shadow maps (Dart paths have none), image textures in Rust path, normal maps, post-processing (bloom/AA/grading), LOD, instancing, reflections, decals |
| **Animation** | 10 procedural types (Rotate…Spin), 8 easings, glTF skeletal skinning + clips (LINEAR/STEP/CUBICSPLINE), `delay` | Blend trees / state machines, cross-fade, IK, ragdoll, animation events, root motion |
| **Physics** | Dart scene3d only: gravity, rigid bodies, sphere/box/plane colliders, restitution/friction | Physics in the Rust path (**none today**), mesh/compound colliders, raycasts, joints, CCD, kinematic character controller, vehicles, ragdoll |
| **Scripting** | Sandboxed Rust bytecode VM (FFI + WASM), custom AST language, QuickJS runtime, host-call bridge, `render`/`updateApp` | Runtime scene-graph API (today scripts must resend whole scene JSON), physics/audio/input/timer APIs from scripts, Lua or TS as the user-facing language, server/client script separation, debugging |
| **Input** | Tap/double-tap/long-press on scenes, 40+ event types in the 2D layer | 3D ray picking → script events, keyboard/mouse capture in-world, **gamepad**, action mapping/rebinding, mobile virtual sticks (exists only hand-rolled in TPS example) |
| **Audio** | **Nothing** | Everything: SFX, music, 3D spatial audio, attenuation/occlusion, streaming |
| **Networking** | HTTP asset fetch only | Everything: client-server sessions, state replication, RPC, interest management, persistence (DataStore equivalent), matchmaking, voice |
| **Assets** | glTF/GLB from URL/data-URI with per-URL cache, placeholder during load | Asset bundles/addressables, texture/audio pipeline, VRAM budgets, eviction, content catalog, moderation pipeline |
| **UI in game** | Strong: full HTML/CSS/Flutter-DSL/Canvas2D overlay (`ui` array) + event system | Spatial (in-world) UI panels, gamepad navigation of UI |
| **Particles/VFX** | CPU emitters: 5 shapes, color/size/alpha over life, gravity/wind, bursts, prewarm (scene3d). Rust path: rudimentary cube-scatter only | GPU particles, trails, ribbons, decals, mesh particles, collision, vortex/turbulence |
| **Terrain** | Single heightmap mesh primitive | Chunked/streamed terrain, voxel editing (Roblox terrain), splatting, water |
| **Tooling** | FPS cap, render-scale, static-key baking, benchmarks (`criterion`) | Frame profiler, draw stats overlay, scene inspector, hot-reload editor loop, memory dashboards |

### 1.3 Verdict: can a Roblox-class game be built on Elpian today?

**Not yet.** A single-player, low-poly, tap-driven 3D experience with HUD — yes (the TPS example
proves it). A Roblox-class game — defined as *user-scripted, multiplayer, physics-driven 3D with
audio on consumer devices* — is blocked by five hard gaps, in order of severity:

1. **No GPU scene rendering** — CPU rasterization caps practical scenes at roughly 10–50k
   triangles at 30 fps on mobile; Roblox-class worlds need 1–5M visible triangles at 60 fps.
2. **No networking/multiplayer layer** of any kind.
3. **No audio** of any kind.
4. **No runtime scene API for scripts** — resending whole-scene JSON per mutation cannot scale
   to thousands of live objects.
5. **No physics in the primary (Rust) renderer**, and the Dart physics is a toy
   (3 collider types, no raycasts, no character controller).

Everything else (animation blending, terrain, tooling, asset economy) is important but
incremental once those five are addressed. The roadmap below covers all of it.

---

## Part 2 — Audit Results (this pass)

Both renderers were audited end-to-end. **13 issues found; 12 fixed in this change, 1 documented.**

### Fixed — Rust renderer (`rust/src/bevy_scene/`)

| # | Severity | Issue | Fix |
|---|---|---|---|
| R1 | **Critical** | 5 of the 10 documented animation types (`Orbit`, `Swing`, `Shake`, `Float`, `Spin`) and 3 of 8 documented easings (`Elastic`, `Back`, `Sine`) were missing from the serde schema. Because scene parsing is all-or-nothing, **one documented animation anywhere in a scene made the entire scene render nothing**. | Added all variants to `schema.rs` with doc-matching defaults; implemented them in `renderer.rs` with semantics identical to scene3d's `core.dart`. |
| R2 | **Critical** | `Translate` animation **replaced** the node's base transform instead of composing with it — an animated node lost its position/rotation/scale. | `Mat4::from_translation(pos) * base_mat` (parity with scene3d). |
| R3 | **Critical** | Malformed glTF with joint/weight arrays shorter than the vertex count **panicked** (`prim.joints[v]` out of bounds) instead of degrading gracefully. | Skinning now requires `joints.len() >= vcount && weights.len() >= vcount`, else rigid-pose fallback. |
| R4 | Major | `camera.animation` was parsed but never applied — animated cameras (flythrough, shake) silently did nothing. | `find_camera` now runs `compute_animated_transform`. |
| R5 | Major | `light.animation` was parsed but never applied. | `collect_lights` now runs `compute_animated_transform`. |
| R6 | Major | Documented light type `Area` was missing from the enum → any scene using it failed to parse entirely. | Added `Area`, shaded as a point source. |
| R7 | Major | Easing curves diverged from the reference renderer (quadratic vs cubic; `Bounce` mirrored), so the same JSON animated differently per renderer. | Aligned to `core.dart` curves; documented the parity contract in code. |
| R8 | Minor | `animation.delay` (documented, supported by scene3d) was ignored. | Added to schema and honored. |
| R9 | Minor | `ambient_color` (the documented key) was not accepted — only `ambient_light`. | serde alias. |
| R10 | Documented | `get_frame_data` returns a raw pointer whose buffer can be swapped by the next render. | Already double-buffered and the lifetime contract is documented at the call site; the safe `get_frame_snapshot` path exists for cross-thread use. No change. |

### Fixed — Dart renderers (`lib/src/scene3d/`, `lib/src/bevy/`)

| # | Severity | Issue | Fix |
|---|---|---|---|
| D1 | **Critical** | Particle nodes **never worked from documented JSON**: the parser looked for a nested `emitter` object plus keys `shape`/`emit_rate`, while the docs (and Rust schema) put `emitter_shape`/`emission_rate` flat on the node. Shape names were also compared case-sensitively against a lowercase map, so `"Cone"` parsed as `Point`. | Parser reads flat node fields per the docs (nested `emitter` kept as legacy alias), accepts both key spellings, matches shapes case-insensitively, and uses the documented default rate (10/s, was 20). |
| D2 | Major | Fallback renderer: same `Translate`-replaces-base-transform bug as R2. | Same fix. |
| D3 | Major | Fallback renderer: missing `Orbit`/`Swing`/`Shake`/`Float`/`Spin`, missing `Elastic`/`Back`/`Sine`, divergent curve shapes, `Bounce` default height 1.0 vs reference 1.5, no `delay`. | Full parity with `core.dart`, including `Spin`'s Rz·Ry·Rx Euler order. |
| D4 | Major | Fallback renderer ignored camera and light `animation`. | Both now build the full animated transform and extract position/basis from it. |
| D5 | Minor | `ambient_color` not accepted by either Dart parser. | Both accept `ambient_color` with `ambient_light` fallback. |

### Verification

- `cargo check` clean; full Rust suite green (**39 tests across 10 suites**), including a new
  `tests/animation_parity.rs` with 4 regression tests covering R1/R2/R4 (every documented
  animation type and easing parses and renders; Translate preserves base transform; camera
  animation is applied).
- Dart changes are API-verified by inspection; **Flutter is not available in this environment**,
  so `flutter analyze`/`flutter test` must run in CI on this branch before merge.

### Known issues deliberately *not* changed

- Skinned-normal transformation uses the blended joint matrix directly (not inverse-transpose);
  correct results require uniformly-scaled bones. This matches industry practice for real-time
  skinning; fixing it costs a per-vertex matrix inverse. Revisit when bones with non-uniform
  scale appear in practice (same caveat applies to non-uniformly scaled static meshes).
- The Rust path's particle rendering is a placeholder (time-scattered cubes) and does not honor
  most emitter fields. Real parity lands with the VFX phase (Phase 9) — flagged in docs.

---

## Part 3 — The Roadmap to a Roblox-class Platform

Ordering principle: **unblock the five hard gaps first** (GPU, scene API, physics, audio,
networking), because every later feature builds on them. Phases are sequential where dependent,
parallelizable where not (marked ∥).

### Phase 0 — Foundation hardening (1–2 weeks) ✅ partially done in this pass

The schema is currently defined three times (scene3d parser, Rust serde, fallback parser) and the
three copies drift — that is exactly what produced bugs R1–R9/D1–D5.

- **0.1** Single source of truth for the scene schema: a JSON-Schema file in `/schema`, with
  conformance tests on all three parsers against a shared corpus of scene fixtures.
  *Acceptance: one fixture corpus, three parsers, zero divergence; CI fails on drift.*
- **0.2** Make Rust scene parsing **fault-isolating**: an unknown node/field skips that node with
  a diagnostic instead of failing the whole scene (today: one typo = black screen).
- **0.3** CI: `flutter analyze` + `flutter test` + `cargo test` + golden-image tests for both
  renderers on every PR (goldens exist for Rust; add Dart).
- **0.4** Rename or re-document the `bevy_scene` module honestly (it is a software rasterizer)
  to stop downstream confusion. Keep the public widget names stable.
- **0.5** Cross-renderer animation/easing parity tests in Dart mirroring `animation_parity.rs`.

### Phase 1 — GPU rendering core (the big one; 2–4 months)

Replace CPU rasterization with a real GPU pipeline while keeping the JSON scene contract stable.

- **1.1 Decide the backend (week 1):**
  - **Option A (recommended): actually adopt Bevy** (`bevy_render`/`bevy_pbr` subset, headless,
    render-to-texture) — mature PBR, shadows, glTF, skinning, and a path to its ecosystem
    (avian physics, bevy_audio, etc.). Heavier binary (~10–20 MB), longer compile.
  - **Option B: hand-rolled wgpu** — smallest binary, full control, but re-implements shadows,
    PBR, skinning, post-FX (~6+ extra months of effort over time).
  - Web: both compile to WASM + WebGPU (WebGL2 fallback).
- **1.2 Zero-copy frame delivery into Flutter:** native `Texture` widget backed by a shared GPU
  texture (Android: `SurfaceTexture`/AHardwareBuffer; iOS/macOS: `CVPixelBuffer`/Metal shared;
  Windows: D3D11 shared handle; Linux: dmabuf; Web: offscreen canvas). The current
  per-frame RGBA memcpy → `decodeImageFromPixels` path is the #2 bottleneck after rasterization
  itself. *Acceptance: 1080p frame delivery < 1 ms, zero per-frame heap allocation.*
- **1.3 Feature parity port:** all 13 primitives, materials, procedural textures, fog/sky,
  the 10 animations, glTF + skinning, particles. Keep the software rasterizer as the
  automatic fallback (it already is) — it becomes the "compatibility" tier.
- **1.4 Beyond parity:** real shadow maps (cascaded for directional), image textures +
  normal/roughness/AO maps, HDR + bloom + tonemapping, MSAA/TAA, GPU instancing
  (`instances` array on `mesh3d`), LOD groups, point/spot shadow atlases.
- *Performance acceptance: 1M-triangle scene, 100 dynamic lights culled, 60 fps on a 2022
  mid-range phone (e.g., Snapdragon 778G) at native res; 120 fps desktop.*

### Phase 2 — Runtime scene graph & scripting API (∥ with Phase 1 after 1.1; 6–8 weeks)

Scripts must mutate a *live* scene, not resend JSON documents.

- **2.1 Retained scene store in Rust** keyed by node `id`: `spawn(json)`, `destroy(id)`,
  `set(id, patch)`, `get(id)`, `query(selector)`, parent/reparent. Exposed to the VM, QuickJS,
  and Dart through one C ABI. Dirty-flagging drives incremental GPU updates (no full rebuilds).
- **2.2 Event flow out of the world:** ray-picking (`onClick`/`onHover` per node), collision
  events, animation-finished, timers (`setTimeout`/`setInterval` in the VM), per-frame `onTick`.
- **2.3 User-facing language decision:** keep the AST VM as the compile target, but adopt
  **Luau or TypeScript→AST** as the authoring language (Roblox developers expect Luau; the
  `pending-work/jsx-compiler` + acorn work suggests TS/JS is the natural fit for Elpian).
- **2.4 Script lifecycle:** module imports, per-scene sandbox quotas (instruction budget already
  exists in the VM), hot reload preserving state where possible.
- *Acceptance: 60 fps with 5,000 script-driven node mutations/frame; spawn/destroy 1,000
  nodes/frame without hitching.*

### Phase 3 — Physics (∥ with Phase 2; 6–8 weeks)

- **3.1 Adopt Rapier (or Avian if Bevy chosen)** in the Rust core — native + WASM proven.
  Retire the toy Dart physics or keep it for the fallback tier only.
- **3.2 Colliders:** box/sphere/capsule/cylinder/convex/trimesh/heightfield; compound; physics
  materials (friction/restitution); collision groups & masks.
- **3.3 Queries & joints:** raycast/shapecast/overlap from scripts; fixed/revolute/prismatic/
  spherical/rope joints; motors.
- **3.4 Kinematic character controller** (slide, step-offset, slope limit, jump, push) — the
  Humanoid-equivalent primitive every Roblox-class game needs.
- **3.5 Determinism & networking prep:** fixed-timestep simulation with interpolation toward
  render time (`physics_hz: 60` in scene JSON).
- *Acceptance: 2,000 active rigid bodies at 60 fps mobile; character controller demo over the
  TPS map; raycast API < 50 µs for 10k-collider scenes.*

### Phase 4 — Input system (∥; 3–4 weeks)

- **4.1 Action mapping layer:** named actions (`"jump"`, `"fire"`) bound to keyboard, mouse,
  touch, and **gamepad** (via Flutter `gamepads`/`RawKeyboard` + native fallbacks); scripts read
  actions, never raw codes; user rebinding supported.
- **4.2 In-world picking** unified across renderers (GPU id-buffer picking in Phase 1 backend;
  ray-vs-AABB in software tier) feeding `2.2` events.
- **4.3 Built-in mobile controls:** virtual joystick + buttons as schema-level UI nodes
  (today they're hand-rolled per example).
- **4.4 Camera rigs as engine primitives:** orbit/follow/first-person/shoulder with collision
  (camera-occlusion raycast from 3.3), configurable in JSON, scriptable.

### Phase 5 — Audio (∥; 3–4 weeks)

- **5.1 `kira` (Rust) as the engine mixer** — native + WASM; `audio` scene node:
  `{type:"audio", src, spatial, loop, volume, range, doppler}` attached to any node.
- **5.2 3D spatialization:** distance attenuation, panning, optional occlusion via physics rays.
- **5.3 Script API:** play/stop/fade/pitch; music ducking; per-group volume buses.
- **5.4 Asset pipeline:** OGG/MP3 streaming for music, in-memory for SFX, same cache/URL
  semantics as glTF.
- *Acceptance: 64 simultaneous spatial voices < 2 ms mixer time on mobile.*

### Phase 6 — Asset platform (∥ after 2.1; 4–6 weeks)

- **6.1 Unified asset server client:** content-addressed URLs, LRU disk+RAM caches with byte
  budgets, priority/preload API, progressive (placeholder → full) loading — generalize what
  `GltfModelCache` does to textures/audio/scenes/scripts.
- **6.2 Bundles:** a `.elpk` pack format (zip + manifest) so a "game" is one downloadable unit;
  signature + version fields for moderation/updates.
- **6.3 Catalog service contract** (IDs → bundles) — the seed of the Roblox-style economy; the
  server side is out of engine scope but the client contract is defined here.
- **6.4 Avatar spec:** standard rig skeleton + attachment points so user avatars/cosmetics work
  across games (Roblox's R15 equivalent), building on the existing glTF skinning.

### Phase 7 — Networking & multiplayer (after 2 + 3; 2–3 months)

- **7.1 Transport:** WebSocket everywhere first (works on web), QUIC/WebTransport upgrade later.
- **7.2 Authoritative server:** run the same Rust core (scene store + physics + VM) headless on
  the server; the existing VM sandboxing becomes the server-script container. Client = renderer
  + input + prediction.
- **7.3 Replication:** snapshot + delta compression of the retained scene store (2.1 makes this
  tractable: dirty flags are the delta source); interest management (only replicate what the
  client can see); client-side prediction + reconciliation for the local character (3.4).
- **7.4 RPC + events:** `fireServer`/`fireClient`/`fireAllClients` mirroring RemoteEvent.
- **7.5 Persistence:** key-value DataStore API with per-game quotas (server-side contract).
- **7.6 Sessions:** join/leave, player identity hooks, server browser/matchmaking contract.
- *Acceptance: 30 players, 1,000 replicated dynamic objects, < 64 kbps/client median, playable
  at 150 ms RTT with prediction.*

### Phase 8 — World systems (after 1; 6–8 weeks)

- **8.1 Chunked terrain:** quadtree heightmap streaming with LOD + texture splatting (the
  existing heightmap primitive becomes one chunk).
- **8.2 Voxel terrain (Roblox parity):** sparse voxel grid, marching-cubes mesher, runtime
  dig/build edits replicated via 7.3, material per voxel.
- **8.3 Water** (animated surface + post fog underwater), **day/night** (animated sun + sky).
- **8.4 Vegetation/instancing scatter** layered on GPU instancing from 1.4.

### Phase 9 — VFX (after 1; ∥ with 8; 4 weeks)

- **9.1 GPU particle systems** honoring the *existing* emitter schema (compute shader; 100k
  particles mobile), replacing the Rust placeholder; collision vs depth buffer.
- **9.2 Trails/ribbons/beams**, mesh particles, soft particles, decals.
- **9.3 Animation upgrades:** blend trees + state machine node (`animator`), cross-fade, IK
  (two-bone + look-at), ragdoll (3.x joints), animation events into 2.2.

### Phase 10 — Tooling & developer experience (continuous; dedicated 4–6 weeks)

- **10.1 Debug overlay:** frame time breakdown (sim/anim/cull/record/GPU), draw calls,
  triangles, memory, network graphs — toggleable from JSON or hotkey.
- **10.2 Scene inspector:** live tree of the retained store, click-to-select via picking,
  property editing at runtime (works over the websocket from a desktop browser).
- **10.3 Profiler hooks:** spans exported as Chrome trace (`puffin`/`tracing` in Rust core).
- **10.4 Editor:** the long-term Roblox-Studio analogue — Flutter app composing scenes
  visually, emitting the same JSON; starts as the inspector (10.2) growing write capability.
- **10.5 Docs as contracts:** every schema field doc generated from the JSON-Schema (0.1), so
  docs can never drift from parsers again (root cause of this audit's bug crop).

### Phase 11 — Platform & trust (parallel to 7+; ongoing)

- Player accounts/identity hooks, content moderation pipeline for the catalog (6.3), abuse
  reporting, parental controls, telemetry/crash reporting, and engine-version compatibility
  policy for published games. (Mostly service-side; the engine ships the client contracts.)

### Dependency graph (critical path bolded)

```
0 → **1 (GPU)** → 8, 9
0 → **2 (scene API)** → **7 (networking)**
0 → **3 (physics)** ─┘        ↑
0 → 4 (input) ────────────────┤
0 → 5 (audio)                 │
0 → 6 (assets) ───────────────┘
10 (tooling) continuous; 11 with 7
```

**Critical path to "first real multiplayer game": 0 → 1 + 2 + 3 (parallel) → 7 → vertical slice.**
Estimated 6–9 months with 2–3 engineers; the vertical-slice milestone (one obby/shooter with
30 players, spatial audio, physics characters, user scripts) is the go/no-go gate for the
platform investment (phases 8–11).

### Performance budgets (the bar everything is measured against)

| Metric | Mobile (mid-range 2022) | Desktop |
|---|---|---|
| Frame rate | 60 fps sustained | 120 fps |
| Visible triangles | 1M | 5M |
| Draw calls (post-instancing) | ≤ 500 | ≤ 2,000 |
| Active rigid bodies | 2,000 | 10,000 |
| Script mutations/frame | 5,000 | 20,000 |
| Spatial audio voices | 64 | 256 |
| Frame delivery to Flutter | < 1 ms | < 0.5 ms |
| Cold scene load (10 MB bundle) | < 3 s | < 1 s |

Each phase lands with benchmarks in `rust/benches/` (criterion is already wired) plus on-device
frame captures, and regressions gate CI.

---

*Audit and fixes: see Part 2 tables for file-level detail. Regression coverage:
`rust/tests/animation_parity.rs` plus the existing parity/golden suites.*
