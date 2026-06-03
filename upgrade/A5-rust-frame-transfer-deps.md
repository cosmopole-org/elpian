# A5 — Double-buffer, faster mutex, real base64

**Risk:** Low · **Verifiable here:** ✅ · **Effort:** 3–5 h · **ROI:** Med (enables F1/F2; cuts web cost)

## Objective
1. Add **double-buffering** so a frame the Dart side is reading stays valid while the
   next frame renders (prerequisite for zero-Dart-copy in `F1`).
2. Replace the global `std::sync::Mutex` with `parking_lot::Mutex` on native.
3. Replace the hand-rolled base64 (`bevy_ffi.rs`) with the `base64` crate.

## Files
- `rust/Cargo.toml` — add `base64`; add `parking_lot` (cfg-gated for safety).
- `rust/src/bevy_scene/renderer.rs` — `pixels` buffer handling.
- `rust/src/bevy_scene/manager.rs` — `Mutex`, `get_frame_data`, `get_frame_copy`/`snapshot`.
- `rust/src/api/bevy_ffi.rs` — base64 encode (`:127-150`, helper `:228-256`).

## Dependencies
```toml
base64 = "0.22"

[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
parking_lot = "0.12"
```
> Keep `std::sync::Mutex` on wasm (single-threaded; `parking_lot` thread features are
> unnecessary there). Use a cfg type alias so call sites are unchanged:
```rust
#[cfg(not(target_arch = "wasm32"))] use parking_lot::Mutex;
#[cfg(target_arch = "wasm32")] use std::sync::Mutex;
```
> Note: `parking_lot::Mutex::lock()` returns the guard directly (no `Result`), so adjust
> `.lock().unwrap()` → `.lock()` behind the native cfg, or wrap with a tiny helper to keep
> both arms uniform.

## Double-buffer design
- In `SceneRenderer`, hold two buffers: `pixels_front` (last completed frame, what Dart
  reads) and `pixels_back` (being rendered). After `render_scene` finishes, swap
  (`std::mem::swap`). `get_frame_data` returns a pointer into `pixels_front`, which is
  **not** mutated by the next render (it renders into `pixels_back`). This makes the
  native pointer safe to read for the whole frame → unlocks `F1`'s no-copy path.
- `depth` buffer stays single (only used during render).
- Keep `width*height*4` sizing; resize both buffers in `resize()`.

## Steps
- [ ] Add `base64` + `parking_lot` (cfg-gated) to `Cargo.toml`.
- [ ] Introduce the `Mutex` cfg alias; fix `.lock()` call sites.
- [ ] Add front/back buffers to `SceneRenderer`; render into back, swap to front at end of
      `render_scene`; `pixels()` accessor returns front.
- [ ] Update `manager.rs` `get_frame_data`/`get_frame_copy`/`get_frame_snapshot` to read front.
- [ ] Replace manual base64 in `bevy_ffi.rs` with `base64::engine::general_purpose::STANDARD`.
- [ ] (Optional) add a reusable scratch `Vec<u8>` for the web `get_frame_copy` to avoid
      per-call `clone` allocation churn (reuse capacity).

## Cross-platform notes (see `X`)
- `parking_lot` native-only via cfg; wasm uses std `Mutex`. `base64` crate is wasm-safe.
- Double-buffer doubles the pixel RAM for the 3D target (e.g. 1080p ≈ +8 MB). Acceptable;
  document it. If memory-constrained on mobile, gate double-buffer behind a flag.

## Verification
- [ ] Golden pixel test unaffected (output identical).
- [ ] Host + wasm builds succeed (proves cfg aliasing).
- [ ] 10 VM tests green.
- [ ] Confirm `get_frame_data` pointer stays valid across a subsequent `render_frame`
      (add a Rust test: render A, grab ptr, render B, assert front bytes unchanged until swap consumed).

## Rollback
Single-buffer restore; revert deps. Mechanical.
