# G — OPTIONAL: true GPU zero-copy via external textures

**Risk:** HIGH · **Verifiable here:** ❌ (needs devices per platform) · **Effort:** Weeks · **ROI:** Highest possible latency/throughput, but large scope

> **Do not start without an explicit go-ahead.** This changes Elpian's core design premise
> ("portable CPU software rasterizer") and is platform-by-platform engine work. F1/F2 already
> deliver the practical low-latency win for the CPU renderer. G is for when GPU-grade 3D is required.

## Objective
Eliminate the CPU→GPU upload entirely: render the 3D scene **on the GPU** and composite it
into the Flutter scene via the **`Texture` widget + platform `TextureRegistry`** (external
textures), so Flutter samples the GPU texture directly — genuine zero-copy.

## What it requires
1. **Real GPU rendering in Rust** — replace (or augment) the software rasterizer with `wgpu`
   (i.e. make "Bevy" actually GPU-backed, or adopt Bevy's render stack / a minimal `wgpu`
   pipeline). Output to a GPU texture instead of `Vec<u8>`.
2. **Per-platform texture sharing** with the Flutter engine (this is the hard part):
   - **Android:** `SurfaceTexture`/`HardwareBuffer` (AHardwareBuffer) → register via
     `TextureRegistry.SurfaceTextureEntry`; render with GL/Vulkan into it.
   - **iOS/macOS:** `CVPixelBuffer`/`IOSurface` backed Metal texture → `FlutterTexture` /
     `registerTexture`.
   - **Windows:** D3D11 shared handle / ANGLE; Flutter Windows external texture API.
   - **Linux:** EGLImage / GBM dmabuf interop with the Flutter Linux embedder.
   - **Web:** no FFI/external-texture analog — use WebGL/WebGPU into an `OffscreenCanvas`/
     `ImageBitmap` composited via platform view; **web cannot share like native** → keep F2.
3. **Flutter Dart side:** `Texture(textureId: id)` widget instead of `RawImage`/`drawImageRect`;
   a platform channel + `TextureRegistry` plugin per platform to allocate/register/update the
   texture and pass the `int textureId` to Dart.
4. **Synchronization:** GPU fences / frame pacing so Flutter never samples a half-written texture
   (double/triple buffering of GPU textures).

## Why it's hard / risks
- Six embedders, six different interop APIs; significant native (Kotlin/Swift/C++/GL) code.
- GPU context sharing between Rust's `wgpu` and Flutter's engine (Impeller/Skia) is non-trivial
  and version-sensitive.
- Web fundamentally differs (no shared external texture via FFI).
- Maintenance burden + larger binary (wgpu, shader toolchain).

## Suggested phasing if pursued
- [ ] Prototype on **one** platform (Android `SurfaceTexture` or macOS `IOSurface`) end-to-end:
      `wgpu` renders a triangle → external texture → `Texture` widget on screen.
- [ ] Add a render-backend abstraction so CPU rasterizer (default, all platforms incl. web) and
      GPU backend (opt-in, per platform) coexist behind one scene API.
- [ ] Roll out platform by platform; keep CPU path as fallback when GPU/interop unavailable.
- [ ] Benchmark vs F1/F2 to confirm the latency/throughput gain justifies the complexity.

## Cross-platform notes
- This is the ONLY path to true zero-copy, but it is **not uniformly achievable** (web is the
  outlier). Treat GPU as an enhancement with a guaranteed CPU fallback for portability.

## Verification
- Per-platform device testing; GPU capture (RenderDoc/Xcode GPU/Android GPU Inspector);
  latency measurement vs F1/F2.

## Decision record
- 2026-06-03: Documented as optional. Recommendation: ship F1/F2 first; only pursue G if a
  customer/use-case needs GPU-class 3D and is willing to fund per-platform embedder work.
