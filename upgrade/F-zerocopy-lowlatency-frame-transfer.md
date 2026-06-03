# F — Minimal-copy, low-latency 3D→2D frame transfer

**Risk:** Med · **Verifiable here:** ⚠️ mixed (Rust side ✅, Dart side inspection) · **Effort:** 1–2 days

## Current state (the problem) — confirmed by audit
Per native frame the Rust pixel buffer reaches the screen via **2 CPU copies + async latency**:
1. Rust renders into `renderer.pixels`.
2. `bevy_scene_api.dart:268`: `Uint8List.fromList(ptr.asTypedList(size))` → **copy #1 (CPU→CPU)**.
3. `bevy_scene_widget.dart:276`: `ui.decodeImageFromPixels(...)` **async** → **copy #2 (CPU→GPU)**
   + callback `setState` (`:281-291`) → **~1 frame latency + full subtree rebuild**.
4. `bevy_scene_widget.dart:439`: `drawImageRect(..., FilterQuality.medium)`.

Web is worse: `getFrameJson` (`bevy_scene_api.dart:283`) ships pixels as **base64 in JSON**.

> True zero-copy (no CPU→GPU upload at all) is **impossible for a CPU rasterizer** — bytes
> live in CPU RAM and must be uploaded once. The practical floor is **one** upload, no Dart-heap
> copy, synchronous (no extra frame latency). That is F1/F2. For genuine zero-copy you need GPU
> rendering + external textures → see optional `G`.

## F1 — Native: remove copy #1 + remove async latency
Prereq: **A5 double-buffer** (so the front buffer Dart reads isn't overwritten mid-frame).

Files: `lib/src/bevy/bevy_scene_api.dart` (`getFrameDirect` `:253-279`),
`lib/src/bevy/bevy_scene_widget.dart` (`_updateImage` `:272-294`),
`lib/src/bevy/bevy_scene_controller.dart` (frame getter).

- [ ] **Remove copy #1:** with double-buffering, hand the native data straight to image
      creation without `Uint8List.fromList`. Either pass `ptr.asTypedList(size)` (a view), or
      copy **once** into a single reused `Uint8List` field (avoids per-frame allocation). Do NOT
      allocate a fresh list each frame.
- [ ] **Remove async + setState latency:** replace `decodeImageFromPixels` (async callback) with
      **synchronous** image creation:
      ```dart
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes); // or keep view if lifetime safe
      final desc = ui.ImageDescriptor.raw(buffer, width: w, height: h,
          pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await desc.instantiateCodec();
      final frame = await codec.getNextFrame();
      _currentImage = frame.image; // paint same frame; no extra setState round-trip
      buffer.dispose(); codec.dispose();
      ```
      Drive the repaint via a `Listenable` on the `CustomPaint` (like `B`) rather than `setState`,
      so the 3D image swap doesn't rebuild the widget subtree. (Note: these `ui` calls are
      `Future`-based but resolve quickly; structure the ticker so the latest frame is painted
      without dropping to the next vsync where possible. If a fully sync path is required,
      `decodeImageFromPixels` remains acceptable but keep the buffer reused.)
- [ ] **Isolate compositing:** wrap the 3D widget subtree in `RepaintBoundary`; set
      `FilterQuality.none/low` when src≈dst (`bevy_scene_widget.dart:439`).
- [ ] Dispose the previous `ui.Image` exactly once (current code does at `:290`).

## F2 — Web: drop base64/JSON, use raw bytes
Files: `lib/src/bevy/bevy_scene_api_web.dart`, `assets/web_runtime/elpian_wasm_loader.js`,
`rust/src/api/bevy_wasm_ffi.rs` (`get_frame_bytes` `:64` already exists).
- [ ] Use `elpian_bevy_wasm_get_frame_bytes` → `Uint8List` (no base64, no JSON parse) instead of
      `get_frame`/`getFrameJson`.
- [ ] Build the image via `createImageBitmap`/`ImageData` (web) or `ui.ImmutableBuffer` path.
- [ ] Remove/deprecate the base64 `get_frame` JSON route for the hot path (keep only if a debug
      fallback is wanted). Pairs with A5's `base64` crate cleanup.

## Cross-platform notes (see `X`)
- F1 is native-only (FFI). F2 is web-only. The Dart 3D fallback path (no FFI) already paints
  geometry directly (no image copy) — only fix its repaint driving in `B`.
- Verify `ImageDescriptor.raw` + `rgba8888` works on every target Flutter/web backend.

## Verification
- Rust side (here): A5 double-buffer pointer-validity test (front buffer stable across next render).
- Dart side (real machine):
  - [ ] `flutter run --profile` a 3D demo; DevTools shows fewer allocations and lower
        UI-thread time per frame; measure input→display latency improvement.
  - [ ] Visual parity; no tearing/flicker (double-buffer correctness).
  - [ ] Web: confirm raw-bytes path renders and is faster than base64 route.

## Rollback
Restore `Uint8List.fromList` + `decodeImageFromPixels` + `setState`; restore web JSON path.
Independent of the Rust render optimizations.
