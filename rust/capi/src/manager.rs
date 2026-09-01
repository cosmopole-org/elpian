//! # The multi-VM manager — a tree of Elpian VMs sharing one Godot scene
//!
//! One `ElpianVM` Godot node no longer hosts a single guest: it hosts a
//! **manager** owning a *tree* of VM instances. The root VM (the node's own
//! program) manages the whole scene and the inter-VM space; any VM holding the
//! `vm_manage` capability can instantiate further VMs with
//! `askHost("vm.spawn", …)` and holds full control of the child — lifecycle
//! (pause / resume / terminate), resource limits, capability permissions and
//! messaging. The layers divide cleanly:
//!
//! ```text
//!  guest program (per VM)   this module (Rust)              C++ bridge
//!  ──────────────────       ───────────────────             ──────────
//!  VMs.spawn(...)   ──▶  vm.*  : serviced HERE (spawn/pause/resume/terminate/
//!                                limits/usage/permissions/send/…, tree rules
//!                                enforced via elpian_vm::api's hierarchy)
//!  GD.create(...)   ──▶  godot.*: sanitized (sandbox tag injected, callback
//!                                ids namespaced per VM) and forwarded to ──▶ GodotController
//! ```
//!
//! ## The tree rules (backed by `elpian_vm::sdk::hierarchy`)
//!
//! * **Lifecycle binding** — terminating a VM terminates its entire descendant
//!   subtree; a parent's death takes all children (and their children…) along.
//! * **Aggregate budgets** — a parent's resource usage is measured as its own
//!   plus its whole descendant subtree; if the aggregate blows the parent's own
//!   limits, the *whole branch* (parent, siblings, offender) is terminated
//!   together. A hung child first traps on its own per-turn instruction cap;
//!   the parent is notified (`__vmNotify(["trapped", id, reason])`) and can
//!   clean up — if it never does, the aggregate rule eventually fires.
//! * **Permission intersection** — a VM's effective capabilities are the AND of
//!   the local grants along its ancestor path. Granting a child something the
//!   parent lacks is inert; an on-the-fly revoke anywhere is pushed to the
//!   whole affected subtree at once.
//!
//! ## The Godot node sandbox
//!
//! Every spawned VM is **assigned a node** in the shared scene (chosen by its
//! parent, verified to lie inside the parent's own sandbox). All of the VM's
//! engine access is confined to that node's subtree: the manager stamps every
//! forwarded `godot.op`/`godot.batch` op with the caller's sandbox root handle
//! (`"__sbx"`, a key stripped from guest input first — a guest cannot forge
//! it), and the C++ controller enforces containment when resolving object
//! references. A parent can freely manipulate its children's node trees (they
//! are inside its own sandbox by construction); a child can never reach out.
//! The root VM (and any VM granted the `scene` permission by a scene-holding
//! ancestor) is unrestricted — that is the "manages the whole scene" role.
//!
//! ## Reentrancy model
//!
//! Host calls arrive while the *calling* VM is suspended mid-`drive`, so the
//! hook can never touch another runtime directly. Everything cross-VM is
//! either keyed control state (`elpian_vm::api`, id-addressed, safe mid-hook)
//! or a queued command the manager applies in [`VmManager::settle`] after the
//! current turn completes: child boots, removals, notifications, messages and
//! resume-drives. `settle` runs after every entry point (run / invoke / pump),
//! so "deferred" still means *within the same engine frame*.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;

// The VM-management system itself is language-agnostic: guests are opaque
// programs behind neutral names. The one language-specific thing about it is
// which front-end compiles guest source, and that is confined to
// [`GuestLang`] + [`compile_guest`] — swap the front-end there and nothing
// else changes.
use dart::governance::{DartCapabilitySet as GuestCapabilitySet, ResourceMeter};
use dart::runtime::DartRuntime as GuestRuntime;

/// Which front-end compiles a guest program. Both lower to the same Elpian
/// AST → bytecode and speak the identical bridge protocol; the language only
/// decides the parser and which prelude (`godot.dart` / `godot.js`) is
/// composed ahead of the user source.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GuestLang {
    Dart,
    Js,
}

impl GuestLang {
    /// Parse a guest-supplied language name ("js"/"javascript" or
    /// "dart"; anything else defaults to `fallback`).
    fn from_name(name: &str, fallback: GuestLang) -> GuestLang {
        match name.to_ascii_lowercase().as_str() {
            "js" | "javascript" => GuestLang::Js,
            "dart" => GuestLang::Dart,
            _ => fallback,
        }
    }
}

/// Compile a guest program (source text, with the godot prelude already
/// composed) into a fresh runtime. The single seam to the language front-ends;
/// everything above it deals in guests, machines and VMs only.
fn compile_guest(
    machine_id: String,
    program: &str,
    lang: GuestLang,
    meter: ResourceMeter,
) -> Result<GuestRuntime, String> {
    match lang {
        GuestLang::Dart => {
            GuestRuntime::from_dart(machine_id, program, GuestCapabilitySet::full(), meter)
                .map_err(|e| format!("{e:?}"))
        }
        GuestLang::Js => {
            GuestRuntime::from_js(machine_id, program, GuestCapabilitySet::full(), meter)
                .map_err(|e| format!("{e:?}"))
        }
    }
}
use elpian_vm::api as vm_api;
use elpian_vm::sdk::capabilities::Capability;
use elpian_vm::sdk::limits::{ResourceLimits, ResourceUsage};
use serde_json::{json, Map, Value};

use crate::{compose_godot_program, compose_godot_program_js};

/// Compose the language's prelude ahead of a user program.
fn compose_for(lang: GuestLang, user_source: &str) -> String {
    match lang {
        GuestLang::Dart => compose_godot_program(user_source),
        GuestLang::Js => compose_godot_program_js(user_source),
    }
}

/// The engine-bridge seam: `(api_name, args) -> reply`. The C ABI wraps the
/// GDExtension's callback into this; tests plug a mock engine in directly.
pub type BridgeFn = Box<dyn FnMut(&str, &[Value]) -> Option<Value>>;

/// The root VM's id. Guest-visible vm ids start here and count up.
pub const ROOT_VM: u64 = 1;

/// Namespace a guest-local callback id into the manager-global id space:
/// the owning VM rides the high 32 bits. Both halves stay well inside the
/// f64-exact integer range (< 2^53) for every realistic vm/callback count, so
/// the id survives JSON round-trips through the engine.
fn encode_cb(vm: u64, local: i64) -> i64 {
    ((vm as i64) << 32) | (local & 0xFFFF_FFFF)
}

fn decode_cb(global: i64) -> (u64, i64) {
    (((global >> 32) & 0xFFFF_FFFF) as u64, global & 0xFFFF_FFFF)
}

/// Per-VM control record (the data plane — the `GuestRuntime` — lives on the
/// manager, not here, so hooks can read metadata mid-turn).
struct VmMeta {
    machine_id: String,
    label: String,
    /// The front-end this VM's program was compiled with. Children inherit it
    /// unless their spawn options say otherwise (`{"lang": "js"|"dart"}`).
    lang: GuestLang,
    parent: Option<u64>,
    children: Vec<u64>,
    /// The Godot node handle this VM is sandboxed to (0 for the root VM: the
    /// hosting ElpianVM node itself, unrestricted).
    node_handle: i64,
    /// Locally granted whole-scene access. Effective scene access is the AND
    /// of this flag along the ancestor path (computed on the fly — it must
    /// reflect on-the-fly changes instantly).
    local_scene: bool,
    /// Manager-level pause: no events, no pumps, no messages delivered.
    paused: bool,
    /// Terminated / trapped / removed — kept for state queries.
    dead: bool,
    trap_notified: bool,
    log_cursor: usize,
}

/// Deferred cross-VM work, applied by [`VmManager::settle`].
enum Command {
    /// Destroy a subtree rooted at `vm` (runtime drop + registry destroy) and
    /// notify its parent.
    Remove { vm: u64, reason: String },
    /// Deliver `__vmNotify(payload)` to `target`.
    Notify { target: u64, payload: Value },
    /// Deliver `__vmMessage(payload)` to `target`.
    Message { target: u64, payload: Value },
    /// Drive a mid-turn-paused VM's preserved continuation forward.
    ResumeDrive { vm: u64 },
}

/// State shared between the manager and every per-VM host hook.
struct Shared {
    bridge: RefCell<Option<BridgeFn>>,
    meta: RefCell<HashMap<u64, VmMeta>>,
    by_machine: RefCell<HashMap<String, u64>>,
    /// Creation order — deterministic iteration for broadcasts/logs.
    order: RefCell<Vec<u64>>,
    /// Children spawned mid-turn, awaiting adoption + boot by `settle`.
    pending_boot: RefCell<Vec<(u64, GuestRuntime)>>,
    commands: RefCell<VecDeque<Command>>,
    /// Manager-level diagnostics surfaced through the host log.
    host_log: RefCell<Vec<String>>,
    next_vm: Cell<u64>,
    /// Machine-id prefix for spawned children.
    base: String,
}

impl Shared {
    fn machine_of(&self, vm: u64) -> Option<String> {
        self.meta.borrow().get(&vm).map(|m| m.machine_id.clone())
    }

    fn parent_of(&self, vm: u64) -> Option<u64> {
        self.meta.borrow().get(&vm).and_then(|m| m.parent)
    }

    /// Whether `ancestor` is `vm` or on `vm`'s parent chain.
    fn is_ancestor_or_self(&self, ancestor: u64, vm: u64) -> bool {
        let meta = self.meta.borrow();
        let mut cursor = Some(vm);
        while let Some(current) = cursor {
            if current == ancestor {
                return true;
            }
            cursor = meta.get(&current).and_then(|m| m.parent);
        }
        false
    }

    /// `vm` plus all descendants, pre-order (from the meta tree).
    fn subtree(&self, vm: u64) -> Vec<u64> {
        let meta = self.meta.borrow();
        let mut out = vec![vm];
        let mut i = 0;
        while i < out.len() {
            if let Some(m) = meta.get(&out[i]) {
                out.extend(m.children.iter().copied());
            }
            i += 1;
        }
        out
    }

    /// Effective whole-scene access: every VM on the ancestor path (self
    /// included) must hold the local grant. Walked live so a revoke anywhere
    /// takes effect on the very next op.
    fn effective_scene(&self, vm: u64) -> bool {
        let meta = self.meta.borrow();
        let mut cursor = Some(vm);
        while let Some(current) = cursor {
            match meta.get(&current) {
                Some(m) if m.local_scene => cursor = m.parent,
                _ => return false,
            }
        }
        true
    }

    /// The sandbox root handle to stamp on this VM's engine ops
    /// (0 = unrestricted: the whole-scene role).
    fn sandbox_of(&self, vm: u64) -> i64 {
        if self.effective_scene(vm) {
            0
        } else {
            self.meta.borrow().get(&vm).map(|m| m.node_handle).unwrap_or(0)
        }
    }

    fn log(&self, line: String) {
        self.host_log.borrow_mut().push(line);
    }

    /// Call the engine bridge. `None` when no bridge is installed or the
    /// bridge declines the name.
    fn forward(&self, api_name: &str, args: &[Value]) -> Option<Value> {
        let mut slot = self.bridge.borrow_mut();
        slot.as_mut().and_then(|f| f(api_name, args))
    }
}

fn vm_error(msg: &str) -> Value {
    // The wire tag is the bridge-wide error convention (the prelude, the
    // guest-runtime layer and the C++ controller all produce/consume it) —
    // kept verbatim for protocol compatibility.
    json!({ "__dart_error__": msg })
}

/// Namespace a guest-allocated engine handle id into the calling VM's id
/// space. Every VM's prelude counts handles from 1, and the C++ controller
/// keys all of them in ONE map — without this, a child VM's node ids collide
/// with (and silently shadow) its parent's, so the child's scene ops resolve
/// to the wrong nodes or to nothing (Godot: 'Parameter "p_child" is null').
/// Host-assigned handles are negative and pass through. Same (vm<<32)|local
/// scheme as callbacks; idempotent for ids already in the caller's space.
fn encode_handle(vm: u64, id: i64) -> i64 {
    if id > 0 {
        encode_cb(vm, id)
    } else {
        id
    }
}

/// Recursively rewrite guest handle ids (`def`/`ref`/`obj`/`chk`/`free`/
/// `base`/`grant` keys — the exact shapes the C++ controller resolves as
/// handles, wherever they appear) into the calling VM's id space.
fn rewrite_handles(v: &mut Value, vm: u64) {
    match v {
        Value::Array(a) => {
            for e in a {
                rewrite_handles(e, vm);
            }
        }
        Value::Object(m) => {
            for key in ["def", "ref", "obj", "chk", "free", "base", "grant"] {
                if let Some(id) = m.get(key).and_then(|x| x.as_i64()) {
                    m.insert(key.into(), json!(encode_handle(vm, id)));
                }
            }
            for (_k, e) in m.iter_mut() {
                rewrite_handles(e, vm);
            }
        }
        _ => {}
    }
}

/// Strip any guest-forged sandbox tag from an op, namespace its callback and
/// handle ids into the calling VM's id space, and stamp the caller's real
/// sandbox root.
fn sanitize_op(op: &mut Value, vm: u64, sandbox: i64) {
    rewrite_callables(op, vm);
    rewrite_handles(op, vm);
    if let Value::Object(m) = op {
        m.remove("__sbx");
        if (m.contains_key("connect") || m.contains_key("disconnect")) && m.contains_key("cb") {
            if let Some(local) = m.get("cb").and_then(|v| v.as_i64()) {
                m.insert("cb".into(), json!(encode_cb(vm, local)));
            }
        }
        if sandbox != 0 {
            m.insert("__sbx".into(), json!(sandbox));
        }
    }
}

/// Recursively rewrite `{"callable": n}` wire tags (the exact shape the C++
/// controller interprets as a bridged Callable, wherever it appears) into the
/// VM-namespaced id space, so signal/callable dispatch can be routed back to
/// the owning VM.
fn rewrite_callables(v: &mut Value, vm: u64) {
    match v {
        Value::Array(a) => {
            for e in a {
                rewrite_callables(e, vm);
            }
        }
        Value::Object(m) => {
            if m.len() == 1 {
                if let Some(local) = m.get("callable").and_then(|x| x.as_i64()) {
                    m.insert("callable".into(), json!(encode_cb(vm, local)));
                    return;
                }
            }
            for (_k, e) in m.iter_mut() {
                rewrite_callables(e, vm);
            }
        }
        _ => {}
    }
}

/// Parse the `limits` option map into a VM resource-limit policy.
fn parse_limits(v: &Value) -> Option<ResourceLimits> {
    let m = v.as_object()?;
    let get = |k: &str| m.get(k).and_then(|x| x.as_u64());
    Some(ResourceLimits {
        max_instructions: get("instructions"),
        max_instructions_per_turn: get("instructionsPerTurn"),
        max_memory_bytes: get("memoryBytes"),
        max_storage_bytes: get("storageBytes"),
        max_call_depth: get("callDepth"),
    })
}

fn usage_json(u: &ResourceUsage) -> Value {
    json!({
        "instructions": u.instructions,
        "instructionsThisTurn": u.instructions_this_turn,
        "memoryBytes": u.memory_bytes,
        "peakMemoryBytes": u.peak_memory_bytes,
        "storageBytes": u.storage_bytes,
        "callDepth": u.call_depth,
        "peakCallDepth": u.peak_call_depth,
    })
}

fn limits_json(l: &ResourceLimits) -> Value {
    // 0 = unbounded (sentinel; the guest-level null cannot be told apart
    // from the VM's typed null across the seam).
    let put = |v: Option<u64>| Value::from(v.unwrap_or(0));
    json!({
        "instructions": put(l.max_instructions),
        "instructionsPerTurn": put(l.max_instructions_per_turn),
        "memoryBytes": put(l.max_memory_bytes),
        "storageBytes": put(l.max_storage_bytes),
        "callDepth": put(l.max_call_depth),
    })
}

/// The per-VM host hook environment. Captured by each runtime's `HostHook`
/// closure; `Send` is asserted under the crate's single-thread embedding
/// contract (see the module docs of `lib.rs`), exactly like the C bridge.
struct HookEnv {
    shared: Rc<Shared>,
    vm: u64,
}
unsafe impl Send for HookEnv {}

impl HookEnv {
    fn handle(&self, name: &str, args: &[Value]) -> Option<Value> {
        match name {
            n if n.starts_with("vm.") => Some(self.service_vm(n, args)),
            "godot.op" => {
                let mut op = args.first().cloned().unwrap_or(Value::Null);
                sanitize_op(&mut op, self.vm, self.shared.sandbox_of(self.vm));
                self.shared.forward("godot.op", &[op])
            }
            "godot.batch" => {
                let mut ops = args.first().cloned().unwrap_or(Value::Null);
                let sandbox = self.shared.sandbox_of(self.vm);
                if let Value::Array(list) = &mut ops {
                    for op in list {
                        sanitize_op(op, self.vm, sandbox);
                    }
                }
                self.shared.forward("godot.batch", &[ops])
            }
            // The Flutter UI seam is the exact twin of the Godot seam: a
            // `flutter.op`/`flutter.batch` op array crosses to the C++
            // `FlutterController`, which drives an embedded Flutter engine. The
            // ops carry the same wire vocabulary the Godot bridge uses —
            // `{"ref": id}` for the parent Godot node a Flutter view mounts
            // under, `{"callable": n}`/`"cb"` for widget event handlers — so the
            // identical `sanitize_op` applies: callables/handles are namespaced
            // into the calling VM's id space and the op is stamped with the VM's
            // sandbox root (`__sbx`). A sandboxed VM can therefore only mount a
            // Flutter surface under a node inside its own subtree, exactly as
            // for native Godot nodes, and widget-event callbacks route back to
            // the owning VM through the shared dispatch queue.
            "flutter.op" => {
                let mut op = args.first().cloned().unwrap_or(Value::Null);
                sanitize_op(&mut op, self.vm, self.shared.sandbox_of(self.vm));
                self.shared.forward("flutter.op", &[op])
            }
            "flutter.batch" => {
                let mut ops = args.first().cloned().unwrap_or(Value::Null);
                let sandbox = self.shared.sandbox_of(self.vm);
                if let Value::Array(list) = &mut ops {
                    for op in list {
                        sanitize_op(op, self.vm, sandbox);
                    }
                }
                self.shared.forward("flutter.batch", &[ops])
            }
            // The React Native UI seam is the third twin of the Godot seam: an
            // `rn.op`/`rn.batch` op array crosses to the JavaScript host, which
            // drives a real React Native / Expo widget tree (2D) and embedded
            // Godot `Scene3D` worlds (3D). It speaks the identical wire
            // vocabulary — `{"ref": id}` handles, `"cb"` callback ids — so the
            // same `sanitize_op` applies: handles/callables are namespaced into
            // the calling VM's id space and the op is stamped with the VM's
            // sandbox root (`__sbx`). A sandboxed child VM can therefore only
            // touch widgets inside its own assigned subtree, exactly as for
            // native Godot nodes, and widget events route back to the owning VM.
            "rn.op" => {
                let mut op = args.first().cloned().unwrap_or(Value::Null);
                sanitize_op(&mut op, self.vm, self.shared.sandbox_of(self.vm));
                self.shared.forward("rn.op", &[op])
            }
            "rn.batch" => {
                let mut ops = args.first().cloned().unwrap_or(Value::Null);
                let sandbox = self.shared.sandbox_of(self.vm);
                if let Value::Array(list) = &mut ops {
                    for op in list {
                        sanitize_op(op, self.vm, sandbox);
                    }
                }
                self.shared.forward("rn.batch", &[ops])
            }
            other => self.shared.forward(other, args),
        }
    }

    /// Parse the target vm id from `args[idx]` and check the caller may manage
    /// it: itself or any descendant (plus, when `allow_parent`, its direct
    /// parent — the messaging uplink).
    fn authorize(&self, args: &[Value], idx: usize, allow_parent: bool) -> Result<u64, Value> {
        let target = args
            .get(idx)
            .and_then(|v| v.as_u64())
            .ok_or_else(|| vm_error("vm.*: missing target vm id"))?;
        if !self.shared.meta.borrow().contains_key(&target) {
            return Err(vm_error(&format!("vm.*: unknown vm {target}")));
        }
        let allowed = self.shared.is_ancestor_or_self(self.vm, target)
            || (allow_parent && self.shared.parent_of(self.vm) == Some(target));
        if !allowed {
            return Err(vm_error(&format!(
                "vm.*: vm {} may not manage vm {} (outside its subtree)",
                self.vm, target
            )));
        }
        Ok(target)
    }

    fn service_vm(&self, name: &str, args: &[Value]) -> Value {
        match name {
            "vm.spawn" => self.spawn(args),
            "vm.pause" => self.with_target(args, false, |env, target| {
                let subtree = env.shared.subtree(target);
                {
                    let mut meta = env.shared.meta.borrow_mut();
                    for id in &subtree {
                        if let Some(m) = meta.get_mut(id) {
                            m.paused = true;
                        }
                    }
                }
                if let Some(machine) = env.shared.machine_of(target) {
                    vm_api::pause_vm_tree(&machine);
                }
                json!(subtree.len())
            }),
            "vm.resume" => self.with_target(args, false, |env, target| {
                let subtree = env.shared.subtree(target);
                {
                    let mut meta = env.shared.meta.borrow_mut();
                    for id in &subtree {
                        if let Some(m) = meta.get_mut(id) {
                            m.paused = false;
                        }
                    }
                }
                let mut cmds = env.shared.commands.borrow_mut();
                for id in &subtree {
                    cmds.push_back(Command::ResumeDrive { vm: *id });
                }
                json!(subtree.len())
            }),
            "vm.terminate" => self.with_target(args, false, |env, target| {
                if let Some(machine) = env.shared.machine_of(target) {
                    vm_api::terminate_vm_tree(&machine);
                }
                env.shared.commands.borrow_mut().push_back(Command::Remove {
                    vm: target,
                    reason: format!("terminated by vm {}", env.vm),
                });
                Value::Bool(true)
            }),
            "vm.state" => self.with_target(args, true, |env, target| {
                let (label, paused, dead) = {
                    let meta = env.shared.meta.borrow();
                    let m = meta.get(&target).expect("authorized target exists");
                    (m.label.clone(), m.paused, m.dead)
                };
                let machine = env.shared.machine_of(target).unwrap_or_default();
                // "" (not JSON null) when untrapped: the VM's typed null is
                // not the guest-level null, so sentinels keep guest-side
                // comparisons and string concatenation well-defined.
                json!({
                    "id": target,
                    "label": label,
                    "state": vm_api::run_state(&machine)
                        .map(|s| s.as_str())
                        .unwrap_or("destroyed"),
                    "trap": vm_api::trap_reason(&machine).unwrap_or_default(),
                    "paused": paused,
                    "alive": !dead && vm_api::vm_exists(machine.clone()),
                })
            }),
            "vm.usage" => self.with_target(args, true, |env, target| {
                let machine = env.shared.machine_of(target).unwrap_or_default();
                vm_api::usage(&machine).map(|u| usage_json(&u)).unwrap_or(Value::Null)
            }),
            "vm.usageTree" => self.with_target(args, true, |env, target| {
                let machine = env.shared.machine_of(target).unwrap_or_default();
                vm_api::subtree_usage(&machine).map(|u| usage_json(&u)).unwrap_or(Value::Null)
            }),
            "vm.limits" => self.with_target(args, true, |env, target| {
                let machine = env.shared.machine_of(target).unwrap_or_default();
                vm_api::limits(&machine).map(|l| limits_json(&l)).unwrap_or(Value::Null)
            }),
            "vm.setLimits" => self.with_target(args, false, |env, target| {
                let Some(limits) = args.get(1).and_then(parse_limits) else {
                    return vm_error("vm.setLimits: expected a limits map");
                };
                let machine = env.shared.machine_of(target).unwrap_or_default();
                json!(vm_api::set_limits(&machine, limits))
            }),
            "vm.setPermission" => self.set_permission(args),
            "vm.permissions" => self.with_target(args, true, |env, target| {
                let machine = env.shared.machine_of(target).unwrap_or_default();
                let local = vm_api::local_capabilities(&machine);
                let effective = vm_api::effective_capabilities(&machine);
                let mut local_map = Map::new();
                let mut eff_map = Map::new();
                for cap in Capability::all() {
                    local_map.insert(cap.as_str().into(), json!(local.is_allowed(cap)));
                    eff_map.insert(cap.as_str().into(), json!(effective.is_allowed(cap)));
                }
                json!({
                    "scene": env.shared.effective_scene(target),
                    "local": local_map,
                    "effective": eff_map,
                })
            }),
            "vm.list" => {
                // Default target: the caller itself.
                let target = if args.is_empty() {
                    self.vm
                } else {
                    match self.authorize(args, 0, true) {
                        Ok(t) => t,
                        Err(e) => return e,
                    }
                };
                let children: Vec<u64> = self
                    .shared
                    .meta
                    .borrow()
                    .get(&target)
                    .map(|m| m.children.clone())
                    .unwrap_or_default();
                let list: Vec<Value> = children
                    .iter()
                    .map(|id| {
                        let meta = self.shared.meta.borrow();
                        let m = &meta[id];
                        json!({
                            "id": id,
                            "label": m.label,
                            "paused": m.paused,
                            "alive": !m.dead,
                        })
                    })
                    .collect();
                json!(list)
            }
            "vm.send" => self.with_target_allow_parent(args, |env, target| {
                let msg = args.get(1).cloned().unwrap_or(Value::Null);
                let paused = env.shared.meta.borrow().get(&target).map(|m| m.paused || m.dead);
                if paused != Some(false) {
                    return vm_error(&format!("vm.send: vm {target} cannot receive"));
                }
                env.shared
                    .commands
                    .borrow_mut()
                    .push_back(Command::Message { target, payload: json!([env.vm, msg]) });
                Value::Bool(true)
            }),
            "vm.grant" => self.with_target(args, false, |env, target| {
                let Some(handle) = args.get(1).and_then(|v| v.as_i64()) else {
                    return vm_error("vm.grant: expected [vmId, handle]");
                };
                let target_sbx = env.shared.sandbox_of(target);
                if target_sbx == 0 {
                    return Value::Bool(true); // target is unrestricted already
                }
                let mut op = json!({ "grant": encode_handle(env.vm, handle), "sbx": target_sbx });
                let caller_sbx = env.shared.sandbox_of(env.vm);
                if caller_sbx != 0 {
                    op["__sbx"] = json!(caller_sbx);
                }
                env.shared.forward("godot.op", &[op]).unwrap_or(Value::Bool(false))
            }),
            "vm.info" => {
                let meta = self.shared.meta.borrow();
                let m = &meta[&self.vm];
                json!({
                    "id": self.vm,
                    // 0 = no parent (the root); vm ids start at 1.
                    "parent": m.parent.unwrap_or(0),
                    "label": m.label,
                    "scene": self.shared.effective_scene(self.vm),
                    "node": m.node_handle,
                })
            }
            other => vm_error(&format!("unknown vm api: {other}")),
        }
    }

    fn with_target(
        &self,
        args: &[Value],
        allow_read_self: bool,
        f: impl FnOnce(&Self, u64) -> Value,
    ) -> Value {
        // Reads may address the parent too (a child may inspect itself and ask
        // about its own place); management verbs are strictly self + subtree.
        match self.authorize(args, 0, allow_read_self) {
            Ok(target) => f(self, target),
            Err(e) => e,
        }
    }

    fn with_target_allow_parent(
        &self,
        args: &[Value],
        f: impl FnOnce(&Self, u64) -> Value,
    ) -> Value {
        match self.authorize(args, 0, true) {
            Ok(target) => f(self, target),
            Err(e) => e,
        }
    }

    fn set_permission(&self, args: &[Value]) -> Value {
        let target = match self.authorize(args, 0, false) {
            Ok(t) => t,
            Err(e) => return e,
        };
        let Some(name) = args.get(1).and_then(|v| v.as_str()) else {
            return vm_error("vm.setPermission: expected [vmId, name, allowed]");
        };
        let allowed = args.get(2).and_then(|v| v.as_bool()).unwrap_or(false);
        if name == "scene" {
            // Whole-scene access: only a scene-holding VM can confer it, and
            // the effective flag is re-derived per op, so this takes effect
            // for the target's whole subtree immediately.
            if allowed && !self.shared.effective_scene(self.vm) {
                return vm_error("vm.setPermission: caller lacks scene access to grant it");
            }
            if let Some(m) = self.shared.meta.borrow_mut().get_mut(&target) {
                m.local_scene = allowed;
            }
            return Value::Bool(true);
        }
        let Some(cap) = Capability::from_str(name) else {
            return vm_error(&format!("vm.setPermission: unknown permission '{name}'"));
        };
        let machine = self.shared.machine_of(target).unwrap_or_default();
        // Effective sets (target ∧ ancestors) are recomputed and pushed for
        // the target's whole subtree inside the registry.
        json!(vm_api::set_local_capability(&machine, cap, allowed))
    }

    fn spawn(&self, args: &[Value]) -> Value {
        let Some(source) = args.first().and_then(|v| v.as_str()) else {
            return vm_error("vm.spawn: expected [source, options]");
        };
        let opts = args.get(1).cloned().unwrap_or(Value::Null);
        let get = |k: &str| opts.get(k).cloned().unwrap_or(Value::Null);

        let want_scene = get("scene").as_bool().unwrap_or(false);
        let caller_scene = self.shared.effective_scene(self.vm);
        if want_scene && !caller_scene {
            return vm_error("vm.spawn: caller lacks scene access to confer it");
        }

        // The assigned node: every VM lives inside a node sandbox. Accept a
        // raw handle or the prelude's {"ref": id} object shape.
        let node = match &get("node") {
            Value::Number(n) => n.as_i64().unwrap_or(0),
            v => v.get("ref").and_then(|r| r.as_i64()).unwrap_or(0),
        };
        if node == 0 {
            return vm_error("vm.spawn: a sandbox node must be assigned (options.node)");
        }
        // The handle arrives in the parent's local id space — namespace it the
        // same way sanitize_op does for the parent's own engine ops, so the
        // containment check and the child's sandbox stamp match the
        // controller's handle map.
        let node = encode_handle(self.vm, node);
        // Containment: the assigned node must lie inside the parent's own
        // sandbox — verified by the engine bridge, which knows the real tree.
        let mut chk = json!({ "chk": node });
        let caller_sbx = self.shared.sandbox_of(self.vm);
        if caller_sbx != 0 {
            chk["__sbx"] = json!(caller_sbx);
        }
        match self.shared.forward("godot.op", &[chk]) {
            Some(Value::Bool(true)) => {}
            Some(other) if other.as_bool() == Some(true) => {}
            _ => {
                return vm_error(
                    "vm.spawn: assigned node is not inside the parent's sandbox",
                )
            }
        }

        let label = get("label").as_str().unwrap_or("child").to_string();
        let meter = ResourceMeter::new(
            get("maxHostCalls").as_u64().filter(|n| *n > 0),
            get("maxBytesMoved").as_u64().filter(|n| *n > 0),
        );

        // The child's front-end: the parent's language unless overridden.
        let parent_lang = self
            .shared
            .meta
            .borrow()
            .get(&self.vm)
            .map(|m| m.lang)
            .unwrap_or(GuestLang::Dart);
        let lang = match get("lang").as_str() {
            Some(name) => GuestLang::from_name(name, parent_lang),
            None => parent_lang,
        };

        let vm_id = self.shared.next_vm.get();
        self.shared.next_vm.set(vm_id + 1);
        let machine = format!("{}-c{}", self.shared.base, vm_id);
        let program = compose_for(lang, source);
        let mut rt = match compile_guest(machine.clone(), &program, lang, meter) {
            Ok(rt) => rt,
            Err(e) => return vm_error(&format!("vm.spawn: child failed to compile: {e}")),
        };
        let child_env = HookEnv { shared: self.shared.clone(), vm: vm_id };
        rt.set_host_hook(Box::new(move |name, args| child_env.handle(name, args)));

        // Hierarchy: adopt (pushes the inherited effective capability set),
        // then apply the parent's explicit grants/denials and limits.
        let parent_machine = self.shared.machine_of(self.vm).unwrap_or_default();
        if !vm_api::adopt_vm(&parent_machine, &machine) {
            vm_api::destroy_vm(machine.clone());
            return vm_error("vm.spawn: hierarchy adoption failed");
        }
        if let Some(perms) = get("permissions").as_object() {
            for (k, v) in perms {
                if let (Some(cap), Some(allowed)) = (Capability::from_str(k), v.as_bool()) {
                    vm_api::set_local_capability(&machine, cap, allowed);
                }
            }
        }
        if let Some(limits) = parse_limits(&get("limits")) {
            vm_api::set_limits(&machine, limits);
        }

        {
            let mut meta = self.shared.meta.borrow_mut();
            meta.insert(
                vm_id,
                VmMeta {
                    machine_id: machine.clone(),
                    label: label.clone(),
                    lang,
                    parent: Some(self.vm),
                    children: Vec::new(),
                    node_handle: node,
                    local_scene: want_scene,
                    paused: false,
                    dead: false,
                    trap_notified: false,
                    log_cursor: 0,
                },
            );
            if let Some(p) = meta.get_mut(&self.vm) {
                p.children.push(vm_id);
            }
        }
        self.shared.by_machine.borrow_mut().insert(machine, vm_id);
        self.shared.order.borrow_mut().push(vm_id);
        self.shared.pending_boot.borrow_mut().push((vm_id, rt));
        self.shared.log(format!("vm {} spawned vm {} ('{}')", self.vm, vm_id, label));
        json!(vm_id)
    }
}

/// The multi-VM manager one `ElpianVM` Godot node hosts: the root runtime plus
/// every VM the tree has spawned, the shared engine bridge, and the settle
/// loop that applies deferred cross-VM work.
pub struct VmManager {
    shared: Rc<Shared>,
    rts: HashMap<u64, GuestRuntime>,
}

impl VmManager {
    /// Create a manager whose root VM runs `user_source` (with the godot.dart
    /// prelude composed ahead unless `prepend` is false). The root VM holds
    /// whole-scene access and every capability; `max_host_calls` /
    /// `max_bytes_moved` bound its resource meter (0 = unbounded).
    pub fn new_root(
        base_machine: String,
        user_source: &str,
        prepend: bool,
        max_host_calls: u64,
        max_bytes_moved: u64,
    ) -> Result<Self, String> {
        Self::new_root_lang(
            base_machine,
            user_source,
            GuestLang::Dart,
            prepend,
            max_host_calls,
            max_bytes_moved,
        )
    }

    /// [`new_root`](Self::new_root) with an explicit guest language: the root
    /// VM runs `user_source` compiled by that language's front-end, with the
    /// matching prelude (`godot.dart` / `godot.js`) composed ahead unless
    /// `prepend` is false. Children spawned by the tree inherit the language.
    pub fn new_root_lang(
        base_machine: String,
        user_source: &str,
        lang: GuestLang,
        prepend: bool,
        max_host_calls: u64,
        max_bytes_moved: u64,
    ) -> Result<Self, String> {
        let program = if prepend {
            compose_for(lang, user_source)
        } else {
            user_source.to_string()
        };
        let meter = ResourceMeter::new(
            (max_host_calls > 0).then_some(max_host_calls),
            (max_bytes_moved > 0).then_some(max_bytes_moved),
        );
        let mut rt = compile_guest(base_machine.clone(), &program, lang, meter)
            .map_err(|e| format!("compile failed: {e}"))?;

        let shared = Rc::new(Shared {
            bridge: RefCell::new(None),
            meta: RefCell::new(HashMap::new()),
            by_machine: RefCell::new(HashMap::new()),
            order: RefCell::new(vec![ROOT_VM]),
            pending_boot: RefCell::new(Vec::new()),
            commands: RefCell::new(VecDeque::new()),
            host_log: RefCell::new(Vec::new()),
            next_vm: Cell::new(ROOT_VM + 1),
            base: base_machine.clone(),
        });
        shared.meta.borrow_mut().insert(
            ROOT_VM,
            VmMeta {
                machine_id: base_machine.clone(),
                label: "root".to_string(),
                lang,
                parent: None,
                children: Vec::new(),
                node_handle: 0,
                local_scene: true,
                paused: false,
                dead: false,
                trap_notified: false,
                log_cursor: 0,
            },
        );
        shared.by_machine.borrow_mut().insert(base_machine, ROOT_VM);
        let env = HookEnv { shared: shared.clone(), vm: ROOT_VM };
        rt.set_host_hook(Box::new(move |name, args| env.handle(name, args)));

        let mut rts = HashMap::new();
        rts.insert(ROOT_VM, rt);
        Ok(VmManager { shared, rts })
    }

    /// Install the engine bridge servicing forwarded `godot.*` calls.
    pub fn set_bridge(&mut self, bridge: Option<BridgeFn>) {
        *self.shared.bridge.borrow_mut() = bridge;
    }

    /// Run the root VM's `main()` (real-time drain), then settle.
    pub fn run_root(&mut self) -> Result<(), String> {
        let result = self
            .rts
            .get_mut(&ROOT_VM)
            .ok_or_else(|| "root vm is gone".to_string())?
            .run_realtime()
            .map(|_| ())
            .map_err(|e| format!("run failed: {e:?}"));
        self.settle();
        result
    }

    /// Deliver a host-side invocation. `__godotDispatch` routes a namespaced
    /// callback to its owning VM; `__godotEvent` broadcasts an engine
    /// lifecycle event to every live VM; anything else goes to the root VM.
    pub fn invoke(&mut self, fn_name: &str, arg: Value) {
        match fn_name {
            "__godotDispatch" => {
                let global = arg.get(0).and_then(|v| v.as_i64()).unwrap_or(0);
                let cb_args = arg.get(1).cloned().unwrap_or(Value::Null);
                let (vm, local) = decode_cb(global);
                if self.deliverable(vm) {
                    if let Some(rt) = self.rts.get_mut(&vm) {
                        rt.deliver_event("__godotDispatch", json!([local, cb_args]));
                    }
                }
            }
            "__godotEvent" => {
                let order = self.shared.order.borrow().clone();
                for vm in order {
                    if self.deliverable(vm) {
                        if let Some(rt) = self.rts.get_mut(&vm) {
                            rt.deliver_event("__godotEvent", arg.clone());
                        }
                    }
                }
            }
            other => {
                if let Some(rt) = self.rts.get_mut(&ROOT_VM) {
                    rt.deliver_event(other, arg);
                }
            }
        }
        self.settle();
    }

    /// Advance every live VM's event loop by the engine frame delta, then
    /// settle (which also runs the aggregate-budget sweep).
    pub fn pump(&mut self, delta_ms: u64) -> Result<(), String> {
        let order = self.shared.order.borrow().clone();
        let mut first_err = None;
        for vm in order {
            if self.deliverable(vm) {
                if let Some(rt) = self.rts.get_mut(&vm) {
                    if let Err(e) = rt.pump_frame(delta_ms) {
                        let msg = format!("vm {vm} pump failed: {e:?}");
                        self.shared.log(msg.clone());
                        first_err.get_or_insert(msg);
                    }
                }
            }
        }
        self.settle();
        match first_err {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }

    /// Whether events may be delivered to a VM right now.
    fn deliverable(&self, vm: u64) -> bool {
        self.shared
            .meta
            .borrow()
            .get(&vm)
            .map(|m| !m.paused && !m.dead)
            .unwrap_or(false)
            && self.rts.contains_key(&vm)
    }

    /// Apply all deferred multi-VM work until quiescent: boot children spawned
    /// this turn, sweep aggregate budgets and traps, and drain the command
    /// queue (removals, notifications, messages, resume-drives). Bounded so a
    /// pathological spawn/notify loop cannot wedge the frame.
    pub fn settle(&mut self) {
        for _round in 0..256 {
            let mut progressed = false;

            // 1. Boot children spawned during the last turn(s).
            let boots: Vec<(u64, GuestRuntime)> =
                self.shared.pending_boot.borrow_mut().drain(..).collect();
            for (vm, rt) in boots {
                progressed = true;
                self.rts.insert(vm, rt);
                let boot = self.rts.get_mut(&vm).expect("just inserted").run_realtime();
                match boot {
                    Ok(_) => {
                        if let Some(rt) = self.rts.get_mut(&vm) {
                            rt.deliver_event("__godotEvent", json!(["_ready", Value::Null]));
                        }
                    }
                    Err(e) => {
                        self.shared.log(format!("vm {vm} boot failed: {e:?}"));
                        self.shared.commands.borrow_mut().push_back(Command::Remove {
                            vm,
                            reason: format!("boot failed: {e:?}"),
                        });
                    }
                }
            }

            // 2. Aggregate-budget sweep (rule 2 of the tree).
            for (machine, axis, _destroyed) in vm_api::enforce_tree_budgets() {
                progressed = true;
                let vm = self.shared.by_machine.borrow().get(&machine).copied();
                if let Some(vm) = vm {
                    self.shared.log(format!(
                        "vm {vm} subtree exceeded its {axis} budget — branch terminated"
                    ));
                    self.remove_subtree(vm, &format!("subtree {axis} budget exceeded"));
                }
            }

            // 3. Trap detection: a VM stopped by its own governor (e.g. a hung
            //    child cut off by its per-turn instruction cap). The parent is
            //    notified once and decides; the VM stays queryable until then.
            let trapped: Vec<(u64, String)> = {
                let meta = self.shared.meta.borrow();
                meta.iter()
                    .filter(|(_, m)| !m.dead && !m.trap_notified)
                    .filter_map(|(vm, m)| {
                        vm_api::trap_reason(&m.machine_id).map(|r| (*vm, r))
                    })
                    .collect()
            };
            for (vm, reason) in trapped {
                progressed = true;
                let parent = {
                    let mut meta = self.shared.meta.borrow_mut();
                    if let Some(m) = meta.get_mut(&vm) {
                        m.trap_notified = true;
                        m.dead = true;
                    }
                    meta.get(&vm).and_then(|m| m.parent)
                };
                self.shared.log(format!("vm {vm} trapped: {reason}"));
                if let Some(parent) = parent {
                    self.shared.commands.borrow_mut().push_back(Command::Notify {
                        target: parent,
                        payload: json!(["trapped", vm, reason]),
                    });
                }
            }

            // 4. Drain deferred commands (one at a time — handling a command
            //    may enqueue more).
            loop {
                let cmd = self.shared.commands.borrow_mut().pop_front();
                let Some(cmd) = cmd else { break };
                progressed = true;
                match cmd {
                    Command::Remove { vm, reason } => self.remove_subtree(vm, &reason),
                    Command::Notify { target, payload } => {
                        if self.deliverable(target) {
                            if let Some(rt) = self.rts.get_mut(&target) {
                                rt.deliver_event("__vmNotify", payload);
                            }
                        }
                    }
                    Command::Message { target, payload } => {
                        if self.deliverable(target) {
                            if let Some(rt) = self.rts.get_mut(&target) {
                                rt.deliver_event("__vmMessage", payload);
                            }
                        }
                    }
                    Command::ResumeDrive { vm } => {
                        if self.deliverable(vm) {
                            let Some(machine) = self.shared.machine_of(vm) else { continue };
                            match vm_api::run_state(&machine) {
                                // Parked mid-turn: drive the continuation on.
                                Some(vm_api::RunState::Paused) => {
                                    if let Some(rt) = self.rts.get_mut(&vm) {
                                        rt.resume_paused();
                                    }
                                }
                                // Was idle when paused: just clear the stale
                                // flag so its next turn is not suspended.
                                Some(vm_api::RunState::PauseRequested) => {
                                    vm_api::clear_pause(&machine);
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }

            if !progressed {
                break;
            }
        }
    }

    /// Tear a subtree down: drain its logs, drop its runtimes, destroy the
    /// registry entries, mark the metas dead, and notify the parent of the
    /// removed root (rule 1 of the tree).
    fn remove_subtree(&mut self, vm: u64, reason: &str) {
        let subtree = self.shared.subtree(vm);
        for id in &subtree {
            self.drain_vm_log(*id);
            self.rts.remove(id);
        }
        if let Some(machine) = self.shared.machine_of(vm) {
            vm_api::destroy_vm_tree(&machine);
        }
        let parent = {
            let mut meta = self.shared.meta.borrow_mut();
            for id in &subtree {
                if let Some(m) = meta.get_mut(id) {
                    m.dead = true;
                }
            }
            meta.get(&vm).and_then(|m| m.parent)
        };
        self.shared.log(format!("vm {vm} removed ({reason}; {} vm(s) total)", subtree.len()));
        if let Some(parent) = parent {
            self.shared.commands.borrow_mut().push_back(Command::Notify {
                target: parent,
                payload: json!(["terminated", vm, reason]),
            });
        }
    }

    /// Move a VM's fresh guest log lines into the host log (prefixed with the
    /// VM identity for every non-root VM).
    fn drain_vm_log(&mut self, vm: u64) {
        let Some(rt) = self.rts.get(&vm) else { return };
        let (cursor, label) = {
            let meta = self.shared.meta.borrow();
            match meta.get(&vm) {
                Some(m) => (m.log_cursor, m.label.clone()),
                None => return,
            }
        };
        let log = rt.log();
        if cursor >= log.len() {
            return;
        }
        let mut lines = Vec::new();
        for line in &log[cursor..] {
            if vm == ROOT_VM {
                lines.push(line.clone());
            } else {
                lines.push(format!("[vm{vm}:{label}] {line}"));
            }
        }
        if let Some(m) = self.shared.meta.borrow_mut().get_mut(&vm) {
            m.log_cursor = log.len();
        }
        self.shared.host_log.borrow_mut().extend(lines);
    }

    /// All fresh log lines (every VM, in creation order, plus manager
    /// diagnostics), draining the buffers.
    pub fn take_log(&mut self) -> Vec<String> {
        let order = self.shared.order.borrow().clone();
        for vm in order {
            self.drain_vm_log(vm);
        }
        std::mem::take(&mut *self.shared.host_log.borrow_mut())
    }

    /// A JSON snapshot of the whole VM tree (id, label, state, usage,
    /// children…), for host-side dashboards and debugging.
    pub fn stats(&self) -> Value {
        self.stats_of(ROOT_VM)
    }

    fn stats_of(&self, vm: u64) -> Value {
        let (label, machine, paused, dead, children) = {
            let meta = self.shared.meta.borrow();
            match meta.get(&vm) {
                Some(m) => (
                    m.label.clone(),
                    m.machine_id.clone(),
                    m.paused,
                    m.dead,
                    m.children.clone(),
                ),
                None => return Value::Null,
            }
        };
        json!({
            "id": vm,
            "label": label,
            "state": vm_api::run_state(&machine).map(|s| s.as_str()).unwrap_or("destroyed"),
            "paused": paused,
            "alive": !dead,
            "usage": vm_api::usage(&machine).map(|u| usage_json(&u)).unwrap_or(Value::Null),
            "usageTree": vm_api::subtree_usage(&machine)
                .map(|u| usage_json(&u))
                .unwrap_or(Value::Null),
            "children": children.iter().map(|c| self.stats_of(*c)).collect::<Vec<_>>(),
        })
    }

    /// Direct access to a VM's runtime (tests / embedders).
    pub fn runtime_mut(&mut self, vm: u64) -> Option<&mut GuestRuntime> {
        self.rts.get_mut(&vm)
    }

    /// Whether a VM is currently alive (booted, not removed).
    pub fn vm_alive(&self, vm: u64) -> bool {
        self.rts.contains_key(&vm)
            && self.shared.meta.borrow().get(&vm).map(|m| !m.dead).unwrap_or(false)
    }

    /// The registry machine id of a VM.
    pub fn machine_of(&self, vm: u64) -> Option<String> {
        self.shared.machine_of(vm)
    }

    /// Ids of every VM ever created, in creation order.
    pub fn vm_ids(&self) -> Vec<u64> {
        self.shared.order.borrow().clone()
    }
}

impl Drop for VmManager {
    fn drop(&mut self) {
        // Rule 1 at host teardown: the whole tree dies with the manager.
        if let Some(machine) = self.shared.machine_of(ROOT_VM) {
            vm_api::destroy_vm_tree(&machine);
        }
        // Belt and braces for VMs that never made it into the tree.
        for (_, m) in self.shared.meta.borrow().iter() {
            vm_api::destroy_vm(m.machine_id.clone());
        }
    }
}
