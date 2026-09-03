# 03 — Governance: capabilities, meters, and the VM tree

Elpian is built to run code you do not trust. Three orthogonal mechanisms
provide that, all enforced inside the Rust VM:

1. **Capabilities** — *what* a guest may do (`rust/crates/elpian-vm/src/sdk/capabilities.rs`).
2. **Resource limits + meters** — *how much* it may do (`rust/crates/elpian-vm/src/sdk/limits.rs`).
3. **The VM hierarchy** — how those compose across a tree of VMs
   (`rust/crates/elpian-vm/src/sdk/hierarchy.rs`), plus lifecycle control
   (`rust/crates/elpian-vm/src/sdk/lifecycle.rs`).

Because a guest's only outward effect is `askHost`, all of this is enforced at
one seam.

---

## 1. Capabilities

> Every side-effecting thing a guest can reach — logging, GPU submission, module
> import, the network, the fabricated filesystem, the clock, the random source —
> is a *capability*.

```rust
pub enum Capability {
    Logging,       // `log`
    Gpu,           // `gpu.*`
    ModuleImport,  // `vm.import`
    Network,       // `net.*`
    Storage,       // `fs.*` — native disk or browser storage
    Clock,         // `time.*`
    Randomness,    // `random.*` and the `random` builtin
    VmManage,      // `vm.*` except vm.import — spawn/steer child VMs
    Other,         // anything unmapped
}
```

### Gating is by API-name family

`Capability::for_api(name)` maps a host-API name to its gate by **prefix**, so
new APIs in a family inherit the right gate automatically:

| API name | Capability |
|---|---|
| `log` | `Logging` |
| `vm.import` | `ModuleImport` |
| `gpu.…` | `Gpu` |
| `net.…` | `Network` |
| `fs.…` | `Storage` |
| `time.…` | `Clock` |
| `random.…` | `Randomness` |
| `vm.…` (other) | `VmManage` |
| anything else | `Other` |

Stable string names for host config: `logging`, `gpu`, `module_import`,
`network`, `storage`, `clock`, `randomness`, `vm_manage`, `other`
(`Capability::as_str` / `from_str`).

### A disabled capability does not crash the guest

This is the important design decision:

> When a guest performs an `askHost` whose capability is disabled, the executor
> does **not** suspend to the host: it short-circuits the call to a typed null,
> so a guest can keep running deterministically with an interface "unplugged"
> rather than crashing.

So revoking `Network` mid-run turns every `net.*` call into `null` instead of
throwing. Guest code should treat host-call results as possibly-null.

### API

```rust
set_capability(machine_id: &str, cap: Capability, allowed: bool) -> bool;
set_capabilities(machine_id: &str, caps: CapabilitySet) -> bool;
capability_allows(machine_id: &str, api_name: &str) -> bool;
```

Capabilities can be flipped **at any time between turns**.

---

## 2. Resource limits and meters

### The policy: `ResourceLimits`

Every field is `Option<u64>`; `None` means unbounded.

| Field | Caps |
|---|---|
| `max_instructions` | Total interpreter steps across the instance's whole life — halts infinite loops |
| `max_instructions_per_turn` | Steps in a *single* turn (one `run`/`run_func`/resume) — caps latency per host call while still allowing a long-lived instance to do a lot of work overall |
| `max_memory_bytes` | Live value-memory held (approximate) |
| `max_storage_bytes` | Persistent storage in the fabricated filesystem |
| `max_call_depth` | Function-call nesting — guards native-stack exhaustion |

Two presets:

```rust
ResourceLimits::unlimited()   // trusted programs; the historical behaviour
ResourceLimits::sandboxed()   // untrusted third-party modules
```

`sandboxed()` is:

```rust
max_instructions:          Some(50_000_000),
max_instructions_per_turn: Some( 5_000_000),
max_memory_bytes:          Some(64 * 1024 * 1024),   // 64 MiB
max_storage_bytes:         Some(16 * 1024 * 1024),   // 16 MiB
max_call_depth:            Some(1024),
```

### The meters: `ResourceUsage`

Reported verbatim to the host "so it can build dashboards or react before a hard
cap is hit":

| Counter | Meaning |
|---|---|
| `instructions` | Total steps over the instance's life |
| `instructions_this_turn` | Steps in the current turn (reset each turn) |
| `memory_bytes` | Live value-memory now (approximate) |
| `peak_memory_bytes` | High-water mark — useful for sizing limits |
| `storage_bytes` | Persistent storage occupied |
| `call_depth` | Current nesting depth |
| `peak_call_depth` | Deepest nesting ever reached |

Memory accounting is **approximate by construction**: the governor charges the
shallow footprint of each allocated value and credits it back when the holding
scope is torn down. It is "a faithful, monotonic-ish proxy the host can cap — not
a byte-exact allocator", designed so a runaway allocation loop is stopped long
before it exhausts the real process heap.

### The `Governor`

One per VM instance. Couples policy + tally and performs checked charges on the
hot path (`charge_instruction` runs once per executor loop iteration). Charges
are **saturating**, and every overrun produces a typed `LimitError`:

```rust
pub struct LimitError { pub kind: LimitKind, pub limit: u64, pub requested: u64 }
pub enum LimitKind { Instructions, InstructionsPerTurn, Memory, Storage, CallDepth }
```

The executor converts a `LimitError` into a **controlled trap**, not a panic.
`LimitKind::as_str()` gives the stable tag that also appears in the guest-visible
trap value: `instructions`, `instructions_per_turn`, `memory`, `storage`,
`call_depth`.

`set_limits` retains already-consumed usage — *tightening a limit below current
usage will trap on the next charge*. That is a deliberate lever: you can strangle
a misbehaving instance without killing it outright.

### API

```rust
set_limits(machine_id: &str, limits: ResourceLimits) -> bool;
limits(machine_id: &str) -> Option<ResourceLimits>;
usage(machine_id: &str) -> Option<ResourceUsage>;          // this VM only
subtree_usage(machine_id: &str) -> Option<ResourceUsage>;  // this VM + descendants
charge_storage(machine_id: &str, delta: i64) -> Result<(), String>;
```

`charge_storage` lets the host's fabricated filesystem bill through the same
governor, so "a single budget covers heap + disk if the host wishes".

---

## 3. The multi-VM hierarchy

A VM may instantiate other VMs (gated by the `VmManage` capability). The
instantiator becomes the **parent** and holds full control of the child —
lifecycle, limits, permissions. Three invariants define the tree:

### Rule 1 — Lifecycle binding

Terminating a VM terminates its whole descendant subtree. `subtree(id)`
enumerates it pre-order (parents before children) and the embedder applies the
operation to each.

### Rule 2 — Aggregate resource accounting

> A parent's consumption is measured as its *own* usage plus the usage of every
> VM in its descendant subtree. A parent whose aggregate blows its own budget
> takes its entire subtree down with it.

The design note calls this the **"handle it or share its fate" rule**: a hung
child that the parent never handles eventually costs the parent, its other
children, and the hung child their lives. This makes delegation safe by default
— you cannot escape your budget by spawning helpers.

Enforcement is a periodic sweep, meant to be called **once per host frame**:

```rust
pub fn enforce_tree_budgets() -> Vec<(String, String, Vec<String>)>;
// → (subtree_root, axis, destroyed_ids) per violation
```

It walks every root's subtree top-down, compares each VM's own limit policy
against `subtree_usage`, and on an overrun destroys that entire subtree,
skipping ids already inside a destroyed one.

### Rule 3 — Permission intersection

> A VM's *effective* capability set is the AND of the *locally granted* sets
> along its ancestor path.

- A parent that lacks a permission **can never confer it**.
- A parent that has one may grant it to any child.
- An on-the-fly change anywhere in the path is recomputed for the whole
  descendant subtree at once.
- A VM absent from the local-grants map is treated as **allow-all** — the
  posture of a standalone/root VM.

`adopt(parent, child)` refuses to create a cycle and refuses a child that
already has a parent.

### API

```rust
adopt_vm(parent_id: &str, child_id: &str) -> bool;
vm_parent(machine_id: &str) -> Option<String>;
vm_children(machine_id: &str) -> Vec<String>;
vm_subtree(machine_id: &str) -> Vec<String>;
vm_is_ancestor_or_self(ancestor: &str, machine_id: &str) -> bool;

set_local_capability(machine_id: &str, cap: Capability, allowed: bool) -> bool;
local_capabilities(machine_id: &str) -> CapabilitySet;      // as granted
effective_capabilities(machine_id: &str) -> CapabilitySet;  // after intersection

terminate_vm_tree(machine_id: &str) -> Vec<String>;
pause_vm_tree(machine_id: &str)     -> Vec<String>;
destroy_vm_tree(machine_id: &str)   -> Vec<String>;
enforce_tree_budgets()              -> Vec<(String, String, Vec<String>)>;
```

`VmHierarchy` is **pure data** — no statics, no locks — so it is unit-testable in
isolation. The process-wide instance and the functions combining it with the live
VM registry live in `rust/crates/elpian-vm/src/api.rs`.

---

## 4. Lifecycle control

Orthogonal to the host-call rhythm. The executor is *already* pausing (it
suspends on every `askHost`); these controls let the embedder steer an instance
independently.

```rust
pub enum RunState {
    Running,             // free to execute
    PauseRequested,      // will suspend at the next step boundary
    Paused,              // suspended with its continuation intact
    TerminateRequested,  // will unwind at the next step boundary
    Terminated,          // fully stopped; further drive calls are inert
}
```

String forms: `running`, `pause_requested`, `paused`, `terminate_requested`,
`terminated`.

- **Pause** stops at the next interpreter step boundary, preserving the full
  continuation (pointer, register stack, scope memory). *A paused instance
  consumes no CPU.*
- **Resume** picks up exactly where it left off.
- **Terminate** unwinds at the next step boundary; the instance is finished.

The control flag is shared (`Rc<RefCell<…>>`) between the public VM handle and
the executor, so the host can flip it **between turns, and even mid-flight while
servicing a host call**, and the executor observes it at the next step.

```rust
pause_vm(machine_id) -> bool;
clear_pause(machine_id) -> bool;
resume_execution(machine_id: String) -> VmExecResult;
terminate_vm(machine_id) -> bool;
run_state(machine_id) -> Option<RunState>;
trap_reason(machine_id) -> Option<String>;
```

---

## A worked policy

Running an untrusted plugin as a child of your app VM:

```rust
// 1. Create the child.
create_vm_from_bytecode("plugin-a".into(), bytes);

// 2. Put it under the app VM — inherits the intersection of ancestor caps.
adopt_vm("app", "plugin-a");

// 3. Grant it only what it needs (it can never exceed the parent's set).
set_local_capability("plugin-a", Capability::Logging, true);
set_local_capability("plugin-a", Capability::Network, false);
set_local_capability("plugin-a", Capability::VmManage, false); // no grandchildren

// 4. Bound its work.
set_limits("plugin-a", ResourceLimits::sandboxed());

// 5. Each frame: meter, and enforce aggregate budgets across the whole tree.
let u = subtree_usage("app").unwrap();
for (root, axis, killed) in enforce_tree_budgets() {
    eprintln!("subtree {root} exceeded {axis}; destroyed {killed:?}");
}
```

## What is *not* here

There is no billing or pricing module **in the VM**, and there should not be:
the VM's job is budgets and counters — instruction, memory, storage and depth,
metered per instance and aggregated per subtree — which a host reads and turns
into whatever accounting model it wants.

What used to be missing was any host that did so. That gap is closed on the
server side: `elpian-host` accumulates per-app meters (invocations, cold starts,
instructions, compute ms, peak memory, storage) and acts on them through a
`throttle → strangle → drain → suspend` ladder applied *before* an invocation
runs. See [21 — Running a host](21-hosting.md) §5.

On a **client** super app the position is unchanged: read `usage` /
`subtree_usage` on a timer and aggregate outside the VM. There is still no
per-tenant billing, and no monetary anything anywhere — the meters count
resources, and turning resources into money is the operator's business.
