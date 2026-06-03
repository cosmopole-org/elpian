# E — Flutter engine config: Impeller + shader warmup + image cache

**Risk:** Low · **Verifiable here:** ⚠️ inspection only · **Effort:** 0.5 day · **ROI:** Eliminates first-use shader jank

> No Flutter SDK in container. These are per-platform build-config + small Dart additions.
> Verify on real devices.

## Background
**Impeller is Flutter's renderer** — it draws *all* Elpian content (2D UI, Canvas, and the
Dart 3D fallback's `CustomPaint`, and the Rust path's `drawImageRect`). There is no separate
"3D Impeller engine"; the goal here is to (a) make sure Impeller is the active backend where
beneficial, (b) precompile shaders to avoid first-frame compilation stalls, and (c) cache
image decodes. Audit found **no Impeller flags and no SkSL warmup** in `example/`.

## E1 — Impeller enablement (per platform)
- iOS/macOS: Impeller is default on recent Flutter; ensure not disabled. (`Info.plist`
  `FLTEnableImpeller` — only set to control it explicitly.)
- Android: Impeller (Vulkan) is default on recent stable; verify the example's
  `AndroidManifest.xml`/Flutter version. Test on a mid GPU device.
- Windows/Linux/macOS desktop & Web: confirm behavior on your target Flutter (web uses
  CanvasKit/Skia or the new renderer — validate the 3D `drawImageRect` path there).
- [ ] Document the chosen setting per platform in this file once tested. Do NOT hard-disable
      Impeller globally; measure first.

## E2 — Shader/SkSL warmup
Common expensive shaders here: gradients (`elpian_animated_gradient`, CSS gradients),
`ShaderMask` (`elpian_shimmer`), blurs/shadows. First use triggers compilation jank.
- [ ] Capture an SkSL bundle: run the app exercising gradient/shadow/shimmer screens with
      `flutter run --profile --cache-sksl --purge-persistent-cache`, then
      `flutter build <platform> --bundle-sksl-path=flutter_01.sksl.json`.
- [ ] Wire the warmup so common shaders compile at startup (reduces jank on first animation).
- [ ] Note: under Impeller, SkSL warmup semantics differ (Impeller precompiles its own set).
      Validate whether warmup is still needed on each backend; keep it where it helps.

## E3 — Global image cache tuning
- [ ] Pair with `D5` (`ResizeImage`/`cacheWidth`). Optionally tune
      `PaintingBinding.instance.imageCache.maximumSizeBytes` for image-heavy apps.

## E4 — Frame-transfer paint hints (ties to F)
- [ ] In `_BevyScenePainter` (`bevy_scene_widget.dart:439`), set `FilterQuality.none` (or `low`)
      when source≈destination size (`medium` adds sampling cost). Wrap the 3D layer in
      `RepaintBoundary` so 3D frames don't invalidate the 2D UI.

## E5 — Release build guidance (docs)
- [ ] Android: `flutter build apk --release --split-per-abi` (or appbundle) to cut size.
- [ ] Profile with DevTools (raster/UI thread, "Track widget builds", shader compilation overlay).

## Cross-platform notes
- Impeller availability/behavior varies by platform & Flutter version — **measure per platform**,
  don't assume. Web especially: validate the image-blit 3D path and shader behavior separately.

## Verification (real devices)
- [ ] First-run animation (shimmer/gradient) shows no compile stutter after warmup.
- [ ] DevTools: no shader-compilation spikes; raster thread within budget.
- [ ] 3D layer composites correctly with 2D UI on all platforms; `RepaintBoundary` isolates repaints.

## Rollback
Remove warmup bundle/flags; revert paint-quality hints. Config-only.
