# S1 — The server runtime: `elpian-host`

**Objective.** Replace the 322-line `elpian-server` binary with a real host: an
async HTTP/WS gateway in front of a synchronous VM worker pool, servicing host
calls so a server function can actually *do* something, and exposing the first
client→server RPC.

**Delivers (P1).** A server function that can log, keep state across
invocations, read the clock, read and write its own scoped storage — and a
client VM that can call it.

---

## 1. The crate

```
rust/crates/elpian-host/
├── Cargo.toml
└── src/
    ├── lib.rs          # ElpianHost: the embeddable server
    ├── bin/elpiand.rs  # the daemon
    ├── gateway/        # HTTP/1.1 + WS, routing, auth extraction
    │   ├── mod.rs  http.rs  ws.rs  routes.rs
    ├── pool/           # instance actors, workers, scheduling      (S4)
    ├── surface/        # ServerHostSurface — services askHost
    │   ├── mod.rs  log.rs  time.rs  random.rs  fs.rs  kv.rs
    │   ├── net.rs      # → the broker                              (S3)
    │   ├── server.rs   # server.invoke / server.render             (S2)
    │   └── secret.rs
    ├── registry/       # apps, versions, manifests, grants, blobs  (S5)
    ├── meter/          # cost meters, quotas                       (S4)
    ├── broker/         # egress policy, SSRF, audit                (S3)
    └── policy.rs       # manifest ∩ grant → policy (port of mini_app.dart:235)
```

`elpian-server` stays as a thin shim that maps its old flags onto the new host
with a single implicit mini app, so `elpian run dev` keeps working through the
transition. Delete it at the end of S6.

### The dependency decision

**Recommendation: `tokio` + `hyper` + `tokio-tungstenite`.** The current
hand-rolled `TcpListener` loop cannot carry what S2–S5 need: WebSockets for
streaming components, long-lived connections, per-request deadlines, graceful
shutdown, and backpressure. Writing all of that by hand is the larger cost.

The architecture that makes this safe is **async front, blocking VM behind**:

```
 tokio (I/O, WS, timers)  ──channel──▶  worker threads (own VM instances)
        ▲                                        │
        └────────────── channel ─────────────────┘
```

No `VM` ever touches an async task, so `Send`/`!Sync` (S0) is respected and no
future ever holds a guest across an await. Guest code stays exactly as
single-threaded as it is today.

If the dependency is refused, the fallback is `tiny_http` plus a hand-rolled WS
upgrade — note the decision in `STATUS.md` either way, because S2's streaming
design leans on the WS path.

## 2. Servicing host calls — the core of P1

Today any `askHost` from a server function is HTTP 501
(`elpian-server.rs:212`). The host-call loop is the fix:

```rust
loop {
    let step = vm.run_func_with_input(func, Some(input), 0);   // or continue_run
    if !step.has_host_call { break step.result }
    let call: HostCall = serde_json::from_str(&step.host_call_data)?;   // {machineId, apiName, payload}
    let reply = surface.service(&ctx, &call.api_name, &call.payload)?;  // may park on I/O
    vm.continue_run(reply);                                            // typed JSON value
}
```

`ctx` carries app id, function id, policy, instance id, meters, deadline and the
end-user identity. It is host-constructed and never guest-supplied.

### The server capability posture

Capabilities are resolved from the API name by family
(`Capability::for_api`), so the posture is a small table, not a list of names.

| Capability | Server default | Note |
|---|---|---|
| `logging` | **grant** | routed to the host log, tagged by app + function |
| `clock`, `randomness` | **grant** | `time.*`, `random.*` |
| `storage` | grant, **scoped** | `fs.*` rooted at the app's own directory, charged through `charge_storage` |
| `host_messaging` | grant | `host.send` / `host.request` = the invocation reply channel |
| `render` | grant | server components emit UI (S2) |
| `other` | grant | `stringify` and unclassified names |
| `network` | **deny** | granted only by an explicit grant, always through the broker (S3) |
| `module_import` | **deny** | a server function's code comes from the registry, not from a URL |
| `vm_manage` | **deny** | the host owns the tree; a function does not spawn siblings |
| `dom`, `canvas`, `surface`, `gpu` | **deny** | there is no display on the server |
| `timers` | deny by default | granted per function; a timer that outlives an invocation is a leak (S4 §5) |
| `tasks` | **deny** | spends host threads; not in P1 |

Two new capabilities are needed. Adding one touches four places, so treat this
as a checklist item:

| Capability | Gates | Held by |
|---|---|---|
| `ServerCall` (`server_call`) | `server.*` — the client→server RPC | the **client** VM |
| `State` (`state`) | `kv.*` — the host key/value store | **server** functions |

1. `sdk/capabilities.rs`: enum variant, `for_api` arm, `as_str`, `from_str`,
   and **`all()` — its return type is a fixed-size `[Capability; 17]`** that has
   to grow.
2. `api.rs:89` `all_host_apis()`: the new names, so they appear in the
   generated catalog.
3. `cargo run --bin gen-host-api-catalog` to regenerate
   `lib/src/vm/host_api_catalog.dart`.
4. `lib/src/vm/governance/models.dart:215`: the mirrored Dart enum members
   (together with the `surface` fix from S0.5).

### New host APIs in P1

| API | Side | Capability | Behaviour |
|---|---|---|---|
| `server.call(fn, args)` | client | `server_call` | Invoke a server **action**; returns its JSON result |
| `server.invoke(fn, args)` | server | `server_call` | Same, function→function inside one app, host-mediated |
| `kv.get/set/delete/list(key…)` | server | `state` | Per-app namespaced store; bytes charged to the app's storage budget |
| `secret.get(name)` | server | `state` | Host-held secret by name; never leaves the server, never in a package |

`server.call` is the first host API that is *outbound network from the client's
point of view* but is not `net.*`. That is deliberate: it is the only
transport a closed-cycle mini app has (S3), so it must be gated separately from
general egress.

## 3. Routing

| Route | Method | Purpose |
|---|---|---|
| `/apps/<app>/` | GET | The Flutter shell (static) |
| `/apps/<app>/manifest.json` | GET | Public manifest: client artifact URL, function table, declared caps |
| `/apps/<app>/client.bc` | GET | The client bytecode. Content-addressed, immutable, long-cache |
| `/apps/<app>/fn/<name>` | POST | Invoke an action or a server component |
| `/apps/<app>/stream/<name>` | WS | Streaming server component (S2) |
| `/apps/<app>/proxy` | POST | Brokered egress (S3) |
| `/__elpian/*` | GET | Legacy dev routes, kept until S6 |
| `/admin/*` | — | The control plane (S5) |

Every `/apps/<app>/…` request resolves the app in the registry, loads its
policy, and constructs `ctx` before any guest code runs. An unknown, disabled
or suspended app 404s/403s before an instance is touched.

## 4. The invocation contract

Request:

```json
POST /apps/notes/fn/createNote
{ "args": { "title": "…", "body": "…" }, "requestId": "01J…" }
```

Response:

```json
{ "ok": true,  "result": { … }, "meta": { "ms": 4, "coldStart": false, "instructions": 18422 } }
{ "ok": false, "error": { "code": "guest_trap", "message": "…", "detail": "instructions" } }
```

Error codes, all fixed and documented: `not_found`, `forbidden`,
`bad_request`, `guest_trap`, `limit_exceeded`, `timeout`, `unavailable`,
`quota_exceeded`, `internal`. A guest trap never leaks interpreter internals to
the caller — that lesson is already learned in `elpian-server.rs:225-240` and
must be carried over: log the detail, return the code.

## 5. The CLI change P1 needs: one module per function

Today `build_project` (`cli/rust/main.rs:271`) emits one `server.elpian.bc` for
the whole server. The serverless design (S4) has to load and unload functions
**independently**, so each function needs its own module.

```
src/server/
├── actions/
│   ├── createNote.ts        # export default function (args, ctx) { … }
│   └── deleteNote.ts
├── components/
│   └── NoteList.ts          # export default function (args, ctx) { … returns a UI node }
└── shared/
    └── store.ts             # imported by both; inlined into each module by the bundler
```

The CLI enumerates those directories, bundles each entry independently (the
existing `bundle_module` already flattens imports depth-first, so `shared/`
inlines), and emits `dist/server/<name>.bc` plus a function table:

```json
{ "functions": [
  { "name": "createNote", "kind": "action",    "module": "server/createNote.bc",
    "sha256": "…", "timeoutMs": 5000, "memoryBytes": 33554432, "maxConcurrency": 8 },
  { "name": "NoteList",   "kind": "component", "module": "server/NoteList.bc",
    "sha256": "…", "revalidateSeconds": 10 }
]}
```

Duplicated shared code across modules is accepted: it costs bytes, buys
independent lifecycle, and content-addressed blobs (S5) dedupe identical
modules across versions. A single `server.ts` keeps working — it is treated as
one module exporting many functions, which the pool loads as a unit.

**Convention over configuration, deliberately.** Directory layout is statically
analysable by the CLI. A registration table (`export const server = {…}`) would
need the CLI to evaluate guest code at build time, and the JS subset has no
decorators to annotate with.

## 6. Files

| File | Change |
|---|---|
| `rust/crates/elpian-host/**` | **New crate** |
| `rust/Cargo.toml` | Add the member (+ tokio/hyper/tungstenite) |
| `rust/crates/elpian-vm/src/sdk/capabilities.rs` | `ServerCall`, `State`; `all()` array size |
| `rust/crates/elpian-vm/src/api.rs:89` | New host API names |
| `lib/src/vm/host_api_catalog.dart` | Regenerate |
| `lib/src/vm/governance/models.dart` | Mirror the new capabilities |
| `lib/src/vm/host_handler.dart` | Service `server.call` (client side) |
| `cli/rust/main.rs:271` | Per-function server modules + function table |
| `rust/crates/elpian-vm/src/bin/elpian-server.rs` | Shim onto `elpian-host`; delete in S6 |

## 7. Verification

- A server function calling `log`, `time.now`, `kv.set`/`kv.get` and `fs.write`
  succeeds — the direct regression test for F1 (HTTP 501 today).
- `net.fetch` from a server function with the default posture returns a typed
  null and is audited; it does **not** trap and does not reach the network.
- `server.call` from a client VM round-trips a JSON result.
- Denied capability → typed null, matching what the VM itself does for a denied
  call (`host_handler.dart:139` already encodes this shape).
- `fs.*` is confined: an app writing `../../etc/x` is refused; storage bytes
  land on that app's meter via `charge_storage`.
- Concurrency: 100 parallel invocations of a 10 ms function complete in ≈ 10 ms ×
  100/workers, not 100 × 10 ms.
- A guest trap returns `{"ok":false,"error":{"code":"guest_trap"}}` with no
  interpreter detail in the body, and the detail present in the server log.

## 8. Risks

| Risk | Mitigation |
|---|---|
| tokio/hyper is a large new dependency for a deliberately lean repo | Async front / blocking behind keeps it at the edge; record the decision, keep the `tiny_http` fallback documented |
| Warm module state across invocations surprises authors | Make it a documented contract in S4, with opt-in `stateless: true` |
| A host call that parks on I/O holds an instance for a long time | Deadlines are per *invocation*, not per turn; the pool counts parked instances against `maxConcurrency` |
| Per-function modules inflate build output | Content-addressed blobs dedupe; measure and report in `STATUS.md` |
