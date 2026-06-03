# Elpian Graphics Optimization Program

This folder is the **single source of truth** for the Elpian graphics/rendering
optimization effort. It is written so the work can be executed across **multiple,
independent sessions** without losing any context. Every workstream is a
self-contained file with: objective, rationale, exact file:line targets,
step-by-step implementation, code sketches, cross-platform notes, verification
steps, risks, and rollback.

> **Golden rule for every session:** the execution container is ephemeral.
> Anything not committed + pushed to the working branch is lost. Commit and push
> after each workstream. Update `STATUS.md` as you go.

---

## How to use this folder (start-of-session ritual)

1. Read `STATUS.md` — find the next unchecked task and any notes from the prior session.
2. Read `00-architecture-and-findings.md` once to reload the mental model.
3. Open the workstream file for the task (e.g. `A1-...md`), follow it end-to-end.
4. Run the verification steps in `V-verification-and-benchmarking.md` for that change.
5. Tick the box in `STATUS.md`, record measured numbers, commit + push.

## Environment constraints (verified 2026-06-03)

- **Rust:** toolchain present (`cargo 1.94.1`), crates.io reachable. You CAN add
  crates, build `--release`, run `cargo test`, and build for `wasm32-unknown-unknown`.
  → **All Rust changes are locally verifiable.**
- **Flutter/Dart:** **NOT installed** in the cloud container. You CANNOT compile or
  run Dart here. → Dart changes must be mechanical/low-risk, reviewed by inspection,
  and verified on a real machine or CI. Add pure-logic Dart unit tests where possible.
- **CI:** `.github/workflows/build_windows.yml` builds Windows release **only on push
  to `main`** (does not trigger on the working branch). Don't rely on it for branch CI.
- **Working branch:** `claude/funny-tesla-vzF9A`. Never push to `main` without explicit permission.

## The headline facts (read these first)

1. **"Bevy" is a misnomer.** There is **no Bevy / wgpu / GPU** dependency. Both 3D paths
   (`rust/src/bevy_scene/` and `lib/src/scene3d/`) are **CPU software rasterizers**
   producing RGBA8 buffers. See `00-architecture-and-findings.md`.
2. **Biggest single win:** Rust release profile is `opt-level = "z"` (optimize for *size*)
   on compute-bound code. → `A1`.
3. **No zero-copy today.** The Rust→Flutter frame path has 2 CPU copies + async latency;
   web uses base64-in-JSON. → `F` (minimal-copy) and optional `G` (true GPU zero-copy).
4. **Flutter UI rebuilds from scratch every update; CSS is re-parsed every build.** → `D`.

## Workstream index

| ID | File | Area | Verifiable here? | Risk |
|----|------|------|------------------|------|
| — | `00-architecture-and-findings.md` | Full architecture + file:line map | n/a | n/a |
| A1 | `A1-rust-build-profile.md` | Rust release profile `z`→`3` | ✅ Rust | Low |
| A2 | `A2-rust-mesh-cache.md` | Cache per-frame mesh generation | ✅ Rust | Low |
| A3 | `A3-rust-rasterizer-inner-loop.md` | Incremental barycentric rasterizer | ✅ Rust | Low |
| A4 | `A4-rust-parallel-rasterizer.md` | `rayon` tiled multithreaded raster | ✅ Rust | Med |
| A5 | `A5-rust-frame-transfer-deps.md` | Double-buffer, `parking_lot`, `base64` | ✅ Rust | Low |
| A6 | `A6-rust-vm-hotpath.md` | VM value model (Rc/RefCell, CoW) | ✅ Rust | High |
| B | `B-dart-3d-fallback.md` | Dart software 3D renderer | ⚠️ inspection | Low |
| C | `C-dart-canvas2d.md` | Canvas 2D API allocations | ⚠️ inspection | Low |
| D | `D-dart-html-css-dsl.md` | HTML/CSS/Flutter-DSL pipeline | ⚠️ inspection | Med |
| E | `E-flutter-impeller-config.md` | Impeller + shader warmup + images | ⚠️ inspection | Low |
| F | `F-zerocopy-lowlatency-frame-transfer.md` | Minimal-copy 3D→2D + web fast path | ⚠️ mixed | Med |
| G | `G-gpu-zerocopy-external-textures.md` | OPTIONAL true GPU zero-copy | ⚠️ large | High |
| X | `X-cross-platform-compatibility.md` | 6-platform compat matrix + checks | ✅ Rust/wasm | n/a |
| V | `V-verification-and-benchmarking.md` | Golden tests, Criterion, wasm build | ✅ Rust | n/a |

## Recommended execution order

`A1 → A2 → A3` (bench) → `A4 → A5` (bench) → `F1 → F2` → `B → C` → `D → E` → `A6` →
*(optional)* `G`. Always run `X` checks + `V` after each Rust change.

## Conventions

- Each file marks tasks with `- [ ]` checkboxes mirrored in `STATUS.md`.
- Code sketches are **illustrative**, not literal patches — match surrounding style.
- Keep every change behind the existing test suite (10 VM tests must stay green) plus
  the new golden/pixel tests introduced in `V`.
