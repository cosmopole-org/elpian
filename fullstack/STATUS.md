# STATUS — the fullstack program

Update this file as you go. It is the first thing the next session reads.

**Working branch:** `claude/refactor-architecture`
**Plan written:** 2026-09-03 (findings verified against the tree that day)
**Current phase:** All eight workstreams have landed their core. What remains
is listed per phase below and summarised in "What is still missing" at the end.

**Environment as found:** Rust toolchain present, crates.io reachable, full
workspace builds and tests. Flutter 3.47.2 / Dart 3.13.2 present — Dart changes
*are* verifiable here. The native library must be built first
(`cd rust && cargo build --release -p elpian-ffi`) and the test run needs
`LD_LIBRARY_PATH=$PWD/rust/target/release`, or 21 FFI-backed tests silently skip.

**Baselines:** cargo `--workspace` 130 → 285 passed, 0 failed.
`flutter test` 278 passed (with the native library loaded).

---

## Session ritual

1. Read this file: find the next unchecked item and any notes below.
2. Read `00-current-state.md` once to reload the mental model.
3. Open the workstream file, follow it end to end.
4. Run that workstream's verification section (`S8-verification.md` §3 indexes
   what each one owes).
5. Tick the box, record measured numbers, commit.

---

## P0 — Foundation (S0) — **done**

- [x] S0.1 audit: no `Rc` is shared between two VMs — **gate passed**. Everything
      crossing a VM boundary is owned and `Send`: host-call envelopes and results
      are `String`, and `vm.send` / `vm.import` carry `serde_json::Value`
      (`elpian-runtime`'s `Command::{Message,Notify}`), re-materialised into fresh
      `Rc`s inside the *target* by `convert_json_value_to_val`. Written into the
      `unsafe impl Send` comment in `sdk/vm.rs`.
- [x] S0.1 removed `unsafe impl Sync for VM`. It was never needed (a static
      `Mutex<HashMap<_, VM>>` asks only for `Send`) and was false besides.
- [x] S0.2 registry sharded into 16 maps of `Arc<Mutex<VM>>`; lock discipline
      documented on `Registry` and enforced by `Registry::get`.
- [x] S0.3 ownership model — landed as the sharded handles plus the out-of-band
      control channel below, which is what the actor model was for.
- [x] S0.4 `api::supervisor`: `sweep()` and `Supervisor::start`.
- [x] S0.5 `ElpianCapability.surface` added; `MiniAppGrant.untrusted` includes it;
      Rust-side parity test reads the Dart enum.
- [x] Tests: `parallel_execution.rs`, `rng_isolation.rs`, `supervisor.rs` — all
      fail against the previous design, pass now.
- [ ] Benchmark baseline recorded (S8 §5) — **deferred to P1**, where there is a
      server to measure invocations against.

### Found during P0, not in the original plan

* **`ExecControl` was a lie in the docs.** Its module comment said the flag was
  shared `Rc<RefCell<…>>` between the VM handle and the executor; it was a
  `Copy` field *inside* the executor. So `terminate` needed the executor borrow
  the running turn was holding, and a request could only land between turns —
  exactly when it is not needed. Now an `Arc<AtomicU8>`; `pause`/`terminate`/
  `run_state` take no VM lock at any layer. **Everything in S4's deadline story
  depends on this**, and the plan had assumed it already worked.
* **The `random` builtin's state was a bare thread-local.** Correct only while
  one global lock made all execution serial and single-threaded. Pooled
  instances would have shared a stream with whatever else ran on their thread
  and jumped streams on migration. Moved into the executor, swapped onto the
  thread for the duration of a turn.

## P1 — Server runtime + RPC (S1, S3 posture) — **mostly done**

- [x] `elpian-host` crate; **dependency decision: std only, reversed from the plan**
      (see Decisions below)
- [x] Host-call servicing loop — the HTTP 501 is gone
- [x] Server capability posture, written positively from deny-all
- [x] `ServerCall` + `State` through all four sites; the S0.5 parity test caught
      the Dart half being missing, which is what it is for
- [x] `kv.*`, `secret.get`, app-rooted `fs.*` with `charge_storage`
- [x] `AppDefinition` + `AppRuntime`; `server.call` between functions of one app
- [x] HTTP gateway: manifest, client bytecode, action and component routes
- [x] `elpiand` binary loading an on-disk registry
- [x] Tests: 33 in `elpian-host` + benchmark baseline
- [x] `server.call` / `server.render` serviced from Dart, via
      `ElpianServerClient.hostHandlers` on `ElpianVm.registerHostHandlers`
- [x] Per-function server modules + function table — `elpian-pkg` writes them,
      `elpiand` reads them, the E2E script drives both
- [ ] `elpian-server` shimmed onto the host so `run dev` keeps working —
      **not started**; the old dev server still exists untouched
- [ ] The `elpian` CLI itself does not yet call `elpian-pkg`; packaging is its
      own binary

### Benchmark baseline (2-core box, debug build, cold instance per call)

| Metric | Value |
|---|---|
| Invoke latency | p50 0.64ms, p99 1.02ms |
| Throughput @ concurrency 1 | 1373 req/s |
| Throughput @ concurrency 8 | 2861 req/s |
| Throughput @ concurrency 64 | 2812 req/s |

2.08× from concurrency 1 → 8 on two cores is the parallelism S0 unlocked,
measured. Re-run after S4 to see what the warm pool adds; cold-start cost is
currently *every* call.

### Found during P1

* **`continue_execution` discarded the resumed turn's value**, returning a fixed
  `"done"`. That lost the return value of every guest function that made a host
  call before returning — including on the *client*, where
  `ElpianVm.executeFunction` reads `resultValue` after exactly this loop. UI
  handlers rarely return anything, which is why it went unnoticed.
* **My own S0 change broke idle terminate.** Routing `VM::request_terminate`
  past the executor lost the immediate confirm-and-clear for an idle instance.
  Split into `confirm_terminate_if_idle`, reached through
  `try_borrow_mut`/`try_lock` — which is the right idleness test anyway, since a
  turn in flight is what holds them.
* **The first queue depth (`workers * 4`) shed load under ordinary traffic.** On
  a two-core box that is eight slots, and a 64-request burst got 503s. A page
  opening does not arrive one request at a time. Now 64 per worker, configurable.
* **Shedding was abrupt enough to lose its own response.** Writing 503 and
  dropping the socket while the client was still sending reset the connection,
  so the client saw a broken pipe instead of the refusal and could not tell
  "retry" from "the host is broken". Now: write, half-close, drain.

## P2 — Server components (S2) — **host half done**

- [x] Payload shape reused from the Next.js bridge, minus `jsCode` (refused, not
      ignored)
- [x] `server.render` route; render cache; `cache.revalidate` host API
- [x] Islands listed by name from `clientComponents`
- [x] Tests (13)
- [x] `ServerComponent` widget — pending / ready / error, a generation guard so
      a slow earlier response cannot overwrite a newer one, and a failed
      revalidation that keeps working content on screen
- [x] `ElpianServerClient` + `ElpianNetPolicy` (advisory, whole-label matching)
- [x] Island resolution on the device, via the engine's widget registry
- [x] Streaming server components — **NDJSON, not WebSocket**. The traffic is
      one-way, so a socket upgrade would buy bidirectionality nothing uses at
      the cost of masking, ping/pong and a close handshake. This is the piece
      that was expected to reverse the std-only runtime decision; it did not,
      because the requirement turned out not to need a WebSocket at all.
- [ ] Frame budgets — a component can emit without bound. The dead-reader
      signal lets a well-behaved one stop; a host-side cap does not exist.

## P3 — Registry + hosting (S5) — **done, with gaps**

- [x] `RegistryStore` + content-addressed blobs + atomic index
- [x] `policy.rs` — port of `MiniAppPolicy.resolve`; 16-case corpus green in
      **both** languages from one file
- [x] Versions, install/deploy split, rollback, downgrade refusal (numeric
      comparison — `1.10.0` > `1.9.0`)
- [x] Admin API + operator auth (closed by default) + audit (records refusals)
- [x] `AuthProvider`; `ctx.user`; nested calls carry the caller
- [x] `elpiand` reads the content-addressed store when there is one, falling
      back to the plain directory layout. Versions, staged deploys, rollback and
      blob verification are reachable at runtime, and covered by the E2E script
- [ ] Per-app/per-function access rules beyond `ctx.user` — an app decides for
      itself; the host does not yet express "only role X may call function Y"
- [ ] Flutter shell: artifact hash verification against the manifest

## P4 — Serverless + meters (S4) — **core done, brought forward**

Brought forward because "load on demand, unload when not needed" is requirement
3 in the user's own words, and every call was cold until this landed.

- [x] Instance pool with warm reuse; policy applied on creation **and on reuse**
      (a grant can change between calls; a warm instance carrying the old one
      would be a way to keep a revoked capability)
- [x] Cold-start attribution (`coldStart` on every response)
- [x] Idle TTL eviction, per-function share cap, host-wide cap, `drain_app`
- [x] Trapped instances discarded rather than reused
- [x] `stateless` opt-out per function, with the reasoning written down
- [x] Cost meters: invocations, cold starts, instructions, compute ms, peak
      memory, storage — **finding F5 said this did not exist anywhere**
- [x] Tests (7) + benchmark
- [x] Quota ladder: throttle → strangle → drain → suspend, applied **before**
      an invocation runs; `strangle` refuses writes while still serving reads
- [x] Supervisor node adoption — every instance is adopted under `app::<id>`,
      so `subtree_usage` gives an app's true total across functions,
      `destroy_vm_tree` unloads it in one call, and permission intersection
      means a function can never hold more than its app holds
- [x] Hibernate/wake — an idle instance is parked with `pause_vm` (continuation
      preserved, no CPU) before the longer TTL unloads it; waking skips module
      initialisation exactly as a warm instance does
- [x] Three deadline layers — instruction budget (computation), the supervisor's
      per-turn deadline (one stretch of execution), and now a per-*invocation*
      deadline. The middle one alone is not enough: a guest making host calls
      starts a new turn each time, so a loop of quick calls resets it forever
- [ ] Meter persistence across restart — **not started**; counters are in memory

### Benchmark, cold-per-call vs warm pool (2-core, debug)

| Metric | Cold per call | Warm pool |
|---|---|---|
| Invoke latency p50 | 0.64ms | **0.52ms** |
| Invoke latency p99 | 1.02ms | **0.84ms** |
| Throughput @ 1 | 1373 req/s | **1509 req/s** |
| Throughput @ 8 | 2861 req/s | **3105 req/s** |
| Throughput @ 64 | 2812 req/s | **2926 req/s** |

An 18% latency improvement is *modest on purpose to report honestly*: the
benchmark's module is three lines, so its initialisation is nearly free and
there is little for warm reuse to save. The saving scales with what a module
does at load time — a real one building a lookup table or parsing a template
pays that on every cold call and none of the warm ones. The number to watch
after a realistic sample lands is this one.

## P5 — The proxy (S3) — **decision core done, brought forward**

Brought forward out of order because the closed-cycle property is requirement 2
and it was cheap to finish once S1 existed.

- [x] `EgressDecision` / `DenyReason`; the ordered checks
- [x] Resolve-then-connect: `Allow` carries the resolved `SocketAddr`, not the
      hostname, so a caller cannot re-resolve and connect somewhere else
- [x] Every resolved address checked, not just the first
- [x] `ElpianNetPolicy` equivalent enforced server-side; closed apps do not hold
      the gate at all
- [x] Closed-cycle suite **with a canary listener** + SSRF corpus green
- [x] Deny reasons are indistinguishable to the guest, detailed to the operator
- [x] `POST /apps/<app>/proxy` and the outbound HTTP client, with redirect
      re-decision and separate head/body caps
- [x] `ElpianNetPolicy` in Dart, matching the server's whole-label rule
- [x] Audit records for every attempt, allowed and denied
- [ ] Audit records **persisted** — they go to the operator's log; nothing
      writes them durably
- [ ] TLS — `https` is refused with a message saying so, never downgraded. A
      TLS crate is a dependency decision for the maintainer
- [ ] `netPolicy` on `MiniAppGrant` — the policy type exists; it is not yet part
      of the grant model
- [ ] Per-app egress **byte** budgets — bytes are recorded per request, not
      totalled or capped
- [ ] `security-review` run over the diff — **not started**

## P6 — Packaging (S6) — **done, with gaps**

- [x] `elpian-pkg` crate: EPKG1 container, deterministic index, HMAC signing
      shared with `bundle.rs` via the new `elpian-crypto`
- [x] `package` / `verify` / `inspect` / `install`
- [x] `elpian.app.json`; manifest and tree must agree — an undeclared module is
      an error, and so is a declared function with no module
- [x] Determinism + tamper + truncation + round-trip tests, and the E2E script
- [x] `samples/closed-fullstack` — the reference sample
- [ ] `publish` (to a remote registry) — **not started**
- [ ] ed25519 — HMAC only; a shared secret cannot support third-party publishers
- [ ] `cli/rust/main.rs` split into modules — **not started**
- [ ] `elpian create --template closed-fullstack` — the sample exists, the
      template does not
- [ ] Delete `elpian-server.rs` — **not done**; still present and unused by the
      new path

## P7 — SDKs and docs (S7) — **done, with gaps**

- [x] `guest-sdk/js/server.js`: `callServer`, `action`, `serverRender`,
      `serverComponent`, `registerIsland`
- [x] `guest-sdk/js/elpian-server.js`: `ui`, `kv*`, `revalidate`, `secret`,
      `ctxUser`, `ctxHasRole` — compiles *and runs* against the real host
- [x] Wiki `18`–`22`; updates to `03` (the stale "no metering" claim), `12`, `14`
- [x] `samples/closed-fullstack`
- [x] `scripts/check-doc-snippets.py` compiles the server-side snippets
- [x] `scripts/e2e-fullstack.sh`
- [ ] Updates to `05-cli.md` and `17-nextjs-integration.md` — **not done**
- [ ] A brokered-mode sample — **not done**
- [ ] Client-side doc snippets are skipped by the checker (they need the GUI
      SDK, which is not standalone-compilable); the script says so rather than
      pretending
- [ ] Neither script is wired into CI — `.github/workflows/` untouched

---

## Decisions taken (record changes here, with the reason)

| Decision | Chosen | Why |
|---|---|---|
| Server VM ownership | Owned handles + per-instance actors; sharded registry for embeddings | `Rc<RefCell<Executor>>` is not safely shareable; owning it outright makes `Send` true and `Sync` unnecessary |
| Async runtime | **std only — reversed from the plan's tokio + hyper** | Built out, the case was weaker than it looked. Every request maps onto a blocking, single-threaded VM turn, so there is nothing for async to interleave; the sharded registry is what gives parallelism, and a bounded worker pool collects it. The repo's whole dependency set is serde/serde_json/once_cell, and tokio+hyper is 24 packages. What async would genuinely have bought is WebSocket streaming for S2 and cheap idle connections — both reachable from here, so this is reversible if S2 proves it wrong. **Flagged for the maintainer.** |
| Server function granularity | One bytecode module per function | Independent load/unload is the whole serverless requirement |
| Function declaration | Directory convention (`actions/`, `components/`) | Statically analysable by the CLI; the subset has no decorators |
| Component rendering | Return a payload; `render`/`patch` only when streaming | Pure, cacheable, testable without a host |
| Islands | Referenced by name from the client bundle | The bundle is already fetched and verified; inline source is a second compile path and a wider trust surface |
| Component payload shape | The Next.js bridge's shape, minus `jsCode` | One parser, existing tests, no third format |
| Package container | Custom `EPKG1` framing | Determinism; no tar/zip dependency or decompression surface |
| Signing | HMAC-SHA256 now, ed25519 before third-party publishing | Reuses `bundle.rs`; a shared secret cannot support publishers the operator does not control |
| Snapshot/fork for cold start | Deferred | Needs executor-state serialisation that does not exist; Hibernate captures most of the win |

## Open questions for the maintainer

1. **tokio/hyper**, or hold the line on a hand-rolled server? Everything else
   works either way, but S2's streaming leans on a real WS implementation.
2. **Warm-instance state**: default to reuse (Lambda-like, fast) or to
   `stateless` (safer for anything touching `ctx.user`)? The plan assumes reuse
   with an opt-in; the opposite default is defensible.
3. **Third-party publishing** — is it in scope? If yes, ed25519 moves from S6's
   "plan for" to S6's "build".
4. **Cross-app communication** — deliberately impossible in this design. If two
   mini apps must talk, that needs its own design.

## Notes for the next session

- Nothing is implemented yet. The plan is `fullstack/`; the tree is unchanged.
- `00-current-state.md` cites exact `file:line` anchors; they were correct on
  2026-09-03 and are worth re-checking if the tree has moved.


---

## What is still missing

Ordered by how likely it is to matter.

1. **Streaming server components.** Nothing emits frames. This is also the
   decision most likely to reverse the std-only runtime choice.
3. **Island splicing on the device.** Payload islands are surfaced and walked;
   `IslandBuilder`s are not yet substituted into the rendered tree.
3. **No TLS.** `https` from a server function is refused, not downgraded. Needs
   a maintainer decision on a crate.
2. **Meters and audit do not survive a restart.**
3. **`elpian-server.rs` still exists**, unused by the new path, and the `elpian`
   CLI does not call `elpian-pkg`.
4. **Frame budgets for streaming** — a component can emit without bound. The
   dead-reader signal lets a well-behaved one stop; a host-side cap does not
   exist.
5. **Nothing drives `hibernate_idle` or `evict_idle` on a timer.** Both are
   implemented and tested; `elpiand` does not yet run a sweep.
6. **ed25519**, gated on whether third-party publishing is in scope.

## Verification as of the last commit

| | |
|---|---|
| `cargo test --workspace` | 602 passed, 0 failed |
| `flutter test` | 317 passed |
| `flutter analyze lib/` | clean |
| `scripts/e2e-fullstack.sh` | all checks pass |
| `scripts/check-doc-snippets.py` | 2 compiled, 1 skipped, 0 failed |

### The `multi_vm` flake — mechanism identified, not proven

`elpian-godot-capi::multi_vm::aggregate_budget_overrun_kills_the_whole_branch`
has failed roughly 3 times in 40+ runs of its full test binary, and **never** in
~30 runs on its own. That asymmetry is the clue, and it points at something my
work plausibly caused:

* `api::enforce_tree_budgets()` sweeps **every root in the process**, not one
  manager's, and every `VmManager` calls it (`manager.rs:1096`).
* Cargo runs that binary's 14 tests concurrently **in one process**, each with
  its own `VmManager`.
* Before S0, the global registry lock serialised all guest execution, so two
  managers' sweeps could not interleave with each other's turns. After S0 they
  genuinely can — so manager A's sweep can now evaluate, and destroy, manager
  B's subtree, and attribute the destruction to itself.

That is a real design issue (a process-global sweep in a multi-manager process),
and S0 is what made it *reachable*. I could not reproduce it under targeted
load, so the causal chain above is a **hypothesis supported by reading the code**
rather than a demonstrated failure path.

Worth noting it does not obviously affect production: there is one manager per
process there. The fix, if wanted, is to scope the sweep to a manager's own
roots rather than the whole forest.
