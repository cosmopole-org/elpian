# S8 — Verification: what has to be true, and how it is checked

Tests land **with** their workstream, not after it. This file is the index of
what each one owes, plus the cross-cutting suites that belong to no single
workstream.

---

## 1. The environment

Verified from `upgrade/README.md` and the current tree:

- **Rust** is installed and crates.io is reachable: every Rust change here is
  locally verifiable with `cargo test --workspace`.
- **Flutter/Dart** availability has varied between sessions. Check first
  (`flutter --version`). If absent, Dart changes must be mechanical, reviewed by
  inspection, and covered by pure-logic unit tests that CI runs. Record which
  situation applied in `STATUS.md`.
- CI lives in `.github/workflows/`.

## 2. The cross-cutting suites

### 2.1 The policy conformance corpus

`test/fixtures/policy_corpus.json` — cases of `(manifest, grant) → expected
policy`, read by **both** `elpian-host`'s Rust tests and the Dart
`mini_app_*_test.dart` suites.

It exists because the tree already shows the drift it prevents: `ElpianCapability`
is missing `surface` (`00-current-state.md` §5). Cases must include: empty
request means "everything granted"; unknown capability names are dropped, not
rejected; limits intersect axis-by-axis with null meaning unbounded;
`mayHostChildren` requires all three of request, grant and `vm_manage`.

### 2.2 The capability parity test

Enumerate `Capability::all()` in Rust and `ElpianCapability.values` in Dart and
assert they name the same set. Plus: every name in `all_host_apis()`
(`api.rs:89`) resolves to a capability that is **not** `Other` unless it is on a
short, explicit exemption list. That second assertion is what catches a new host
API silently landing on the catch-all gate.

### 2.3 The closed-cycle test

The security claim of this whole program, so it gets a dedicated suite. For an
app in `closed` mode, with a canary TCP listener recording every connection:

- client VM `net.fetch(<canary>)` → typed null, zero connections, one audit record;
- server function `net.fetch(<canary>)` → same;
- `server.call` reaches only that app's own functions; another app's function
  name 403s;
- `vm.import` of a URL is refused;
- after the run, the canary recorded **no** connections at all.

### 2.4 The SSRF corpus

Table-driven, listed in full in `S3-proxy-and-egress.md` §6. It is the other
suite that must never be allowed to rot.

## 3. What each workstream owes

| WS | Must prove |
|---|---|
| S0 | Two guest turns overlap in wall time (fails on `main` today); terminate lands mid-flight; destroy during a turn is clean under a sanitizer; existing suites stay green |
| S1 | A server function can log / read the clock / use `kv` / use `fs` (HTTP 501 today); denied capability → typed null; `fs.*` confined; traps do not leak internals; 100 parallel invocations actually parallel |
| S2 | Payload → widget-tree golden equality; island splice and unknown-island degradation; streaming frames; cache and `revalidate(tag)`; stylesheet scoping |
| S3 | The closed-cycle suite; the SSRF corpus; rebinding; allowlist matching; caps and quotas; audit completeness |
| S4 | Warm reuse runs module init once; cold-start attribution; hibernate/wake; LRU eviction never takes a Busy instance; all three deadline layers; aggregate teardown hits one app only; meters accurate and restart-durable |
| S5 | Policy parity via the corpus; registry round-trip and blob dedupe; atomic index writes survive a kill; cross-app isolation; access control before guest CPU; admin auth and audit |
| S6 | Byte-identical rebuilds; tamper detection on blob, index, truncation and key; downgrade refusal; `package→install→serve→invoke` round-trip; `publish` and `install` produce identical records |
| S7 | Every documentation snippet compiles through `js2elpian`; the sample builds and runs from `create` with no edits |

## 4. End-to-end

One scripted path, run in CI, over `fullstack-sample`:

```
elpian create --template closed-fullstack   → builds clean
elpian run build                            → deterministic artifacts
elpian package                              → verify passes, hash recorded
elpian install --registry ./data            → record written
elpian serve --registry ./data &
GET  /apps/sample/manifest.json             → client url + function table
GET  /apps/sample/client.bc                 → hash matches the manifest
POST /apps/sample/fn/createNote             → ok, coldStart true
POST /apps/sample/fn/createNote             → ok, coldStart false      (warm reuse)
POST /apps/sample/fn/NoteList               → component payload renders
     canary listener                        → zero connections         (closed cycle)
GET  /admin/apps/sample/meters              → non-zero, plausible
```

## 5. Benchmarks to record in `STATUS.md`

Numbers, not adjectives. Measure before P0 and after each of P0/P1/P4:

| Metric | Why |
|---|---|
| Cold start (ms, p50/p99) | The serverless promise |
| Warm invoke (ms, p50/p99) | The steady state |
| Invocations/s at concurrency 1 / 8 / 64 | The direct F2 regression measure |
| RSS per idle instance (MB) | Sets the eviction budget |
| Package size, and dedupe ratio across two versions | Whether per-function modules cost too much |
| Broker overhead per request (ms) | Whether the proxy is a choke point |

## 6. Security review

Before P5 ships, run the repository's `security-review` over the diff, with
these specifically in scope: the `unsafe impl Send` justification (S0), guest
trap containment, `fs`/`kv` path confinement, the SSRF guards, identity
construction (`ctx.user` may only come from a verified credential), admin
authentication, secret handling (never packaged, never logged, never returned to
a client), and warm-instance state as a cross-user data path.
