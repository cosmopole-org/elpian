//! Embedding API for the Elpian VM.
//!
//! This is a renderer-agnostic port of the original Elpian `api/mod.rs`. It
//! keeps the VM registry and the pause/resume host-call protocol, but drops the
//! old Bevy/Flutter coupling. The set of host API names advertised here is the
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
use std::sync::Mutex;

use once_cell::sync::Lazy;
use serde_json::{json, Value};

use crate::sdk::compiler;
use crate::sdk::vm::VM;

pub mod catalog;
#[cfg(not(target_arch = "wasm32"))]
pub mod ffi;
// The browser API, built on wasm-bindgen, and meaningful only for the
// wasm-pack target. `target_arch = "wasm32"` alone also matches
// wasm32-unknown-emscripten, which is how the Godot web GDExtension is built:
// that dragged wasm-bindgen into a link that can never use it.
#[cfg(all(target_arch = "wasm32", target_os = "unknown"))]
pub mod wasm;

/// Thread-safe registry of live VMs keyed by `machineId`.
static VMS: Lazy<Mutex<HashMap<String, VM>>> = Lazy::new(|| Mutex::new(HashMap::new()));

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

/// Host APIs the Elpa runtime services. The VM implements none of these — it
/// only forwards `askHost` calls. Elpa is a *programmable VM around the wgpu
/// API*: there is **no** widget/DOM/canvas abstraction. The app's JS emits a
/// nested JSON tree of wgpu commands and submits it; Elpa maps that tree to the
/// wgpu API in real time (see `PLAN.md`).
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
/// This list is the single source of truth for the host surface. The Dart
/// catalog (`lib/src/vm/host_api_catalog.dart`) is generated from it by the
/// `gen-host-api-catalog` binary — do not maintain a second copy by hand.
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
        // Capability-gated environmental interfaces. Each family is toggled by
        // the host via the instance's capability set; a disabled family makes
        // the corresponding `askHost` short-circuit to null (see executor).
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
    drop(lock_tolerant(&VMS));
}

/// Create a VM from an Elpian AST JSON string. Returns `false` on parse error.
pub fn create_vm_from_ast(machine_id: String, ast_json: String) -> bool {
    let ast_obj: Value = match serde_json::from_str(&ast_json) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let vm = VM::compile_and_create_of_ast(machine_id.clone(), ast_obj, 1, all_host_apis());
    lock_tolerant(&VMS).insert(machine_id, vm);
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
    let vm = VM::compile_and_create_of_bytecode(machine_id.clone(), bytecode, all_host_apis());
    lock_tolerant(&VMS).insert(machine_id, vm);
    true
}

/// Create a VM directly from Elpian source code (uses the in-VM parser).
pub fn create_vm_from_code(machine_id: String, code: String) -> bool {
    let vm = VM::compile_and_create_of_code(machine_id.clone(), code, 1, all_host_apis());
    lock_tolerant(&VMS).insert(machine_id, vm);
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
    let mut vms = lock_tolerant(&VMS);
    match vms.get_mut(&machine_id) {
        Some(vm) if vm.is_exec_processing() => VmExecResult::done("\"vm_busy\""),
        Some(vm) => drive_turn(vm, |vm| {
            vm.run();
            check_host_call(vm, "\"done\"")
        }),
        None => VmExecResult::done("\"vm_not_found\""),
    }
}

/// Execute a named function (no input). `cb_id` correlates async continuations.
pub fn execute_vm_func(machine_id: String, func_name: String, cb_id: i64) -> VmExecResult {
    let mut vms = lock_tolerant(&VMS);
    match vms.get_mut(&machine_id) {
        Some(vm) if vm.is_exec_processing() => VmExecResult::done("\"vm_busy\""),
        Some(vm) => drive_turn(vm, |vm| {
            let res = vm.run_func_with_input(&func_name, None, cb_id);
            check_host_call(vm, &res.stringify())
        }),
        None => VmExecResult::done("\"vm_not_found\""),
    }
}

/// Execute a named function with a JSON input payload (e.g. an event object).
pub fn execute_vm_func_with_input(
    machine_id: String,
    func_name: String,
    input_json: String,
    cb_id: i64,
) -> VmExecResult {
    let mut vms = lock_tolerant(&VMS);
    match vms.get_mut(&machine_id) {
        Some(vm) if vm.is_exec_processing() => VmExecResult::done("\"vm_busy\""),
        Some(vm) => drive_turn(vm, |vm| {
            let res = vm.run_func_with_input(&func_name, Some(&input_json), cb_id);
            check_host_call(vm, &res.stringify())
        }),
        None => VmExecResult::done("\"vm_not_found\""),
    }
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
    let mut vms = lock_tolerant(&VMS);
    match vms.get_mut(&machine_id) {
        Some(vm) => drive_turn(vm, |vm| {
            vm.continue_run(input_json);
            check_host_call(vm, "\"done\"")
        }),
        None => VmExecResult::done("\"vm_not_found\""),
    }
}

/// Destroy a VM and free its resources.
pub fn destroy_vm(machine_id: String) -> bool {
    lock_tolerant(&VMS).remove(&machine_id).is_some()
}

/// Whether a VM with this id is registered.
pub fn vm_exists(machine_id: String) -> bool {
    lock_tolerant(&VMS).contains_key(&machine_id)
}

/// Whether the VM is currently mid-turn (its executor is on the call stack
/// servicing a host call). Event-loop drains must not deliver while this is
/// true: `execute_vm_func*` would bounce with `vm_busy` and the task would be
/// consumed unrun. An embedder callback that re-enters the runtime from inside
/// a host call (e.g. a Godot notification fired synchronously by an engine op)
/// checks this to defer its drain to the next regular pump instead.
pub fn vm_is_processing(machine_id: &str) -> bool {
    lock_tolerant(&VMS)
        .get(machine_id)
        .map(|vm| vm.is_exec_processing())
        .unwrap_or(false)
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
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => {
            vm.set_limits(limits);
            true
        }
        None => false,
    }
}

/// Read a VM's live resource usage, if it exists.
pub fn usage(machine_id: &str) -> Option<ResourceUsage> {
    lock_tolerant(&VMS).get(machine_id).map(|vm| vm.usage())
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
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => {
            vm.set_capabilities(caps);
            true
        }
        None => false,
    }
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
    lock_tolerant(&VMS)
        .get(machine_id)
        .map(|vm| vm.capabilities().allows_api(api_name))
        .unwrap_or(false)
}

/// Request a pause: the VM suspends at its next interpreter step boundary, with
/// its full continuation preserved for [`resume_execution`].
pub fn pause_vm(machine_id: &str) -> bool {
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => {
            vm.request_pause();
            true
        }
        None => false,
    }
}

/// Clear a VM's pause flag (requested or confirmed) without driving it —
/// for an instance that was idle between turns when the pause landed. A VM
/// parked mid-turn (state `Paused`) should instead be driven forward with
/// [`resume_execution`].
pub fn clear_pause(machine_id: &str) -> bool {
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => {
            vm.clear_pause();
            true
        }
        None => false,
    }
}

/// Resume a paused VM, continuing exactly where it suspended.
pub fn resume_execution(machine_id: String) -> VmExecResult {
    let mut vms = lock_tolerant(&VMS);
    match vms.get_mut(&machine_id) {
        Some(vm) => {
            let res = vm.resume();
            check_host_call(vm, &res.stringify())
        }
        None => VmExecResult::done("\"vm_not_found\""),
    }
}

/// Request termination: the VM unwinds at its next step boundary and becomes
/// inert. Further drive calls are no-ops.
pub fn terminate_vm(machine_id: &str) -> bool {
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => {
            vm.request_terminate();
            true
        }
        None => false,
    }
}

/// Current run state of a VM (running / paused / terminated / …).
pub fn run_state(machine_id: &str) -> Option<RunState> {
    lock_tolerant(&VMS).get(machine_id).map(|vm| vm.run_state())
}

/// The fatal trap reason if a VM was stopped by a limit overrun or runtime
/// error, else `None`.
pub fn trap_reason(machine_id: &str) -> Option<String> {
    lock_tolerant(&VMS)
        .get(machine_id)
        .and_then(|vm| vm.trap_reason())
}

/// Charge the storage governor on behalf of the host's fabricated filesystem.
/// Returns the limit-error message if the storage cap would be exceeded.
pub fn charge_storage(machine_id: &str, delta: i64) -> Result<(), String> {
    let vms = lock_tolerant(&VMS);
    match vms.get(machine_id) {
        Some(vm) => vm.charge_storage(delta),
        None => Err("vm_not_found".to_string()),
    }
}

/// Read a VM's current resource-limit policy, if it exists.
pub fn limits(machine_id: &str) -> Option<ResourceLimits> {
    lock_tolerant(&VMS).get(machine_id).map(|vm| vm.limits())
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
    let ids = vm_subtree(machine_id);
    let vms = lock_tolerant(&VMS);
    let mut total = ResourceUsage::default();
    let mut found = false;
    for id in ids {
        if let Some(vm) = vms.get(&id) {
            accumulate_usage(&mut total, &vm.usage());
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
    let vms = lock_tolerant(&VMS);
    for id in &ids {
        if let Some(vm) = vms.get(id) {
            vm.request_terminate();
        }
    }
    ids
}

/// Request a pause of a VM and every descendant (each suspends at its next
/// step boundary, continuation preserved). Returns the affected ids.
pub fn pause_vm_tree(machine_id: &str) -> Vec<String> {
    let ids = vm_subtree(machine_id);
    let vms = lock_tolerant(&VMS);
    for id in &ids {
        if let Some(vm) = vms.get(id) {
            vm.request_pause();
        }
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
    let mut vms = lock_tolerant(&VMS);
    for id in &ids {
        if let Some(vm) = vms.get(id) {
            vm.request_terminate();
        }
        vms.remove(id);
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
