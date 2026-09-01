# Dart inspection-level changes (C / D5 / E4 / F1-partial)

**Date:** 2026-06-03 · **Status:** applied by inspection — **NOT compiled/tested**
(no Flutter SDK in the container). Must pass `flutter analyze` + `flutter test` +
device profiling before merge, per each workstream's Verification section.

## Applied
- **E4 / F1 (frame blit)** — `lib/src/bevy/bevy_scene_widget.dart`
  `_BevyScenePainter` now reuses a single static `Paint` (no per-frame allocation)
  and drops `FilterQuality.medium` (mipmapped, costly) to `none` when blitting ~1:1
  and bilinear `low` only when scaling. `build()` already wraps in `RepaintBoundary`.
- **C (Canvas 2D)** — `lib/src/canvas/canvas_api.dart`
  - `clearRect`: replaced `saveLayer(... BlendMode.clear)` + `restore()` (offscreen
    layer) with a single `drawRect` using a static `BlendMode.clear` paint.
  - Font parsing: added a `_ParsedFont` cache so the `font` string is split/scanned
    once per distinct value instead of on every `fillText`/`strokeText`.
- **D5 (image decode cache)** — `lib/src/html_widgets/html_img.dart`,
  `lib/src/widgets/elpian_image.dart`: pass `cacheWidth`/`cacheHeight` derived from the
  styled width/height so large source images decode at display size, not native res.

## Deliberately NOT done here (need Flutter verification or are higher-risk)
- **F1 async path**: reuse one `Uint8List` in `getFrameDirect` + replace async
  `decodeImageFromPixels`+`setState` with a `Listenable` repaint. Buffer lifetime vs
  async decode is easy to get wrong without on-device testing.
- **F2 web fast path**: switch web to `elpian_bevy_wasm_get_frame_bytes` (raw bytes)
  off the base64/JSON route. (Rust side already exposes the bytes API; A5 cleaned up
  base64.)
- **B** Dart 3D fallback (Path reuse, swap-and-pop, repaint Listenable),
  **D1–D4/D6** CSS memoization / merge / immutability+keys / layout / animated allocs,
  **E1/E2** Impeller flags + SkSL warmup, **C** paint-color cache + shadow decision.
- **A6** VM value-model migration (locally verifiable but a multi-day, high-risk
  refactor across the 4906-line executor — deferred to a focused effort).

Rationale: these touch the core styling/VM/async-frame paths where an unverified
change can cause visual or behavioral regressions this container cannot catch.
