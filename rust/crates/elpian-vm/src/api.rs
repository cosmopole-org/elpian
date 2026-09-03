//! Embedding API for the Elpian VM.
//!
//! This is a renderer-agnostic port of the original Elpian `api/mod.rs`. It
//! keeps the VM registry and the pause/resume host-call protocol, but drops the
//! earlier renderer coupling. The set of host API names advertised here is the
//! contract the embedding `elpa-runtime` is expected to service.
//!
//! ## Host-call protocol
//!
//! 1. The embedder creates a VM ([`create_vm_from_ast`]) and starts it
//!    ([`execute_vm`] / [`execute_vm_func`]).
//! 2. When user code calls `askHost(apiName, payload)`, the VM pauses and the
//!    returned [`VmExecResult`] has `has_host_call == true`. `host_call_data` is
//!    a JSON string `{"machineId", "apiName", "payload"}`.
//! 3. The embedder performs the side effect (e.g. hands `payload` to the
//!    renderer when `apiName == "render"`), then resumes with
//!    [`continue_execution`], passing a typed JSON value back as the call's
//!    return value.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use once_cell::sync::Lazy;
use serde_json::{json, Value};

use crate::sdk::compiler;
use crate::sdk::vm::VM;

pub mod catalog;
pub mod govern;
pub mod supervisor;

/// A registered instance. The registry hands out clones of this handle, so a
/// turn can run against one VM while every other VM stays reachable.
type VmHandle = Arc<Mutex<VM>>;

/// What the registry stores per instance.
///
/// The control flag is kept *beside* the VM rather than only inside it, because
/// the calls that need it most — pause, terminate, read the run state — are the
/// ones a host makes while a turn is running and the VM's own lock is therefore
/// held. Reaching those through the lock would mean a runaway guest could not be
/// stopped until it stopped by itself.
#[derive(Clone)]
struct Entry {
    vm: VmHandle,
    control: crate::sdk::lifecycle::ExecControl,
    /// When the instance's current turn began, as milliseconds since
    /// [`PROCESS_START`]; `0` when it is between turns.
    ///
    /// Kept beside the VM, and atomic, for the same reason the control flag is:
    /// the supervisor needs to read it *while* a turn is running, which is
    /// precisely when the VM's own lock is held. A supervisor that could only
    /// observe idle instances could never catch the one overrunning.
    busy_since_ms: Arc<std::sync::atomic::AtomicU64>,
    /// When the instance's last turn ended, in the same units; `0` if it has
    /// never run one. The supervisor uses it to spot instances nothing has
    /// called for a while.
    last_turn_end_ms: Arc<std::sync::atomic::AtomicU64>,
}

/// Number of independent registry shards. Sixteen is enough that the map lock
/// is uncontended in practice while keeping the fixed cost of a full sweep
/// (`enforce_tree_budgets`, `all_ids`) trivial.
const SHARD_COUNT: usize = 16;

/// Thread-safe registry of live VMs keyed by `machineId`.
///
/// # Why this is not one map behind one lock
///
/// It used to be, and the lock was held for the *entire duration of a guest
/// turn* — `execute_vm` took it, ran the program, and only released it when the
/// guest hit a host call or finished. That made every guest turn in the process
/// mutually exclusive: a server could accept connections on many threads and
/// still execute exactly one instruction stream at a time, and one guest stuck
/// in a loop blocked every unrelated instance, including the calls a host would
/// use to terminate it.
///
/// # Lock discipline
///
/// Two locks are in play — a shard's map lock and an individual VM's lock — and
/// the rules that keep them deadlock-free are:
///
/// 1. **Never acquire a VM lock while holding a shard lock.** Every accessor
///    clones the `Arc` out of the shard and drops the shard guard *before*
///    touching the VM. [`Registry::get`] is the only way to obtain a handle and
///    it enforces this by construction.
/// 2. **Never hold two VM locks at once.** The tree operations below all work
///    from a list of ids collected up front, then lock one instance at a time.
/// 3. **Never hold a VM lock while taking the hierarchy lock** (and the
///    pre-existing converse: never hold the hierarchy lock across a registry
///    call). Ids are always collected first, then applied.
///
/// With those, no thread ever holds two locks in conflicting order, and a long
/// guest turn holds only its own instance's lock.
struct Registry {
    shards: Vec<Mutex<HashMap<String, Entry>>>,
}

impl Registry {
    fn new() -> Self {
        Registry {
            shards: (0..SHARD_COUNT).map(|_| Mutex::new(HashMap::new())).collect(),
        }
    }

    fn shard_of(&self, machine_id: &str) -> &Mutex<HashMap<String, Entry>> {
        // FNV-1a: stable across runs and platforms, and cheap on the short ids
        // machine names actually are. The registry only needs even spread, not
        // hash quality, so this does not want a `DefaultHasher` (whose output is
        // randomised per process and would scatter a debug session's ids
        // differently on every run).
        let mut hash: u64 = 0xcbf29ce484222325;
        for byte in machine_id.as_bytes() {
            hash ^= *byte as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        &self.shards[(hash as usize) % SHARD_COUNT]
    }

    /// Clone out the handle for `machine_id`, releasing the shard lock before
    /// returning. Rule 1 above holds by construction: the caller cannot be
    /// holding a shard guard by the time it locks the VM.
    fn get(&self, machine_id: &str) -> Option<VmHandle> {
        self.entry(machine_id).map(|e| e.vm)
    }

    fn entry(&self, machine_id: &str) -> Option<Entry> {
        lock_tolerant(self.shard_of(machine_id)).get(machine_id).cloned()
    }

    /// The instance's control flag, reachable with only the (briefly held)
    /// shard lock — never the VM lock. This is what makes host control work on
    /// an instance that is mid-turn.
    fn control(&self, machine_id: &str) -> Option<crate::sdk::lifecycle::ExecControl> {
        self.entry(machine_id).map(|e| e.control)
    }

    fn insert(&self, machine_id: String, vm: VM) {
        let entry = Entry {
            control: vm.control_handle(),
            vm: Arc::new(Mutex::new(vm)),
            busy_since_ms: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            last_turn_end_ms: Arc::new(std::sync::atomic::AtomicU64::new(0)),
        };
        lock_tolerant(self.shard_of(&machine_id)).insert(machine_id, entry);
    }

    /// Every registered id, with its entry. Used by the supervisor sweep; the
    /// shard locks are taken one at a time and released before anything is done
    /// with the results, so a sweep never blocks a running turn.
    fn snapshot(&self) -> Vec<(String, Entry)> {
        let mut out = Vec::new();
        for shard in &self.shards {
            for (id, entry) in lock_tolerant(shard).iter() {
                out.push((id.clone(), entry.clone()));
            }
        }
        out
    }

    /// Unregister an instance. A turn already running against it holds its own
    /// `Arc` and finishes undisturbed; the VM is dropped when that last handle
    /// goes away. This is why destroying a busy instance no longer has to wait
    /// for it — and why it is safe not to.
    fn remove(&self, machine_id: &str) -> Option<Entry> {
        lock_tolerant(self.shard_of(machine_id)).remove(machine_id)
    }

    fn contains(&self, machine_id: &str) -> bool {
        lock_tolerant(self.shard_of(machine_id)).contains_key(machine_id)
    }
}

static VMS: Lazy<Registry> = Lazy::new(Registry::new);

/// Monotonic base for the millisecond timestamps the supervisor compares.
/// `Instant` is not representable in an atomic, so turn starts are stored as a
/// millisecond offset from this.
static PROCESS_START: Lazy<std::time::Instant> = Lazy::new(std::time::Instant::now);

fn now_ms() -> u64 {
    PROCESS_START.elapsed().as_millis() as u64
}

/// Run `body` against a registered instance, or return `None` if it is unknown.
///
/// This is the single chokepoint for "lock one VM and do something with it", so
/// the discipline documented on [`Registry`] lives in one place instead of being
/// restated at fifty call sites.
fn with_vm<R>(machine_id: &str, body: impl FnOnce(&mut VM) -> R) -> Option<R> {
    let handle = VMS.get(machine_id)?;
    let mut vm = lock_tolerant(&handle);
    Some(body(&mut vm))
}

/// Like [`with_vm`], but marks the instance busy for the duration so the
/// supervisor can see how long the turn has been running and enforce a wall-
/// clock deadline against it.
///
/// Every entry into guest code goes through here. The marker is cleared on the
/// way out including on unwind, so a guest that traps does not leave itself
/// looking permanently overrunning.
fn with_vm_turn<R>(machine_id: &str, body: impl FnOnce(&mut VM) -> R) -> Option<R> {
    use std::sync::atomic::Ordering;
    let entry = VMS.entry(machine_id)?;
    let mut vm = lock_tolerant(&entry.vm);

    struct ClearOnExit {
        busy: Arc<std::sync::atomic::AtomicU64>,
        ended: Arc<std::sync::atomic::AtomicU64>,
    }
    impl Drop for ClearOnExit {
        fn drop(&mut self) {
            self.ended.store(now_ms().max(1), Ordering::Release);
            self.busy.store(0, Ordering::Release);
        }
    }
    // `max(1)` so a turn that begins in the first millisecond of the process is
    // still distinguishable from the `0` that means idle.
    entry.busy_since_ms.store(now_ms().max(1), Ordering::Release);
    let _clear = ClearOnExit {
        busy: entry.busy_since_ms.clone(),
        ended: entry.last_turn_end_ms.clone(),
    };

    Some(body(&mut vm))
}

/// Steer an instance through its control flag, taking **no** VM lock.
///
/// Every host control that must work on a running instance goes through here.
/// Using [`with_vm`] for these would reintroduce exactly the bug this design
/// exists to fix: the call would queue behind the turn it is trying to stop.
fn with_control<R>(
    machine_id: &str,
    body: impl FnOnce(&crate::sdk::lifecycle::ExecControl) -> R,
) -> Option<R> {
    VMS.control(machine_id).map(|c| body(&c))
}

/// Take a lock, recovering the guard if a previous holder panicked.
///
/// A guest program that traps can unwind through the executor while this lock is
/// held, which would poison it and make every later `create`/`execute`/`destroy`
/// fail for the life of the process — one bad program would take down a whole
/// server. A panicking guest is a guest fault, not a corruption of the registry
/// itself: the map still holds valid entries, and the offending VM can be
/// destroyed. So recover the guard and keep serving.
fn lock_tolerant<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Host APIs the embedding runtime services. The VM implements none of these — it
/// only forwards `askHost` calls. The GPU surface below is a *programmable VM around the wgpu
/// API*: there is **no** widget/DOM/canvas abstraction. The app's JS emits a
/// nested JSON tree of wgpu commands and submits it; the host maps that tree
/// to the wgpu API in real time.
///
/// The surface is intentionally tiny:
/// * `gpu.submit` — hand the renderer one frame's wgpu command tree
///   (`elpa_protocol::Frame`: resources + encoder commands). This is the central
///   call and the only one strictly required.
/// * `gpu.writeBuffer` / `gpu.writeTexture` — stream data into an existing GPU
///   resource without re-submitting the whole tree (queue writes).
/// * `gpu.readBuffer` — async GPU→CPU readback (resolves on a later continue).
/// * `gpu.surfaceInfo` — query the current surface size/format/scale factor.
/// * `gpu.define` / `gpu.undefine` — register / unregister a reusable drawing
///   definition (a named batch of commands, 2D and/or 3D) in the host's store,
///   so later `gpu.submit` frames can reference it abstractly by id instead of
///   re-emitting its command tree. Definitions may reference other definitions,
///   composing complex drawings from simpler ones and keeping payloads tiny.
/// * `vm.import` — import an external Elpian module (from a project asset or the
///   network) and run it so it can register definitions, expanding the engine's
///   drawing vocabulary at runtime.
/// * `host.send` / `host.request` — the embedder-defined custom messaging pipe.
///   `host.send(channel, message)` pushes a message out to the host
///   (fire-and-forget); `host.request(channel, message)` makes a synchronous
///   round-trip that returns the host's reply. The host -> guest direction is
///   delivered by [`deliver_host_message`].
/// * `log` — diagnostics.
///
/// This list is the documented host surface, and the source the Dart catalog
/// (`lib/src/vm/host_api_catalog.dart`) is generated from by the
/// `gen-host-api-catalog` binary — do not maintain a second copy by hand.
///
/// It is **not** an allowlist. An `askHost` name absent from here still
/// reaches the host: what gates a call is the capability set, which resolves
/// any name through [`Capability::for_api`] and needs no list to work. This
/// list used to be threaded into the executor as `_allowed_api` and never
/// read, which made it look like a gate it never was.
///
/// Keeping a name here is still worth doing: it is how the name gets a
/// capability in the generated catalog, and how a host knows the surface
/// exists at all.
pub fn all_host_apis() -> Vec<String> {
    // Every native host name the VM may emit must appear here, or a call to it
    // is not treated as a native `askHost` target.
    [
        "log",
        // Custom, bidirectional host messaging. The guest pushes messages out to
        // the embedding host (`host.send`, fire-and-forget) or makes a synchronous
        // round-trip that returns the host's reply (`host.request`). The matching
        // inbound direction (host -> guest) is delivered by the embedder via
        // [`deliver_host_message`], which invokes the guest's [`HOST_MESSAGE_HANDLER`]
        // function. Together these form the application-defined pipe an embedding
        // app (e.g. a Flutter host) uses to talk to the JS running on the VM.
        "host.send",
        "host.request",
        "gpu.submit",
        "gpu.writeBuffer",
        "gpu.writeTexture",
        "gpu.readBuffer",
        "gpu.surfaceInfo",
        "gpu.define",
        "gpu.undefine",
        "vm.import",
        // The multi-VM manager's control surface (serviced by
        // `elpian-runtime`, not by the VM itself). A guest holding `vm_manage`
        // spawns and steers children through these; they were called by every
        // prelude but listed nowhere, so they had no capability and did not
        // appear in the generated catalog.
        "vm.spawn",
        "vm.pause",
        "vm.resume",
        "vm.terminate",
        "vm.state",
        "vm.usage",
        "vm.usageTree",
        "vm.limits",
        "vm.setLimits",
        "vm.permissions",
        "vm.setPermission",
        "vm.list",
        "vm.info",
        "vm.send",
        "vm.grant",
        // The UI op seams. Every host surface speaks the same op vocabulary,
        // so they share one capability: a super app can deny a mini app the
        // drawing surface without touching anything else.
        "godot.op",
        "godot.batch",
        "flutter.op",
        "flutter.batch",
        // Capability-gated environmental interfaces. Each family is toggled by
        // the host via the instance's capability set; a disabled family makes
        // the corresponding `askHost` short-circuit to null (see executor).
        // A mini app calling its own server functions. `server.call` invokes an
        // action and returns its JSON result; `server.render` invokes a server
        // component and returns a UI payload. Both are resolved *within the
        // calling app* by the host — a guest cannot name another app's
        // function, because it never supplies the app identity: the host takes
        // that from the request it already routed.
        "server.call",
        "server.render",
        // Durable per-app state, and the secrets a server function may read.
        // `kv.*` is scoped to the app by the host, never by the guest.
        "kv.get",
        "kv.set",
        "kv.delete",
        "kv.list",
        // Values are declared by name in the app's manifest and injected by the
        // host; they are never packaged with the app and never returned to a
        // client.
        "secret.get",
        // A server action telling the host that a tag's cached renders are out
        // of date. Gated with `kv.*` because it is a statement *about* the
        // app's state, and an app that may change its state is the one that may
        // say the change happened.
        "cache.revalidate",
        "net.fetch",
        "net.open",
        "net.send",
        "net.recv",
        "net.close",
        "fs.read",
        "fs.write",
        "fs.append",
        "fs.delete",
        "fs.list",
        "fs.exists",
        "fs.stat",
        "fs.mkdir",
        "time.now",
        "time.monotonic",
        "random.next",
        "random.bytes",
        // Multi-threaded task offload: spawn guest compute onto a pool of worker
        // threads, each running its own Elpian executor (serviced by the host's
        // worker pool). Gated by the catch-all `Other` capability.
        "task.init",
        "task.spawn",
        "task.poll",
        "task.join",
        "task.relay",
        "task.stats",
        // Flutter Elpian engine compatibility. These names are intentionally
        // kept alongside Victor's newer gpu/host/environment surface so both
        // generations of guest programs can run on the same VM.
        "println",
        "stringify",
        "render",
        "updateApp",
        "env.get",
        "setTimeout",
        "setInterval",
        "clearTimeout",
        "clearInterval",
        "dom.getElementById",
        "dom.getElementsByClassName",
        "dom.getElementsByTagName",
        "dom.querySelector",
        "dom.querySelectorAll",
        "dom.createElement",
        "dom.removeElement",
        "dom.clear",
        "dom.setTextContent",
        "dom.setInnerHtml",
        "dom.setAttribute",
        "dom.getAttribute",
        "dom.removeAttribute",
        "dom.hasAttribute",
        "dom.setStyle",
        "dom.getStyle",
        "dom.setStyleObject",
        "dom.addClass",
        "dom.removeClass",
        "dom.hasClass",
        "dom.toggleClass",
        "dom.appendChild",
        "dom.insertBefore",
        "dom.removeChild",
        "dom.replaceChild",
        "dom.addEventListener",
        "dom.removeEventListener",
        "dom.dispatchEvent",
        "dom.toJson",
        "dom.getAllElements",
        "canvas.ctx.create",
        "canvas.ctx.dispose",
        "canvas.ctx.clear",
        "canvas.ctx.setSize",
        "canvas.ctx.addCommand",
        "canvas.ctx.addCommands",
        "canvas.addCommand",
        "canvas.addCommands",
        "canvas.clear",
        "canvas.getCommands",
        "canvas.beginPath",
        "canvas.closePath",
        "canvas.moveTo",
        "canvas.lineTo",
        "canvas.quadraticCurveTo",
        "canvas.bezierCurveTo",
        "canvas.arc",
        "canvas.arcTo",
        "canvas.ellipse",
        "canvas.rect",
        "canvas.roundRect",
        "canvas.circle",
        "canvas.fillRect",
        "canvas.strokeRect",
        "canvas.clearRect",
        "canvas.fillCircle",
        "canvas.strokeCircle",
        "canvas.fillPolygon",
        "canvas.strokePolygon",
        "canvas.fillText",
        "canvas.strokeText",
        "canvas.drawImage",
        "canvas.drawImageRect",
        "canvas.fill",
        "canvas.stroke",
        "canvas.clip",
        "canvas.save",
        "canvas.restore",
        "canvas.translate",
        "canvas.rotate",
        "canvas.scale",
        "canvas.transform",
        "canvas.setTransform",
        "canvas.resetTransform",
        "canvas.setFillStyle",
        "canvas.setStrokeStyle",
        "canvas.setLineWidth",
        "canvas.setLineCap",
        "canvas.setLineJoin",
        "canvas.setMiterLimit",
        "canvas.setLineDash",
        "canvas.setLineDashOffset",
        "canvas.setShadowBlur",
        "canvas.setShadowColor",
        "canvas.setShadowOffsetX",
        "canvas.setShadowOffsetY",
        "canvas.setGlobalAlpha",
        "canvas.setGlobalCompositeOperation",
        "canvas.setFont",
        "canvas.setTextAlign",
        "canvas.setTextBaseline",
        "canvas.createLinearGradient",
        "canvas.createRadialGradient",
        "canvas.addColorStop",
        "canvas.createPattern",
        "canvas.putImageData",
        "canvas.getImageData",
        "canvas.createImageData",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

/// Result of a VM execution step.
///
/// When the VM needs to call a host function it pauses and reports the request
/// here. The embedder services it and calls [`continue_execution`].
#[derive(Debug, Clone)]
pub struct VmExecResult {
    /// Whether the VM is paused waiting for a host-call response.
    pub has_host_call: bool,
    /// JSON of the host-call request: `{"machineId", "apiName", "payload"}`.
    pub host_call_data: String,
    /// Stringified result value (only meaningful when `has_host_call == false`).
    pub result_value: String,
}

impl VmExecResult {
    fn host_call(data: String) -> Self {
        VmExecResult {
            has_host_call: true,
            host_call_data: data,
            result_value: String::new(),
        }
    }
    fn done(result_value: &str) -> Self {
        VmExecResult {
            has_host_call: false,
            host_call_data: String::new(),
            result_value: result_value.to_string(),
        }
    }
}

/// After an execution step, surface a pending host call if one was queued.
fn check_host_call(vm: &mut VM, fallback_result: &str) -> VmExecResult {
    if let Some(data) = vm.sending_host_call_data.take() {
        VmExecResult::host_call(data)
    } else {
        VmExecResult::done(fallback_result)
    }
}

/// Initialize the VM subsystem. Call once at startup.
pub fn init_vm_system() {
    Lazy::force(&VMS);
}

/// Create a VM from an Elpian AST JSON string. Returns `false` on parse error.
pub fn create_vm_from_ast(machine_id: String, ast_json: String) -> bool {
    let ast_obj: Value = match serde_json::from_str(&ast_json) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let vm = VM::compile_and_create_of_ast(machine_id.clone(), ast_obj, 1);
    VMS.insert(machine_id, vm);
    true
}

/// Create a VM from **prebuilt bytecode** — the output of a source-language
/// compiler's `compile_*_to_bytecode` (e.g. `js2elpian` / `dart2elpian`) or of
/// [`compiler::compile_ast`], produced at build time and shipped as an asset.
/// This skips any front-end entirely at run time: the deployed app loads
/// bytecode straight into the executor (which decodes it once into its in-memory
/// operation structure). Always succeeds — bytecode is already validated by the
/// build-time compile.
pub fn create_vm_from_bytecode(machine_id: String, bytecode: Vec<u8>) -> bool {
    let vm = VM::compile_and_create_of_bytecode(machine_id.clone(), bytecode);
    VMS.insert(machine_id, vm);
    true
}

/// Create a VM directly from Elpian source code (uses the in-VM parser).
pub fn create_vm_from_code(machine_id: String, code: String) -> bool {
    let vm = VM::compile_and_create_of_code(machine_id.clone(), code, 1);
    VMS.insert(machine_id, vm);
    true
}

/// Validate that an AST JSON string compiles, without registering a VM.
pub fn validate_ast(ast_json: String) -> bool {
    let ast_obj: Value = match serde_json::from_str(&ast_json) {
        Ok(v) => v,
        Err(_) => return false,
    };
    compiler::compile_ast(ast_obj, 0);
    true
}

/// Drive one VM turn with guest faults contained.
///
/// The executor raises guest type errors with `panic!` (`{} - 1` unwinds with
/// "object and integer can not be subtracted"), which skips every piece of
/// end-of-turn bookkeeping on the way out. Two things went wrong as a result:
/// the instance stayed flagged `processing` and so bounced every later call
/// with `vm_busy`, and the unwind escaped to whatever was driving the VM — for
/// the C ABI, straight through an `extern "C"` frame.
///
/// Containing it here rather than at each embedder's edge means every embedder
/// — the C ABI, the wasm bindings, the Godot manager, a plain Rust host — gets
/// the same behaviour: the fault becomes an ordinary trap on that instance,
/// readable through [`trap_reason`], and the turn returns a normal result.
///
/// `AssertUnwindSafe` is sound for the same reason `lock_tolerant` is: the
/// registry holds plain data that stays coherent across an executor unwind, and
/// the faulting instance is left in a well-defined terminated state.
fn drive_turn(vm: &mut VM, turn: impl FnOnce(&mut VM) -> VmExecResult) -> VmExecResult {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| turn(vm))) {
        Ok(result) => result,
        Err(payload) => {
            let reason = if let Some(s) = payload.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "guest fault".to_string()
            };
            vm.record_fault(reason.clone());
            VmExecResult::done(&serde_json::Value::String(reason).to_string())
        }
    }
}

/// Execute a VM's top-level program.
pub fn execute_vm(machine_id: String) -> VmExecResult {
    with_vm_turn(&machine_id, |vm| {
        if vm.is_exec_processing() {
            return VmExecResult::done("\"vm_busy\"");
        }
        drive_turn(vm, |vm| {
            vm.run();
            check_host_call(vm, "\"done\"")
        })
    })
    .unwrap_or_else(|| VmExecResult::done("\"vm_not_found\""))
}

/// Execute a named function (no input). `cb_id` correlates async continuations.
pub fn execute_vm_func(machine_id: String, func_name: String, cb_id: i64) -> VmExecResult {
    with_vm_turn(&machine_id, |vm| {
        if vm.is_exec_processing() {
            return VmExecResult::done("\"vm_busy\"");
        }
        drive_turn(vm, |vm| {
            let res = vm.run_func_with_input(&func_name, None, cb_id);
            check_host_call(vm, &res.stringify())
        })
    })
    .unwrap_or_else(|| VmExecResult::done("\"vm_not_found\""))
}

/// Execute a named function with a JSON input payload (e.g. an event object).
pub fn execute_vm_func_with_input(
    machine_id: String,
    func_name: String,
    input_json: String,
    cb_id: i64,
) -> VmExecResult {
    with_vm_turn(&machine_id, |vm| {
        if vm.is_exec_processing() {
            return VmExecResult::done("\"vm_busy\"");
        }
        drive_turn(vm, |vm| {
            let res = vm.run_func_with_input(&func_name, Some(&input_json), cb_id);
            check_host_call(vm, &res.stringify())
        })
    })
    .unwrap_or_else(|| VmExecResult::done("\"vm_not_found\""))
}

/// Name of the guest function the host invokes to deliver an inbound custom
/// message (the host -> guest leg of the messaging pipe). An app that wants to
/// receive messages from the embedder defines `function onHostMessage(msg) {…}`;
/// it is optional — delivering to a VM that does not define it is a harmless
/// no-op, exactly like an undefined `onEvent`.
pub const HOST_MESSAGE_HANDLER: &str = "onHostMessage";

/// Deliver a custom message **into** the VM (host -> guest) by invoking the
/// guest's [`HOST_MESSAGE_HANDLER`] with `message_json` as its single argument.
///
/// This is the inbound half of the embedder-defined messaging pipe; the outbound
/// half is the guest calling the `host.send` / `host.request` host APIs, which
/// the embedder services in its host-call dispatch. `message_json` is a plain
/// JSON value (e.g. `{"channel":"nav","data":{…}}`) — the same shape `onEvent`
/// receives — and `cb_id` correlates any async continuation, like the other
/// `execute_vm_func*` entry points. Returns the usual [`VmExecResult`], so the
/// embedder pumps any host calls the handler makes (a re-render, a reply) through
/// the same continue/loop it uses for events.
pub fn deliver_host_message(machine_id: String, message_json: String, cb_id: i64) -> VmExecResult {
    execute_vm_func_with_input(
        machine_id,
        HOST_MESSAGE_HANDLER.to_string(),
        message_json,
        cb_id,
    )
}

/// Resume a VM after a host call, injecting the call's return value.
/// `input_json` is a typed value like `{"type":"string","data":{"value":"ok"}}`.
pub fn continue_execution(machine_id: String, input_json: String) -> VmExecResult {
    with_vm_turn(&machine_id, |vm| {
        drive_turn(vm, |vm| {
            // Report what the resumed turn actually produced.
            //
            // This used to discard `continue_run`'s value and hand back a fixed
            // `"done"`, which lost the return value of *every* guest function
            // that made a host call before returning — the driving loop in both
            // this crate and `ElpianVm.executeFunction` reads `resultValue`
            // after the last continue, and that is the value it was reading.
            // A UI event handler rarely returns anything, which is why it went
            // unnoticed; a server function's return value is the entire point
            // of calling it.
            let res = vm.continue_run(input_json);
            check_host_call(vm, &res.stringify())
        })
    })
    .unwrap_or_else(|| VmExecResult::done("\"vm_not_found\""))
}

/// Destroy a VM and free its resources.
pub fn destroy_vm(machine_id: String) -> bool {
    VMS.remove(&machine_id).is_some()
}

/// Whether a VM with this id is registered.
pub fn vm_exists(machine_id: String) -> bool {
    VMS.contains(&machine_id)
}

/// Whether the VM is currently mid-turn (its executor is on the call stack
/// servicing a host call). Event-loop drains must not deliver while this is
/// true: `execute_vm_func*` would bounce with `vm_busy` and the task would be
/// consumed unrun. An embedder callback that re-enters the runtime from inside
/// a host call (e.g. a Godot notification fired synchronously by an engine op)
/// checks this to defer its drain to the next regular pump instead.
pub fn vm_is_processing(machine_id: &str) -> bool {
    with_vm(machine_id, |vm| vm.is_exec_processing()).unwrap_or(false)
}

/// Compile source to bytecode and report its length (debug aid).
pub fn compile_code_to_info(code: String) -> String {
    let bytecode = compiler::compile_code(code);
    json!({ "bytecodeLength": bytecode.len() }).to_string()
}

// ----------------------------------------------------------------------------
// Instance control: resource limits, capabilities, and lifecycle.
//
// The host steers a registered VM entirely through these functions, keyed by
// `machine_id`. They are the embedder-facing contract for the unified governance
// and lifecycle system: cap an instance's CPU/heap/storage, switch its
// environmental interfaces on and off, and pause / resume / terminate it.
// ----------------------------------------------------------------------------

pub use crate::sdk::capabilities::{Capability, CapabilitySet};
pub use crate::sdk::lifecycle::RunState;
pub use crate::sdk::limits::{ResourceLimits, ResourceUsage};

/// Apply a resource-limit policy to a registered VM. Returns `false` if unknown.
pub fn set_limits(machine_id: &str, limits: ResourceLimits) -> bool {
    with_vm(machine_id, |vm| vm.set_limits(limits)).is_some()
}

/// Read a VM's live resource usage, if it exists.
pub fn usage(machine_id: &str) -> Option<ResourceUsage> {
    with_vm(machine_id, |vm| vm.usage())
}

/// Push an already-resolved *effective* capability set straight into a VM's
/// executor, with no hierarchy involvement.
///
/// Private on purpose. The tree's second invariant is that a VM's effective set
/// is the intersection of the local grants along its ancestor path, so the only
/// legitimate source of an effective set is [`VmHierarchy::effective_caps`].
/// The public setters below record a *local grant* and then recompute what each
/// affected VM may actually do; a caller reaching past them could hand a child
/// a capability its parent does not hold.
fn push_effective_caps(machine_id: &str, caps: CapabilitySet) -> bool {
    with_vm(machine_id, |vm| vm.set_capabilities(caps)).is_some()
}

/// Recompute the effective capability set for `machine_id` and every VM below
/// it, and push each into its executor. Call after any change to a local grant
/// on the path, so an on-the-fly revoke reaches the whole affected subtree at
/// once.
fn refresh_effective_caps(machine_id: &str) -> bool {
    let updates: Vec<(String, CapabilitySet)> = {
        let h = lock_tolerant(&HIERARCHY);
        h.subtree(machine_id)
            .into_iter()
            .map(|id| {
                let eff = h.effective_caps(&id);
                (id, eff)
            })
            .collect()
    };
    let mut any = false;
    for (id, eff) in updates {
        any |= push_effective_caps(&id, eff);
    }
    any
}

/// Grant or revoke one capability (network, storage, clock, …) for a VM.
///
/// This records a **local grant** and then recomputes the effective set for the
/// VM and its whole descendant subtree. Granting locally what an ancestor
/// denies is recorded but stays ineffective until the ancestor grants it too —
/// the tree's rule that a parent which lacks a permission can never confer it.
///
/// Before this went through the hierarchy it wrote straight into the executor,
/// so a host call after `adopt_vm` could hand a child a capability its parent
/// did not hold, silently defeating the intersection rule.
pub fn set_capability(machine_id: &str, cap: Capability, allowed: bool) -> bool {
    lock_tolerant(&HIERARCHY).set_local_capability(machine_id, cap, allowed);
    refresh_effective_caps(machine_id)
}

/// Replace a VM's whole local capability set (e.g. install a sandbox
/// `deny_all`), then recompute the effective set for it and its subtree.
///
/// Like [`set_capability`], this sets *local grants*: what the VM may actually
/// do is still the intersection with every ancestor.
pub fn set_capabilities(machine_id: &str, caps: CapabilitySet) -> bool {
    lock_tolerant(&HIERARCHY).set_local_caps(machine_id, caps);
    refresh_effective_caps(machine_id)
}

/// Whether a VM currently permits the given host API.
pub fn capability_allows(machine_id: &str, api_name: &str) -> bool {
    with_vm(machine_id, |vm| vm.capabilities().allows_api(api_name)).unwrap_or(false)
}

/// Request a pause: the VM suspends at its next interpreter step boundary, with
/// its full continuation preserved for [`resume_execution`].
pub fn pause_vm(machine_id: &str) -> bool {
    with_control(machine_id, |c| c.request_pause()).is_some()
}

/// Clear a VM's pause flag (requested or confirmed) without driving it —
/// for an instance that was idle between turns when the pause landed. A VM
/// parked mid-turn (state `Paused`) should instead be driven forward with
/// [`resume_execution`].
pub fn clear_pause(machine_id: &str) -> bool {
    with_control(machine_id, |c| c.resume()).is_some()
}

/// Resume a paused VM, continuing exactly where it suspended.
pub fn resume_execution(machine_id: String) -> VmExecResult {
    with_vm_turn(&machine_id, |vm| {
        drive_turn(vm, |vm| {
            let res = vm.resume();
            check_host_call(vm, &res.stringify())
        })
    })
    .unwrap_or_else(|| VmExecResult::done("\"vm_not_found\""))
}

/// Request termination: the VM unwinds at its next step boundary and becomes
/// inert. Further drive calls are no-ops.
pub fn terminate_vm(machine_id: &str) -> bool {
    let Some(entry) = VMS.entry(machine_id) else {
        return false;
    };
    // Set the flag first, unconditionally and without any lock: this is the
    // half that has to reach a guest currently spinning inside a turn.
    entry.control.request_terminate();

    // Then, *if* the instance is idle, finish the job — confirm the terminate
    // and drop its registers. `try_lock` is the test for idleness: a turn in
    // flight holds this lock. Deliberately not a blocking lock, because waiting
    // for the turn to end is precisely the behaviour that made terminate
    // useless against a runaway guest.
    if let Ok(vm) = entry.vm.try_lock() {
        vm.confirm_terminate_if_idle();
    }
    true
}

/// Current run state of a VM (running / paused / terminated / …).
pub fn run_state(machine_id: &str) -> Option<RunState> {
    with_control(machine_id, |c| c.state())
}

/// The fatal trap reason if a VM was stopped by a limit overrun or runtime
/// error, else `None`.
pub fn trap_reason(machine_id: &str) -> Option<String> {
    with_vm(machine_id, |vm| vm.trap_reason()).flatten()
}

/// Charge the storage governor on behalf of the host's fabricated filesystem.
/// Returns the limit-error message if the storage cap would be exceeded.
pub fn charge_storage(machine_id: &str, delta: i64) -> Result<(), String> {
    with_vm(machine_id, |vm| vm.charge_storage(delta))
        .unwrap_or_else(|| Err("vm_not_found".to_string()))
}

/// Read a VM's current resource-limit policy, if it exists.
pub fn limits(machine_id: &str) -> Option<ResourceLimits> {
    with_vm(machine_id, |vm| vm.limits())
}

// ----------------------------------------------------------------------------
// The VM tree: hierarchical instance management.
//
// A VM may instantiate other VMs; the registry tracks the resulting tree and
// enforces the three hierarchical rules (see `sdk::hierarchy`):
//   * lifecycle binding   — terminating a VM terminates its whole subtree;
//   * aggregate budgets   — a VM's usage is measured own + descendant subtree,
//                           and an aggregate overrun kills the whole subtree;
//   * permission AND      — a VM's effective capabilities are the intersection
//                           of the local grants along its ancestor path, and a
//                           change anywhere is pushed to the affected subtree.
//
// Lock discipline: the hierarchy mutex is never held across a call that takes
// the VMS mutex — ids are collected first, then applied per VM.
// ----------------------------------------------------------------------------

use crate::sdk::hierarchy::{accumulate_usage, aggregate_exceeds, VmHierarchy};

static HIERARCHY: Lazy<Mutex<VmHierarchy>> = Lazy::new(|| Mutex::new(VmHierarchy::new()));

// The hierarchy mutex is taken through `lock_tolerant` for the same reason the
// VM registry is: a guest panic that unwinds while it is held must not poison
// it for the life of the process. See `lock_tolerant` above.

/// Register `child` as a child of `parent` in the VM tree and push the
/// resulting effective capability set into the child's executor. Fails on
/// cycles or if the child already has a parent.
pub fn adopt_vm(parent_id: &str, child_id: &str) -> bool {
    {
        let mut h = lock_tolerant(&HIERARCHY);
        if !h.adopt(parent_id, child_id) {
            return false;
        }
    }
    // The child's local grants are unchanged; what changed is its ancestry, so
    // it and everything below it need their effective sets recomputed against
    // the new path.
    refresh_effective_caps(child_id);
    true
}

/// The parent of a VM in the tree, if it has one.
pub fn vm_parent(machine_id: &str) -> Option<String> {
    lock_tolerant(&HIERARCHY)
        .parent_of(machine_id)
        .map(|s| s.to_string())
}

/// The direct children of a VM.
pub fn vm_children(machine_id: &str) -> Vec<String> {
    lock_tolerant(&HIERARCHY).children_of(machine_id).to_vec()
}

/// The VM plus all its descendants, pre-order.
pub fn vm_subtree(machine_id: &str) -> Vec<String> {
    lock_tolerant(&HIERARCHY).subtree(machine_id)
}

/// Whether `ancestor` is `machine_id` itself or one of its ancestors.
pub fn vm_is_ancestor_or_self(ancestor: &str, machine_id: &str) -> bool {
    lock_tolerant(&HIERARCHY).is_ancestor_or_self(ancestor, machine_id)
}

/// The explicit spelling of [`set_capability`], for call sites that want to be
/// unambiguous that they are setting a *local grant* rather than an effective
/// set. Identical behaviour: both record the grant and recompute the effective
/// set (local ∧ ancestors) across the VM's whole descendant subtree.
pub fn set_local_capability(machine_id: &str, cap: Capability, allowed: bool) -> bool {
    set_capability(machine_id, cap, allowed)
}

/// A VM's locally granted capability set (allow-all when never restricted).
pub fn local_capabilities(machine_id: &str) -> CapabilitySet {
    lock_tolerant(&HIERARCHY).local_caps(machine_id)
}

/// A VM's effective capability set (local grants ∧ every ancestor's grants).
pub fn effective_capabilities(machine_id: &str) -> CapabilitySet {
    lock_tolerant(&HIERARCHY).effective_caps(machine_id)
}

/// Aggregate resource usage of a VM **and its whole descendant subtree** —
/// the figure a parent is accountable for. Additive budgets add; depth-like
/// gauges take the subtree max. `None` if the VM is unknown.
pub fn subtree_usage(machine_id: &str) -> Option<ResourceUsage> {
    // Rule 2: one instance locked at a time. The figure is therefore a
    // *sample* across the subtree rather than an instant of it — a sibling can
    // advance while a later one is being read. That is the right trade here:
    // the alternative is freezing every instance in the branch to read a
    // counter, and the budget check this feeds tolerates being a hair stale.
    let mut total = ResourceUsage::default();
    let mut found = false;
    for id in vm_subtree(machine_id) {
        if let Some(usage) = with_vm(&id, |vm| vm.usage()) {
            accumulate_usage(&mut total, &usage);
            found = true;
        }
    }
    found.then_some(total)
}

/// Request termination of a VM **and every descendant**: each executor unwinds
/// at its next step boundary (including mid-turn — a hung child parked inside
/// a loop observes the flag at its next interpreter step). Returns the ids the
/// terminate was applied to, pre-order. The tree edges are kept until
/// [`destroy_vm_tree`] so the embedder can still inspect the branch.
pub fn terminate_vm_tree(machine_id: &str) -> Vec<String> {
    let ids = vm_subtree(machine_id);
    for id in &ids {
        with_vm(id, |vm| vm.request_terminate());
    }
    ids
}

/// Request a pause of a VM and every descendant (each suspends at its next
/// step boundary, continuation preserved). Returns the affected ids.
pub fn pause_vm_tree(machine_id: &str) -> Vec<String> {
    let ids = vm_subtree(machine_id);
    for id in &ids {
        with_vm(id, |vm| vm.request_pause());
    }
    ids
}

/// Destroy a VM and its whole subtree: terminate flags set, registry entries
/// dropped, hierarchy edges removed. Returns the destroyed ids, pre-order.
pub fn destroy_vm_tree(machine_id: &str) -> Vec<String> {
    let ids = {
        let mut h = lock_tolerant(&HIERARCHY);
        h.remove_subtree(machine_id)
    };
    for id in &ids {
        // Unregister first, so nothing new can start a turn against the
        // instance, then flag the termination through the handle we just took
        // out. An instance already mid-turn observes the flag at its next
        // interpreter step and unwinds; it holds its own `Arc`, so it is not
        // freed from under itself and this call does not block on it.
        if let Some(entry) = VMS.remove(id) {
            entry.control.request_terminate();
        }
    }
    ids
}

/// Sweep the whole VM forest for **aggregate budget overruns**: for every VM
/// (top-down), compare its own limit policy against the aggregate usage of its
/// subtree; on an overrun, terminate and destroy that entire subtree. This is
/// the enforcement half of rule 2 — a child that hangs or bloats and is not
/// handled by its parent eventually costs the parent's whole branch.
///
/// Returns `(subtree_root, axis, destroyed_ids)` per violation. Call it
/// periodically (e.g. once per host frame).
pub fn enforce_tree_budgets() -> Vec<(String, String, Vec<String>)> {
    // Collect the candidate set without holding the hierarchy lock across the
    // per-VM registry reads.
    let candidates: Vec<String> = {
        let h = lock_tolerant(&HIERARCHY);
        let mut all = Vec::new();
        for root in h.roots() {
            all.extend(h.subtree(&root));
        }
        all
    };
    let mut violations = Vec::new();
    let mut dead: Vec<String> = Vec::new();
    for id in candidates {
        if dead.iter().any(|d| d == &id) {
            continue; // already inside a destroyed subtree
        }
        let Some(limits) = limits(&id) else { continue };
        let Some(aggregate) = subtree_usage(&id) else {
            continue;
        };
        if let Some(axis) = aggregate_exceeds(&limits, &aggregate) {
            let destroyed = destroy_vm_tree(&id);
            dead.extend(destroyed.iter().cloned());
            violations.push((id, axis.to_string(), destroyed));
        }
    }
    violations
}
