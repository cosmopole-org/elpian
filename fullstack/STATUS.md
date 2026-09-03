# STATUS — the fullstack program

Update this file as you go. It is the first thing the next session reads.

**Working branch:** `claude/refactor-architecture`
**Plan written:** 2026-09-03 (findings verified against the tree that day)
**Current phase:** P0 not started — the plan is written, no code has changed.

---

## Session ritual

1. Read this file: find the next unchecked item and any notes below.
2. Read `00-current-state.md` once to reload the mental model.
3. Open the workstream file, follow it end to end.
4. Run that workstream's verification section (`S8-verification.md` §3 indexes
   what each one owes).
5. Tick the box, record measured numbers, commit.

---

## P0 — Foundation (S0)

- [ ] S0.1 audit: prove no `Rc` is shared between two VMs (`vm.import`, `vm.send`) — **hard gate**
- [ ] S0.1 remove `unsafe impl Sync for VM`; document the `Send` justification
- [ ] S0.2 shard the registry to `Arc<Mutex<VM>>`; fix lock ordering in the tree functions
- [ ] S0.3 instance-actor ownership model (specified here, built in S1)
- [ ] S0.4 supervisor sweep thread (`enforce_tree_budgets`, deadlines, eviction)
- [ ] S0.5 add `surface` to `ElpianCapability` (Dart)
- [ ] Tests: parallel-turn, isolation-under-contention, terminate-mid-flight, destroy-during-turn under a sanitizer
- [ ] Benchmark baseline recorded (S8 §5)

## P1 — Server runtime + RPC (S1, S3 posture)

- [ ] `elpian-host` crate skeleton; dependency decision recorded (tokio/hyper vs `tiny_http`)
- [ ] Host-call servicing loop (kills the HTTP 501 at `elpian-server.rs:212`)
- [ ] Server capability posture: deny `network`, `module_import`, `vm_manage`, `dom`, `canvas`, `surface`, `gpu`, `tasks`, `timers`
- [ ] New capabilities `ServerCall` + `State` — all four sites (enum + `all()` array size, `all_host_apis()`, regenerate catalog, Dart mirror)
- [ ] `kv.*`, `secret.get`, scoped `fs.*` with `charge_storage`
- [ ] `server.call` serviced in Dart `HostHandler`
- [ ] CLI: per-function server modules + function table
- [ ] `elpian-server` shimmed onto the host so `run dev` keeps working
- [ ] Tests + parallel-invocation benchmark

## P2 — Server components (S2)

- [ ] Payload parser shared with the Next.js bridge
- [ ] `server.render`; host render cache; `revalidate(tag)`
- [ ] `ServerComponent` widget (pending / ready / error / revalidating)
- [ ] Islands: client-bundle resolution by name, unknown-island degradation
- [ ] Streaming over WS into `ElpianStreamWidget`; frame budgets
- [ ] Tests

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

## P5 — The proxy (S3)

- [ ] `EgressDecision` / `DenyReason`; the nine ordered checks
- [ ] Resolve-then-connect (rebinding closed); redirect re-checking
- [ ] `POST /apps/<app>/proxy`; server-side `net.*` through the broker
- [ ] `ElpianNetPolicy` in Dart; `netPolicy` on `MiniAppGrant`
- [ ] Audit records for every allow and deny
- [ ] Closed-cycle suite + SSRF corpus green
- [ ] `security-review` run over the diff

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
| Async runtime | tokio + hyper (pending confirmation) | WS, deadlines, backpressure and graceful shutdown are needed by S2–S5; async front / blocking VM behind keeps guests single-threaded |
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
