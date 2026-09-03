# S4 — Serverless: on-demand function VMs, and what they cost

**Objective.** Load a mini app's server function VMs on demand, keep them warm
while they are useful, unload them when they are not, and meter what each app
consumes precisely enough to bill or throttle it.

**Delivers (P4).** The instance pool with a real lifecycle, per-invocation
deadlines, idle eviction under a memory budget, cost meters and enforceable
quotas.

---

## 1. The unit

One VM instance per `(app, version, function, seq)`. Each function is its own
bytecode module (S1 §5), so instances load and unload independently.

```
app "notes" v3
├── supervisor VM node ─────────── the app's parent in the VM hierarchy
│   ├── createNote #0   Warm   idle 4s   mem 2.1 MB
│   ├── createNote #1   Busy              mem 2.4 MB
│   ├── NoteList   #0   Warm   idle 31s  mem 5.7 MB
│   └── deleteNote      Cold             (bytecode in the blob store, no instance)
```

The **supervisor node** is the reuse that makes governance free: adopt every
function instance under one per-app node in `VmHierarchy`, and the existing
machinery gives, with no new code:

- `subtree_usage(app)` — the app's total consumption across every instance
  (`api.rs:786`);
- `enforce_tree_budgets()` — an app whose aggregate blows its own budget loses
  its whole subtree, together (`api.rs:854`);
- permission intersection — a function can never hold more than the app holds,
  even if a per-function grant says otherwise (`wiki/03-governance.md` §3
  Rule 3);
- `destroy_vm_tree(app)` — one call unloads the app.

## 2. The lifecycle

```
                   invoke, no warm instance
      ┌────────┐  ─────────────────────────▶  ┌─────────┐   module init ok   ┌──────┐
      │  Cold  │                              │ Loading │ ─────────────────▶ │ Warm │
      └────────┘  ◀───────────────────────    └─────────┘                    └──┬───┘
           ▲       destroy (hard eviction)         │ trap                      │  ▲
           │                                       ▼                    invoke │  │ reply
           │                                  ┌────────┐                       ▼  │
           │        idle > hibernateAfter     │ Failed │                    ┌──────┴──┐
           ├──────  ◀── ┌──────────┐  ◀───────┴────────┘                    │  Busy   │
           │            │ Hibernate│   idle > evictAfter                    └─────────┘
           │            └──────────┘  ──────────────▶ destroy                    │
           │                                                     deadline / trap │
           └─────────────────────────────────────────────────────────────────────┘
```

| Transition | Trigger | Mechanism |
|---|---|---|
| Cold → Loading | invoke with no warm instance and headroom to add one | read blob, `VM::compile_and_create_of_bytecode`, adopt under the supervisor, apply policy **before** the first run |
| Loading → Warm | module top-level program completes | `vm.run()` once — the module-init step the current server repeats on *every* request |
| Warm → Busy | invocation dequeued | `run_func_with_input`, then the host-call loop |
| Busy → Warm | invocation completes | reply sent; instance returned to the pool |
| Warm → Hibernate | idle > `hibernateAfter` (default 60 s) | `pause_vm` — *"a paused instance consumes no CPU"* and keeps its continuation |
| Hibernate → Warm | invoke | `clear_pause` — no re-init, no cold start |
| Hibernate → Cold | idle > `evictAfter` (default 15 min), or memory pressure | `destroy_vm` |
| any → Cold | limit trap, deadline, app suspended, new version deployed | `terminate_vm` then destroy; in-flight invocation fails with a typed error |

**Order matters at load.** Apply the resolved policy — capabilities and limits —
*before* running the module's top-level program. The Dart mini-app host already
gets this right and says why: *"the resolved policy is applied to the VM before
the program runs, so a mini app is never briefly unrestricted at boot"*
(`lib/src/superapp/mini_app_host.dart:104`). The server must match it.

## 3. Concurrency and queueing

A VM executes one turn at a time. So:

- **One invocation per instance.** Concurrency for a function is instance count,
  capped by `maxConcurrency` (per function) and the app's instance budget.
- **Bounded queue** per function: `maxQueueDepth` (default 64) and
  `maxQueueWaitMs` (default 2× the function's timeout). Overflow returns
  `unavailable` immediately — a full queue rejected fast beats a full queue
  timing out slowly.
- **Scale-up** when the queue is non-empty and instances < `maxConcurrency`
  and the app's memory budget has headroom. Scale-up is synchronous with the
  request that triggered it, so the cold start is attributed to that request
  (`meta.coldStart: true`).
- **A parked instance counts as busy.** An instance waiting on a brokered HTTP
  call holds its slot. Otherwise a slow upstream silently multiplies an app's
  instance count.

## 4. Deadlines: three layers, all necessary

| Layer | Mechanism | Stops |
|---|---|---|
| Interpreter | `max_instructions_per_turn` | a tight infinite loop, at a step boundary, as a clean trap |
| Invocation | wall clock, checked by the sweep thread (S0.4) → `terminate_vm` | a guest parked on a slow host call |
| Connection | gateway request timeout | a client that vanished |

The interpreter cap alone is not enough (a guest can be slow without executing
instructions, waiting on I/O); the wall clock alone is not enough (it cannot
interrupt a guest that never yields). Both, plus the control flag the executor
checks *"between turns, and even mid-flight while servicing a host call"*
(`wiki/03-governance.md` §4).

## 5. Timers and background work

`setTimeout` / `setInterval` in a server function is a leak: a timer that
outlives its invocation means an instance that can never be evicted and work
nobody is waiting for.

Policy: `timers` is **denied by default** server-side (S1). When granted:
timers are cancelled when the invocation completes, and an interval is refused
outright. A function that needs periodic work is a scheduled function — a
manifest-declared `schedule: "*/5 * * * *"` the host drives — which is a
separate, later feature. Note it in the manifest schema now so it can be added
without a breaking change.

## 6. Cost meters

The one requirement with nothing to build on: `wiki/03-governance.md` says
outright there is no billing module and suggests reading `usage` on a timer.
This makes that a first-class component.

```rust
pub struct CostSample {                  // per invocation, per instance
    pub app: AppId, pub version: u32, pub function: String,
    pub instructions: u64,               // from ResourceUsage — the CPU proxy
    pub wall_micros: u64,
    pub peak_memory_bytes: u64,
    pub memory_byte_micros: u128,        // peak_memory × wall — the "GB-s" analogue
    pub cold_start: bool,
    pub egress_bytes_in: u64, pub egress_bytes_out: u64,
    pub storage_bytes_delta: i64,
    pub host_calls: u32,
    pub outcome: Outcome,                // Ok | Trap | Timeout | Denied | QueueOverflow
}
```

Aggregated per app per window (minute / hour / day) into a rolling meter,
persisted with the registry so a restart does not zero anyone's bill.

**Where the numbers come from.** `instructions`, `peak_memory_bytes` and
`storage_bytes` come from `ResourceUsage`, which the VM already maintains and
reports verbatim (`sdk/limits.rs`). Wall clock and egress bytes are the host's.
Nothing here needs new instrumentation inside the interpreter — which is
exactly why this design is affordable.

`instructions` is an *approximate* CPU proxy, and `memory_bytes` is documented
as *"approximate by construction"*. That is fine for quotas and cost
attribution, and it must be stated in the docs so nobody builds a
cent-accurate invoice on it.

### Quotas

```json
"quotas": {
  "instructionsPerMinute": 2000000000,
  "invocationsPerMinute": 6000,
  "concurrentInstances": 16,
  "memoryBytes": 268435456,
  "egressBytesPerDay": 5368709120,
  "storageBytes": 104857600
}
```

Enforcement ladder, in order of severity:

1. **Throttle** — queue admission returns `quota_exceeded` (HTTP 429) with
   `Retry-After`. The app stays up.
2. **Strangle** — tighten `set_limits` below current usage. The docs call this
   out as a deliberate lever: *"you can strangle a misbehaving instance without
   killing it outright"* (`wiki/03-governance.md` §2).
3. **Drain** — stop admitting, let in-flight finish, evict all instances.
4. **Suspend** — registry state change; the app 403s until an operator
   re-enables it.

Every step emits an event on the admin log so an operator can see why an app
degraded.

## 7. Deferred: snapshot / fork

The biggest remaining cold-start win is snapshotting an instance right after
module init and forking new instances from it, skipping init entirely. It needs
a serialisation format for executor state (`sdk/context.rs`, `sdk/program.rs`)
that does not exist. **Explicitly out of scope for P4** — the Hibernate state
already removes most repeated init cost for warm apps. Revisit once instance
counts make it worth the interpreter surgery, and measure first.

## 8. Files

| File | Change |
|---|---|
| `elpian-host/src/pool/**` | **New** — instances, workers, queues, eviction |
| `elpian-host/src/meter/**` | **New** — samples, aggregation, quotas, persistence |
| `elpian-host/src/gateway/routes.rs` | Admission control, 429 with `Retry-After` |
| `rust/crates/elpian-vm/src/api.rs` | Supervisor-node adoption helpers if the tree API needs a non-registry path |
| `elpian-host/src/registry/**` | Per-function limits/timeouts in the manifest (S5) |

## 9. Verification

- **Warm reuse**: two sequential invocations produce one module init
  (a counter incremented at module top level reads `1`, not `2`) — the direct
  regression test for the current create/destroy-per-request behaviour.
- **Cold-start attribution**: the first invocation reports
  `meta.coldStart: true`, the second `false`.
- **Hibernate → wake**: after `hibernateAfter`, `run_state` is `paused` and CPU
  is idle; the next invocation succeeds without re-running init.
- **Eviction under pressure**: with a small memory budget, LRU evicts the right
  instances and never one that is Busy.
- **Deadlines**: a guest in `while(true){}` is stopped by the interpreter cap;
  a guest parked on a 60 s upstream is stopped by the invocation deadline; both
  return `timeout`/`limit_exceeded` and free the instance.
- **Aggregate teardown**: an app exceeding its subtree budget loses every
  instance in one `enforce_tree_budgets` sweep and nothing belonging to another
  app.
- **Queue behaviour**: with `maxQueueDepth=4` and a blocked function, the 5th
  request gets `unavailable` in under 5 ms.
- **Meters**: a function with a known instruction count reports within a stated
  tolerance; egress bytes match what the broker actually transferred; meters
  survive a restart.
- **Benchmarks** to record in `STATUS.md`: cold start ms, warm p50/p99, invokes/s
  at concurrency 1/8/64, bytes of RSS per idle instance.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Warm state across invocations leaks user data between end users | Documented contract + `stateless: true` opt-in; the security review must cover it; consider `stateless` as the *default* for functions that read `ctx.user` |
| Instance count × VM overhead exhausts host memory | Global and per-app memory budgets gate scale-up; measure per-instance RSS in the benchmark |
| `instructions` is an unfair CPU proxy across workloads | Bill on a blend (instructions + wall + memory·time), document the approximation, never claim exactness |
| A parked instance leaks when a host call never returns | Every host call has its own timeout; the sweep terminates instances past their invocation deadline regardless of state |
