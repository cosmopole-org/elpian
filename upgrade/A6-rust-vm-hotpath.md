# A6 — VM value-model hot path (Rc/RefCell → fast-path enum + CoW)

**Risk:** HIGH · **Verifiable here:** ✅ (full VM test suite) · **Effort:** 2–4 days · **ROI:** Med–High for script-driven UIs

> Do this **last**. It touches the interpreter core. Only proceed when A1–A5 + F are
> stable and the VM tests are a tight safety net. Land it in small, separately-tested commits.

## Objective
Reduce per-value indirection and deep cloning in the bytecode VM so script-driven
renders cost less CPU/RAM.

## Why
`rust/src/sdk/data.rs` represents every runtime value as `Rc<RefCell<Box<dyn Any>>>`
(three levels of indirection: refcount + borrow-check + dynamic downcast) and
`clone_data` (`:33-84`) deep-copies arrays/objects on assignment. For hot scripts
(animation/state loops calling `render`), this is heavy.

## Files
- `rust/src/sdk/data.rs` — `Val` representation, `clone_data`.
- `rust/src/sdk/executor.rs` (4906 lines) — the dispatch loop; many call sites read/write `Val`.
- `rust/src/sdk/vm.rs` — JSON↔Val conversion.
- `rust/src/sdk/context.rs` — variable scopes.

## Design (incremental, lowest-risk ordering)
1. **Primitive fast path:** make `Val` an enum with inline variants for `Null/Bool/Int/
   Float/Str` and an `Rc`-backed variant only for `Array`/`Object`/`Function`. This removes
   `Box<dyn Any>` + downcast for the common scalar operations.
   ```rust
   enum Val {
       Null, Bool(bool), Int(i64), Float(f64), Str(Rc<str>),
       Array(Rc<RefCell<Vec<Val>>>),
       Object(Rc<RefCell<HashMap<String, Val>>>),
       Func(Rc<FuncDef>),
   }
   ```
2. **Copy-on-write for containers:** assignment clones the `Rc` (cheap); mutate via
   `Rc::make_mut` so the deep copy happens only when actually shared+written. Replaces
   eager `clone_data` deep copies.
3. **String interning (optional):** `Rc<str>` for identifiers/keys to cut allocations.

## Steps
- [ ] Introduce the `Val` enum behind the existing API surface; migrate constructors/accessors.
- [ ] Replace `clone_data` deep-copy with `Rc` clone + `make_mut` on write.
- [ ] Sweep `executor.rs` for `downcast`/`borrow` patterns; replace with `match`.
- [ ] Update `vm.rs` JSON↔Val both directions.
- [ ] Add micro-tests for each Val type (arithmetic, array mutate-after-alias, object key set,
      function call) proving CoW semantics (mutating one alias must not affect the other).

## Cross-platform notes
- Pure logic; native + wasm identical. `Rc` (not `Arc`) is correct (VM is single-threaded).

## Verification
- [ ] **All 10 VM tests green at every commit** — they cover arithmetic, host-call round-trip,
      function input mapping, if/elseif/switch, and the counter/message/theme examples.
- [ ] Add new CoW + per-type tests.
- [ ] Host + wasm builds succeed.
- [ ] Bench a script-driven render loop (counter/animation example) for CPU reduction.

## Rollback
Largest rollback surface — keep this on its own commits so it can be reverted without
touching the renderer work. If unstable, abandon A6; A1–F deliver most of the gains.
