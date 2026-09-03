# S0 — Concurrency foundation: sound VM ownership

**Objective.** Make it possible for two Elpian guest turns to execute at the
same time in one process, with a defensible ownership story, so a server can
host more than one request at a time.

**Why first.** Every other workstream assumes concurrency. A serverless pool of
warm instances (S4) is pointless if the pool serialises on a process-wide lock,
and a per-request timeout (S4) cannot be enforced if one hung guest holds the
lock every other request needs.

---

## 1. The problem, precisely

Two facts (see `00-current-state.md` F2):

```rust
// rust/crates/elpian-vm/src/api.rs:33
static VMS: Lazy<Mutex<HashMap<String, VM>>> = Lazy::new(|| Mutex::new(HashMap::new()));

// rust/crates/elpian-vm/src/api.rs:404 — and :417, :430, :476
pub fn execute_vm(machine_id: String) -> VmExecResult {
    let mut vms = lock_tolerant(&VMS);      // ← held across the whole guest turn
    match vms.get_mut(&machine_id) { … }
}
```

```rust
// rust/crates/elpian-vm/src/sdk/vm.rs:16-22
struct VM { single_thread_executor: Option<Rc<RefCell<Executor>>>, … }
unsafe impl Send for VM {}
unsafe impl Sync for VM {}
```

The `Rc` is non-atomically refcounted. `unsafe impl Send` is only defensible
today *because* the global mutex means no two threads ever touch any VM
concurrently. Removing the lock without addressing this trades a throughput bug
for a memory-corruption bug.

`unsafe impl Sync` is worse: it claims `&VM` is shareable, which would let two
threads clone the same `Rc` at once. Nothing currently does, but nothing stops
it either.

## 2. The decision: own VMs, don't register them

Two candidate designs were considered.

**(a) Shard the registry** — `HashMap<String, Arc<Mutex<VM>>>`. The map lock is
held only for lookup; the per-VM mutex is held for the turn. Small diff, keeps
every existing call site working.

**(b) Owned handles + per-instance actors** — the server never puts VMs in the
global registry. Each instance is owned by exactly one worker thread, driven
through a channel. `VM` becomes `!Sync`, and `Send` becomes true in the only
sense that matters: the whole `Rc` graph moves as a unit and is never aliased
across threads.

**Take (b) for the server, and (a) for the embedding path.** Rationale:

- The pieces for (b) already exist and are public: `VM::compile_and_create_of_bytecode`,
  `run_func_with_input`, `continue_run`, and the inherent governance methods
  `set_limits` / `limits` / `usage` / `capabilities` (`sdk/vm.rs:66-82`).
  Nothing in the server path needs the registry.
- `VmHierarchy` is documented as **pure data — no statics, no locks**
  (`wiki/03-governance.md` §3), so the server can own its own instance and get
  aggregate accounting and subtree teardown without touching global state.
- The FFI / Flutter / Godot embeddings are single-threaded by construction and
  address VMs by id from Dart. They keep the registry; sharding it is a small
  independent win that removes lock convoys between the UI thread and any
  background pump.

## 3. Implementation

### S0.1 — Make the unsafe impls honest

```rust
// sdk/vm.rs — replace lines 21-22
// SAFETY: a VM owns its entire Rc graph and never shares an Rc with another
// VM, so moving one between threads moves the whole graph as a unit. `Sync`
// is NOT implemented: two threads must never hold `&VM` to the same instance,
// because a shared `&` permits concurrent `Rc::clone`, whose refcount is not
// atomic. Exclusive access is what makes this sound — the registry provides it
// with a per-VM mutex, and the host pool provides it with single ownership.
unsafe impl Send for VM {}
```

Removing `unsafe impl Sync` is the load-bearing part of this step. Fix the
fallout the compiler reports; if any call site genuinely needs `&VM` from two
threads, that call site is the bug.

**Audit gate — do this before writing any code.** Prove no `Rc` is ever shared
between two VMs. The one place it could happen is module import (`vm.import`,
gated by `Capability::ModuleImport`) and any cross-VM value passing
(`vm.send` in `elpian-runtime/src/manager.rs:491`). Confirm both copy or
serialise rather than aliasing. If either aliases, S0 grows a sub-task to make
it copy, and that must land before anything else in this workstream.

### S0.2 — Shard the registry

```rust
static VMS: Lazy<Mutex<HashMap<String, Arc<Mutex<VM>>>>> = …;

fn slot(machine_id: &str) -> Option<Arc<Mutex<VM>>> {
    lock_tolerant(&VMS).get(machine_id).cloned()   // map lock: lookup only
}

pub fn execute_vm(machine_id: String) -> VmExecResult {
    let Some(slot) = slot(&machine_id) else { return VmExecResult::done("\"vm_not_found\"") };
    let mut vm = lock_tolerant(&slot);             // instance lock: the turn
    if vm.is_exec_processing() { return VmExecResult::done("\"vm_busy\"") }
    drive_turn(&mut vm, |vm| { vm.run(); check_host_call(vm, "\"done\"") })
}
```

Mechanical across `api.rs`. Two things to get right:

- **Lock ordering.** Never take the map lock while holding an instance lock.
  The tree functions (`api.rs:729-854`) walk many VMs; they must collect ids
  under the map lock, release it, then act. `enforce_tree_budgets` and
  `destroy_vm_tree` are the two that need care.
- **`destroy_vm` while a turn is in flight.** Removing the `Arc` from the map
  does not cancel the turn; the last `Arc` drops when the worker finishes.
  That is the correct behaviour (no use-after-free, no half-torn-down VM), but
  it means "destroyed" and "stopped" are different states. Use
  `terminate_vm` — which sets the shared control flag the executor checks at
  each step boundary — to stop, then destroy.

### S0.3 — The instance actor (the server's ownership model)

New in the S1 crate, specified here because it is the ownership contract:

```rust
pub enum Msg {
    Invoke  { func: String, input: String, reply: Reply<InvokeOutcome> },
    HostReply { value: String },                 // resume after an async host call
    Tick,                                        // deadline / budget sweep
    Pause, Resume, Terminate { reason: String },
    Meters  { reply: Reply<ResourceUsage> },
}

pub struct Instance {          // lives on, and only on, its worker thread
    vm: VM,                    // owned outright — never in a registry
    id: InstanceId,            // app::version::fn::seq
    hierarchy_node: NodeId,    // for aggregate accounting (S5)
    inbox: Receiver<Msg>,
}
```

Rules:

1. One instance, one owner thread, one message at a time. Concurrency comes
   from having many instances, never from sharing one.
2. A host call that needs I/O parks the instance: the worker sends the request
   to the async gateway, keeps the continuation, and waits for a `HostReply`.
   The instance stays checked out for the whole logical invocation, so
   `vm_busy` can never be observed.
3. `Terminate` and deadline enforcement go through the shared control flag, not
   through the mailbox — a hung guest is not reading its mailbox. This is what
   `pause_vm` / `terminate_vm` already do, and the docs confirm the flag is
   observed *mid-flight, even while servicing a host call*
   (`wiki/03-governance.md` §4).

### S0.4 — The sweep

Client embeddings call `enforce_tree_budgets()` once per frame. A server has no
frames, so add a supervisor thread: every *N* ms (default 250), run
`enforce_tree_budgets`, expire invocation deadlines, and drive idle eviction
(S4). One thread for the whole process; it must never hold an instance lock.

### S0.5 — Fix the capability drift

Add `surface('surface')` to `ElpianCapability`
(`lib/src/vm/governance/models.dart:215`) so it stops resolving to
`ElpianCapability.other`. Small, independent, and the conformance corpus in S8
is what keeps it fixed.

## 4. Files

| File | Change |
|---|---|
| `rust/crates/elpian-vm/src/sdk/vm.rs` | Drop `unsafe impl Sync`; document `Send` |
| `rust/crates/elpian-vm/src/api.rs` | `Arc<Mutex<VM>>` slots; lookup/turn lock split; lock ordering in the tree fns |
| `rust/crates/elpian-vm/src/api/govern.rs` | Follow the slot API |
| `rust/crates/elpian-ffi/src/manager.rs` | Follow the slot API |
| `lib/src/vm/governance/models.dart` | Add the `surface` capability |
| `rust/crates/elpian-vm/tests/concurrency.rs` | **New** — see below |

## 5. Verification

- **Parallelism is real.** Two VMs each run a spin loop of *K* instructions on
  two threads. Assert wall time ≈ one loop, not two (with a generous margin).
  This test fails on `main` today and is the regression guard for F2.
- **Isolation under contention.** *N* threads × *M* VMs each mutating and
  reading module state; assert no cross-talk and no drift in `usage()`.
- **Terminate mid-flight.** Start an infinite-loop guest, `terminate_vm` from
  another thread, assert it stops within the sweep interval and its
  `trap_reason` is set.
- **Destroy during a turn** does not corrupt or leak (run under
  `RUSTFLAGS="-Z sanitizer=address"` on nightly, or Valgrind; note the result in
  `STATUS.md` — this is the step where a soundness mistake would show up).
- **`cargo test --workspace` stays green**, and the existing
  `governance_tree.rs`, `multi_vm.rs` and `ffi_boundary.rs` suites in particular.

## 6. Risks

| Risk | Mitigation |
|---|---|
| A hidden `Rc` shared between VMs makes (b) unsound | The S0.1 audit gate is a hard precondition; do not skip it |
| Lock-ordering inversion deadlocks the tree functions | Collect-then-act; one test that hammers `enforce_tree_budgets` against live spawns |
| `unsafe impl Sync` removal breaks an embedding | It is the point of the change; fix call sites rather than restoring the impl |
| Sweep thread contending with workers | It only reads meters and sets flags; never takes an instance lock |
