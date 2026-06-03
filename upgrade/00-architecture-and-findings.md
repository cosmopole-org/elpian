# 00 — Architecture & Investigation Findings

Reload this to rebuild the mental model. All line numbers are from the audit on
2026-06-03 (branch `claude/funny-tesla-vzF9A`); re-confirm before editing since
they may drift.

## The four rendering paths

| Path | Location | What it really is |
|------|----------|-------------------|
| **Rust "Bevy" 3D** | `rust/src/bevy_scene/` | **CPU software rasterizer** (glam math). No Bevy, no wgpu, no GPU. Writes RGBA8 `Vec<u8>`. |
| **Dart 3D fallback** | `lib/src/scene3d/`, `lib/src/bevy/dart_scene_renderer.dart` | Pure-Dart CPU software rasterizer (same role). |
| **Canvas 2D** | `lib/src/canvas/` | Command-replay over Flutter `Canvas`, with `ui.Picture` cache. |
| **HTML / CSS / Flutter-DSL** | `lib/src/core`, `lib/src/css`, `lib/src/html_widgets`, `lib/src/widgets`, `lib/src/models`, `lib/src/parser` | JSON→Widget tree, rebuilt from scratch each update; CSS re-parsed each build. |

Plus the **Elpian VM** (`rust/src/sdk/`) — a bytecode interpreter driving scripted UI,
crossing FFI via JSON. Not graphics per se but shares the Rust release profile and
affects per-frame CPU when scripts drive renders.

## Bridge / data flow

- **Native FFI:** `dart:ffi`. Lib loaded as `libelpian_vm.so` (Android/Linux),
  `elpian_vm.dll` (Windows), `DynamicLibrary.process()` (iOS/macOS static).
  See `lib/src/bevy/bevy_scene_api.dart:68` and `lib/src/vm/frb_generated/api.dart:55`.
- **Web:** prebuilt WASM in `assets/web_runtime/wasm/elpian_vm/`, wired via
  `assets/web_runtime/elpian_wasm_loader.js` (JS-interop). Web does **not** use the
  native FFI path. Rust already cfg-gates wasm: `rust/src/api/bevy_wasm_ffi.rs:5`,
  `rust/src/api/wasm_ffi.rs:3`.
- **Render loop (UI):** VM `render` host-call → Dart `setState` → `ElpianEngine.renderFromJson`
  rebuilds the **entire** widget tree (`lib/src/core/elpian_engine.dart:236`). No diffing.
- **Render loop (3D):** `Ticker` at `fps` → `bevy_scene_widget.dart:_onTick` → either
  Dart renderer `setState` (fallback) or Rust `renderFrame` + `_updateImage`.

## Rust software rasterizer — key files & hot spots

- `rust/src/bevy_scene/renderer.rs` (~1134 lines): the rasterizer.
  - `SceneRenderer { width, height, pixels: Vec<u8>, depth: Vec<f32>, elapsed_time }` at `:25`.
  - `clear()` `:54` — serial per-pixel clear.
  - `render_scene()` `:68` — per-frame entry.
  - `rasterize_triangles()` `:416` — transforms, near-plane clip, flat lighting at triangle center (`:460-462`).
  - `fill_triangle()` `:546-620` — **inner loop calls `edge_function` 3× per pixel** (`:573-575`); alpha-blend slow path `:599-615`.
  - **Per-frame mesh regen:** `generate_mesh_triangles(...)` is called every frame, and
    **100×/frame inside the particle loop** (`:401`, with `count.min(100)` cap at `:383`).
- `rust/src/bevy_scene/manager.rs` (193 lines): `Mutex<HashMap<String, SceneInstance>>`.
  - `get_frame_data()` `:103` — **zero-copy pointer** (native fast path, good).
  - `get_frame_copy()` `:118` / `get_frame_snapshot()` `:132` — **`pixels.clone()` per call** (web/snapshot).
  - `update_scene()` `:58`, `create_scene()` `:36`, `send_input()` `:157` — full `serde_json::from_str` (no delta).
- `rust/src/bevy_scene/schema.rs` (671 lines): serde scene structs.
- `rust/src/api/bevy_ffi.rs`: C FFI (`get_frame_ptr` `:111`, `get_frame_json` `:127` base64).
- `rust/src/api/bevy_wasm_ffi.rs`: wasm-bindgen (`get_frame_bytes` `:64`).
- `rust/Cargo.toml`: deps `serde_json, serde, once_cell, glam 0.29`; profile `opt-level="z"`, `lto=true`, `codegen-units=1`, `strip=true`. **No `catch_unwind` in FFI** → do not add `panic="abort"`.

## Dart frame ingestion (the copy/latency trail)

Per native frame:
1. Rust renders into `renderer.pixels`.
2. `bevy_scene_api.dart:268`: `Uint8List.fromList(ptr.asTypedList(size))` → **copy #1 (CPU→CPU)**.
3. `bevy_scene_widget.dart:276`: `ui.decodeImageFromPixels(...)` **async** → **copy #2 (CPU→GPU)** + callback `setState` → **~1 frame latency + subtree rebuild** (`:281-291`).
4. `bevy_scene_widget.dart:439`: `drawImageRect(..., FilterQuality.medium)` composites with 2D UI.

Web path: `getFrameJson` (`bevy_scene_api.dart:283`) → base64 string in JSON → decode. Heavy.

Dart 3D fallback: `_DartScenePainter.shouldRepaint => true` (`:418`); driven by `setState(() {})` each tick (`:264`).

## Dart 3D fallback renderer — hot spots

- `lib/src/scene3d/renderer.dart`: `new ui.Path()` per triangle (`:98`); `screenTris`/`screenParticles`
  lists rebuilt per frame (`:77-78`); per-triangle clip allocs (`:232-240`); `math.pow` lighting (`:361`).
- `lib/src/scene3d/core.dart`: `Mat4*Mat4` allocates `Float64List(16)` (`:259-271`); particle
  `removeAt` O(n) (`:1132-1135`); `_spawnParticle` allocates (`:1150`); `sampleTexture` (`:784`).
- `lib/src/scene3d/game_scene_widget.dart`: `shouldRepaint => true` (`:264`); ticker `setState` (`:153-164`).
- `lib/src/bevy/dart_scene_renderer.dart` (888 lines): duplicate renderer for web fallback.

## Canvas 2D — hot spots

- `lib/src/canvas/canvas_api.dart`: `TextPainter`+`TextSpan`+`TextStyle` per text command, font
  string parsed every call (`:541-573`); `_getFillPaint`/`_getStrokePaint` mutate + `withOpacity`
  per draw (`:645-660`); `clearRect` uses `saveLayer` + inline `Paint` (`:391-402`);
  `CanvasState.copy()` deep clone per `save` (`:170-193`); **shadow state stored but never rendered**
  (`:61-64`, `:133-136` — dead code).
- `lib/src/canvas/canvas_context_store.dart`: `ui.Picture` cache (good); disposes correctly (`:68,91,122`).
- `lib/src/widgets/elpian_cached_canvas.dart`: good `shouldRepaint` w/ version notifier (`:108-112`).

## HTML/CSS/Flutter-DSL — hot spots

- `lib/src/core/elpian_engine.dart`: full tree rebuild `render()/renderFromJson()` (`:236-320`);
  **CSS re-parsed every build** (`:248-267`); **double parse** Map→CSSStyle→Map→CSSStyle on merge
  (`:266-276`, `_styleToMap` `:327-370`); weak keying (`:302-317`).
- `lib/src/css/css_parser.dart`: regex color parse per build (`:177-229`); border-radius/box-shadow/
  text-shadow allocs (`:307-315`, `:459-497`); gradient objects uncached (`:526-560`); named colors
  not const (`:669`).
- `lib/src/css/stylesheet.dart`: `getComputedStyle` linear map lookups, **no memoization** (`:103-136`),
  re-parses rules every call; `GlobalStylesheetManager` singleton, no cache (`:246-312`).
- `lib/src/html_widgets/*` (79 files): builders are static funcs returning **non-const** widgets;
  `_addGap` rebuilds list + `SizedBox` each call (`html_div.dart:80-93`); `Wrap` even for plain text
  (`html_span.dart`, `html_p.dart`); ~8% const coverage (12/155).
- `lib/src/html_widgets/html_img.dart:10-12`, `lib/src/widgets/elpian_image.dart:10-12`:
  `Image.network/asset` with **no `cacheWidth/cacheHeight`/`ResizeImage`**.
- `lib/src/css/css_properties.dart`: `createTextStyle` allocs per build (`:164-179`); unconditional
  `Opacity`/`Transform`/`ClipRRect` wrapping (`:12-36`).
- Animated widgets recreate gradients/lists per frame: `elpian_shimmer.dart:74-89`,
  `elpian_animated_gradient.dart:62-88`.
- `lib/src/models/css_style.dart`: has `const CSSStyle()` (`:251`) but not `@immutable`/no `==`/`hashCode`.

## Flutter engine config

- No Impeller flags, no SkSL warmup found in `example/{android,ios,macos}`. `example/lib/main.dart`
  measures startup only. → opportunity in `E`.

## Baseline (before any change)

- `cargo build --release` OK; `cargo test --release` → **10/10 VM tests pass**
  (`rust/tests/vm_ast_integration.rs`). No renderer tests exist yet → add in `V`.
- Existing benchmark reports: `benchmarks/reports/presentmon/` (PresentMon; note demand-driven
  rendering inflates avg fps — trust p50/p99).
