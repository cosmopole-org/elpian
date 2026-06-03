# A1 — Rust release build profile (`opt-level "z"` → `3`)

**Risk:** Low · **Verifiable here:** ✅ (Rust + wasm build) · **Effort:** 15 min · **ROI:** Very high

## Objective
Stop optimizing the compute-bound CPU rasterizer + bytecode VM for *binary size*.
Switch to speed-oriented codegen.

## Why
`rust/Cargo.toml` currently has `opt-level = "z"` (smallest size). For a tight
per-pixel rasterizer loop and an interpreter, `z` disables inlining/unrolling and
costs large throughput. `opt-level = 3` is the correct choice; keep LTO + single
codegen unit (best runtime, slower compile — acceptable).

## Files
- `rust/Cargo.toml` — `[profile.release]` block (currently ~lines 21-26).

## Steps
- [ ] In `[profile.release]`, change `opt-level = "z"` → `opt-level = 3`.
- [ ] Keep `lto = true`, `codegen-units = 1`, `strip = true`.
- [ ] Do **NOT** add `panic = "abort"` — there is no `catch_unwind` at the FFI boundary
      (confirmed), so changing panic semantics risks UB across FFI. Leave default unwind.
- [ ] Do **NOT** add `target-cpu=native` (binaries are cross-compiled for mobile/other CPUs;
      must stay portable). If you ever want micro-tuning, do it per-target in
      `.cargo/config.toml`, never globally.
- [ ] (Optional) Add a `[profile.bench]` inheriting release opts for Criterion (see `V`).

### Resulting profile (target state)
```toml
[profile.release]
lto = true
codegen-units = 1
opt-level = 3
strip = true
```

## Cross-platform notes (see `X`)
- Applies identically to all native targets and to the wasm rebuild. No API change.
- Trade-off: native `.so/.dll/.dylib` and `.wasm` grow modestly (~10-20%). Acceptable
  per the "aggressive" directive. If web bundle size becomes a concern, you may keep
  `opt-level = "s"` *only* for wasm via a cfg/profile split, but default to `3`.

## Verification
- [ ] `cargo build --release --manifest-path rust/Cargo.toml` succeeds.
- [ ] `cargo test --release --manifest-path rust/Cargo.toml` → 10/10 green.
- [ ] `cargo build --release --manifest-path rust/Cargo.toml --target wasm32-unknown-unknown`
      succeeds (add target first: `rustup target add wasm32-unknown-unknown`).
- [ ] Run Criterion bench (after `V` is set up) and record before/after in `STATUS.md`.

## Rollback
Revert the one-line change. Pure config; no behavioral risk.
