# STATUS — the fullstack program

Update this file as you go. It is the first thing the next session reads.

**Working branch:** `claude/refactor-architecture`
**Plan written:** 2026-09-03 (findings verified against the tree that day)
**Current phase:** **P0 complete.** P1 in progress.

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
- [ ] `server.call` serviced in Dart `HostHandler` — **not started** (needs the
      client half; belongs with S2's client work)
- [ ] CLI: per-function server modules + function table — **not started**
      (the format is settled and `elpiand` reads it; the CLI does not write it yet)
- [ ] `elpian-server` shimmed onto the host so `run dev` keeps working —
      **not started**

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
- [ ] `ServerComponent` widget (pending / ready / error / revalidating) — **not
      started**, Dart side
- [ ] Unknown-island degradation on the device — **not started**, Dart side
- [ ] Streaming over WS into `ElpianStreamWidget`; frame budgets — **not
      started**; this is the one piece the std-only runtime decision makes more
      work, and the piece most likely to reverse it

## P3 — Registry + hosting (S5)

- [ ] `RegistryStore` + content-addressed blobs + atomic index
- [ ] `policy.rs` — port of `MiniAppPolicy.resolve`; conformance corpus green in both languages
- [ ] Versions, deploy, drain, rollback, downgrade refusal
- [ ] Admin API + operator auth + audit
- [ ] `AuthProvider`; `ctx.user`; per-app/per-function access rules
- [ ] Flutter shell: app-scoped manifest, artifact hash verification, net policy
- [ ] Tests

## P4 — Serverless + meters (S4)

- [ ] Instance pool, supervisor node adoption, policy applied before first run
- [ ] Lifecycle: Cold/Loading/Warm/Busy/Hibernate/Failed + transitions
- [ ] Bounded queues, scale-up, cold-start attribution
- [ ] Three deadline layers
- [ ] `CostSample` → rolling meters, persisted
- [ ] Quota ladder: throttle → strangle → drain → suspend
- [ ] Tests + benchmarks

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
- [ ] `POST /apps/<app>/proxy` and the actual outbound HTTP client — **not
      started**; the decision function is complete and tested, nothing calls it
      to make a real request yet
- [ ] Audit records persisted — **not started** (the reasons carry their detail;
      nothing writes it down)
- [ ] `ElpianNetPolicy` in Dart; `netPolicy` on `MiniAppGrant` — **not started**
- [ ] `security-review` run over the diff — **not started**

## P6 — Packaging (S6)

- [ ] `elpian-pkg` crate: EPKG1 container, deterministic index, signing (shared with `bundle.rs`)
- [ ] `package` / `verify` / `inspect` / `publish` / `install` / `serve` / `apps`
- [ ] `elpian.app.json`; manifest derived from the tree; disagreement is an error
- [ ] `main.rs` split into modules
- [ ] Templates incl. `closed-fullstack`; `run dev` as a registry case
- [ ] Delete `elpian-server.rs`
- [ ] Determinism + tamper + round-trip tests

## P7 — SDKs and docs (S7, rolling)

- [ ] `@elpian/sdk`: `callServer`, `serverRender`, `serverComponent`, `action`
- [ ] `@elpian/server`: `ui`, `ctx`
- [ ] Wiki `18`–`22`; updates to `03`, `05`, `12`, `14`, `17`
- [ ] `fullstack-sample` upgraded; brokered-mode sample added
- [ ] Doc snippets compile through `js2elpian`
- [ ] E2E script in CI

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
