# A3 — Incremental barycentric rasterizer inner loop

**Risk:** Low–Med · **Verifiable here:** ✅ · **Effort:** 2–3 h · **ROI:** High (per-pixel cost)

## Objective
Remove the 3 `edge_function` calls per pixel in `fill_triangle`, replacing them with
incremental edge stepping, plus a fast opaque write path. Output must stay
pixel-identical.

## Why
`rust/src/bevy_scene/renderer.rs:546-620` computes three edge functions for **every
pixel** in the bounding box (`:573-575`). Edge functions are affine in (x, y), so
`E(x+1, y) = E(x, y) + dEdx` and `E(x, y+1) = E(x, y) + dEdy`. Precompute the row
start and step horizontally — turning 3 multiplies+adds per pixel into 3 adds.

## Background math
For edge from `a` to `b` evaluated at point `p`:
`E(p) = (b.x-a.x)*(p.y-a.y) - (b.y-a.y)*(p.x-a.x)`
So `dE/dx = -(b.y-a.y)`, `dE/dy = (b.x-a.x)`. For the three edges (v1→v2, v2→v0,
v0→v1) precompute `A_i = -(dy_i)`, `B_i = dx_i`, and the value at the bbox top-left
pixel center; step by `A_i` across x and by `B_i` down y.

## Files
- `rust/src/bevy_scene/renderer.rs` — `fill_triangle` (`:546-620`), `edge_function` helper.

## Steps
- [ ] Compute `area` and `inv_area` once (already done at `:563-567`).
- [ ] For each of the 3 edges compute `A_i`, `B_i`, and `w_i_row` = edge value at the
      first pixel center `(min_x+0.5, min_y+0.5)`.
- [ ] Outer `for y`: copy `w_i = w_i_row`; inner `for x`: test `w0|w1|w2 >= 0`
      (use the same sign convention as today — verify against current `inv_area` sign
      so winding/back-face behavior is unchanged), then `w_i += A_i`. After inner loop
      `w_i_row += B_i`.
- [ ] Interpolated depth `z` uses normalized weights `w_i * inv_area` (same as now).
- [ ] Keep the existing depth test + RGBA write. Add a **fast path**: if `alpha >= 1.0`
      write 4 bytes directly (already present `:594-598`); keep the blend path `:599-615`
      for translucent.
- [ ] Optional: hoist `clamp(0,1)*255` color conversion out of the pixel loop (color is
      constant per triangle under flat shading) — compute `r,g,b,a: u8` once before the loops.
      **This is a real win** since lighting is per-triangle (`:460-462`).

## Pitfalls (to keep output identical)
- Match the **exact inclusion rule** (`>= 0.0`) and sign handling of the current code,
  including the degenerate-area early return (`:564`).
- Pixel center offset must remain `+0.5` (`:571`).
- Watch integer/float rounding in bbox clamp (`:558-561`) — keep identical casts.

## Cross-platform notes
- Pure arithmetic; identical on all native + wasm. No deps.

## Verification
- [ ] **Golden pixel-checksum test is mandatory here** (see `V`). Compare CRC/hash of the
      full framebuffer for several scenes against the pre-A3 baseline; must match exactly.
      If a handful of edge pixels differ due to FP reassociation, document it and decide
      (ideally keep exact; reorder ops to match if needed).
- [ ] 10 VM tests green; host + wasm builds succeed.
- [ ] Bench fill-rate-heavy scene (large triangles); expect notable per-pixel speedup.

## Rollback
Revert `fill_triangle` to the edge-function-per-pixel version.
