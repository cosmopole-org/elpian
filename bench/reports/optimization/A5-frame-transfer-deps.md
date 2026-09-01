# A5 — Double-buffer + parking_lot + base64 crate

**Date:** 2026-06-03

## What changed
1. **Double-buffering.** `SceneRenderer` keeps a front buffer (`pixels`, last
   completed frame — what FFI/manager read) and a back buffer (`pixels_back`, the
   render target). `render_scene` clears+rasterizes into the back buffer and then
   `mem::swap`s it to front. A pointer handed out by `get_frame_data` therefore
   stays valid for the entire next frame (the next frame renders into the *other*
   buffer). This is the prerequisite for the F1 no-Dart-copy path.
   - New test `rust/tests/double_buffer.rs` proves the front buffer a reader grabbed
     after frame N is byte-intact after frame N+1 renders (using an animated scene so
     the assertion is non-vacuous).
   - Cost: +1 framebuffer of RAM (e.g. ~+8 MB at 1080p). Acceptable per plan.
2. **parking_lot mutex** for the global scene map on native targets; `std::sync::Mutex`
   retained on wasm (single-threaded). A `lock_scenes()` helper hides the API
   difference (parking_lot returns the guard, std returns a `Result`).
3. **base64 crate** (`base64::engine::general_purpose::STANDARD`) replaces the
   hand-rolled encoder in `bevy_ffi.rs::elpian_bevy_get_frame_json`. Same standard
   alphabet + padding, so the web/snapshot JSON output is unchanged.

## Verification
- Golden framebuffer hashes byte-identical (double-buffer swap is transparent).
- Double-buffer validity test green.
- 10 VM tests green.
- Host build OK; **wasm32 build OK** — proves parking_lot + rayon are cfg-gated out
  and the std Mutex + base64 crate compile for web.
- No frame-time regression (the swap is an O(1) pointer exchange):
  sphere_hipoly ≈ 2.4 ms, fillrate_quad ≈ 1.64 ms (unchanged vs A4 within noise).
