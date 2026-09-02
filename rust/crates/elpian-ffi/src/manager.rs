//! The multi-VM manager, over the C ABI, for a Flutter host.
//!
//! # What this adds
//!
//! Flutter could already create a VM, run it, govern it, and — through
//! `MiniAppHost.spawnChild` on the Dart side — nest mini apps by driving the
//! tree from the host. What it could not do was let a *guest* spawn one:
//! `askHost("vm.spawn", …)` from inside a mini app's own code needs the
//! manager, and the manager was locked inside the Godot crate.
//!
//! This module closes that. A Flutter host creates a manager, registers one
//! bridge callback for the `flutter.op` seam, and the guest's `VMs.spawn(…)`
//! works exactly as it does under Godot — with the same sandboxing, the same
//! inherited permissions, the same aggregate budgets.
//!
//! # Threading
//!
//! A manager and its bridge belong to one thread: Flutter's platform thread,
//! where the Dart FFI call lands. The manager is never migrated.

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};

use elpian_runtime::{GuestLang, HostSurface, VmManager};
use serde_json::{json, Value};

// ---------------------------------------------------------------------------
// The Flutter host surface
// ---------------------------------------------------------------------------

/// A Flutter widget tree as a host for a tree of VMs.
///
/// Deliberately thin. Flutter's widget tree has no node handles a guest can
/// address the way a Godot scene does — a mini app renders by submitting a
/// widget tree, not by mutating nodes — so containment is enforced by the
/// host's own per-mini-app isolation (`ElpianServices`, `MiniAppHost`) rather
/// than by walking a scene graph.
pub struct FlutterSurface {
    prelude: Option<String>,
}

impl FlutterSurface {
    /// A surface that composes `prelude` ahead of every guest program.
    pub fn with_prelude(prelude: Option<String>) -> Self {
        FlutterSurface { prelude }
    }
}

impl HostSurface for FlutterSurface {
    fn compose(&self, _lang: GuestLang, user_source: &str) -> String {
        match &self.prelude {
            Some(p) => format!("{p}\n\n{user_source}"),
            None => user_source.to_string(),
        }
    }

    fn op_prefix(&self) -> &str {
        "flutter"
    }

    fn dispatch_fn(&self) -> &str {
        "__flutterDispatch"
    }

    fn event_fn(&self) -> &str {
        "__flutterEvent"
    }

    /// Flutter has no addressable node tree for a guest to escape into, so
    /// there is nothing to walk: a mini app's reach is bounded by the host's
    /// own isolation, and every op is still stamped with the calling VM's
    /// sandbox id and namespaced to its callback space by the manager.
    ///
    /// This overrides the default explicitly rather than inheriting it, so the
    /// reasoning is recorded at the place a reader would look for it.
    fn verify_containment(
        &self,
        _bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        _node: i64,
        _sandbox: i64,
    ) -> bool {
        true
    }

    /// Handle grants are a scene-graph notion; on Flutter the host mediates
    /// what a child can reach, so there is nothing to hand over here.
    fn grant_handle(
        &self,
        _bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        _vm: u64,
        _handle: i64,
        _sandbox: i64,
    ) -> bool {
        false
    }
}

// ---------------------------------------------------------------------------
// The C ABI
// ---------------------------------------------------------------------------

/// Service a guest host call: `(user, api_name, args_json)` → reply JSON, or
/// NULL to decline (the guest then sees `null`). The returned buffer is
/// released through the paired free callback.
pub type ElpianHostFn = Option<
    extern "C" fn(
        user: *mut c_void,
        api_name: *const c_char,
        args_json: *const c_char,
    ) -> *mut c_char,
>;

/// Release a buffer the host callback returned (same allocator).
pub type ElpianHostFreeFn = Option<extern "C" fn(user: *mut c_void, s: *mut c_char)>;

/// Opaque handle across the C boundary: the whole VM tree.
pub struct ElpianManager {
    mgr: VmManager,
}

/// The registered callback bundle. Carrying the raw `user` pointer across the
/// `Send` bound is sound under this module's single-thread contract.
struct HostBridge {
    call: extern "C" fn(*mut c_void, *const c_char, *const c_char) -> *mut c_char,
    free: ElpianHostFreeFn,
    user: *mut c_void,
}
unsafe impl Send for HostBridge {}

impl HostBridge {
    fn dispatch(&self, api_name: &str, args: &[Value]) -> Option<Value> {
        let name = CString::new(api_name).ok()?;
        let args_json = CString::new(Value::Array(args.to_vec()).to_string()).ok()?;
        let reply_ptr = (self.call)(self.user, name.as_ptr(), args_json.as_ptr());
        if reply_ptr.is_null() {
            return None;
        }
        let reply = unsafe { CStr::from_ptr(reply_ptr) }
            .to_string_lossy()
            .into_owned();
        if let Some(free) = self.free {
            free(self.user, reply_ptr);
        }
        serde_json::from_str(&reply).ok()
    }
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

fn set_error(msg: &str) {
    let c = CString::new(msg.replace('\0', " ")).unwrap_or_default();
    LAST_ERROR.with(|e| *e.borrow_mut() = c);
}

unsafe fn c_str(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        CStr::from_ptr(p).to_str().ok().map(str::to_owned)
    }
}

/// Create a VM tree whose root runs `guest_source`.
///
/// `prelude` is composed ahead of the program when non-NULL. `max_host_calls` /
/// `max_bytes_moved` bound the root's resource meter (0 = unbounded). Returns
/// NULL on a compile error — read [`elpian_manager_last_error`].
///
/// # Safety
/// Every pointer is NULL or a NUL-terminated string valid for this call.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_new(
    machine_id: *const c_char,
    guest_source: *const c_char,
    language: *const c_char,
    prelude: *const c_char,
    max_host_calls: u64,
    max_bytes_moved: u64,
) -> *mut ElpianManager {
    let machine = c_str(machine_id).unwrap_or_else(|| "root".to_string());
    let Some(source) = c_str(guest_source) else {
        set_error("elpian_manager_new: guest_source is null or not UTF-8");
        return std::ptr::null_mut();
    };
    let lang = match c_str(language).as_deref() {
        Some(n) if n.eq_ignore_ascii_case("dart") => GuestLang::Dart,
        _ => GuestLang::Js,
    };
    let prelude = c_str(prelude);
    let prepend = prelude.is_some();

    let result = catch_unwind(AssertUnwindSafe(|| {
        VmManager::new_root_lang(
            Box::new(FlutterSurface::with_prelude(prelude)),
            machine,
            &source,
            lang,
            prepend,
            max_host_calls,
            max_bytes_moved,
        )
    }));
    match result {
        Ok(Ok(mgr)) => Box::into_raw(Box::new(ElpianManager { mgr })),
        Ok(Err(e)) => {
            set_error(&format!("compile failed: {e}"));
            std::ptr::null_mut()
        }
        Err(_) => {
            set_error("panic during elpian_manager_new");
            std::ptr::null_mut()
        }
    }
}

/// Register the callback servicing forwarded `flutter.*` ops and any host API
/// the manager does not handle itself. NULL uninstalls it.
///
/// # Safety
/// `rt` is NULL or a live manager; `user` outlives the bridge.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_set_host(
    rt: *mut ElpianManager,
    host_fn: ElpianHostFn,
    free_fn: ElpianHostFreeFn,
    user: *mut c_void,
) {
    let Some(rt) = rt.as_mut() else { return };
    match host_fn {
        Some(call) => {
            let bridge = HostBridge {
                call,
                free: free_fn,
                user,
            };
            rt.mgr.set_bridge(Some(Box::new(move |name, args| {
                bridge.dispatch(name, args)
            })));
        }
        None => rt.mgr.set_bridge(None),
    }
}

/// Run the root guest's entry point, drain its due event-loop work, and settle
/// the tree (boot any children it spawned). 0 = ok.
///
/// # Safety
/// `rt` is NULL or a live manager.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_run(rt: *mut ElpianManager) -> c_int {
    let Some(rt) = rt.as_mut() else { return 1 };
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.run_root())) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(&format!("run failed: {e}"));
            1
        }
        Err(_) => {
            set_error("panic during elpian_manager_run");
            1
        }
    }
}

/// Invoke a named guest function with one JSON argument. This is how a host
/// delivers events and routes callbacks back to the VM that registered them.
/// 0 = ok.
///
/// # Safety
/// `rt` is NULL or a live manager; the strings are NUL-terminated or NULL.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_invoke(
    rt: *mut ElpianManager,
    fn_name: *const c_char,
    json_arg: *const c_char,
) -> c_int {
    let Some(rt) = rt.as_mut() else { return 1 };
    let Some(name) = c_str(fn_name) else {
        set_error("elpian_manager_invoke: fn_name is null or not UTF-8");
        return 1;
    };
    let arg: Value = c_str(json_arg)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(Value::Null);
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.invoke(&name, arg))) {
        Ok(()) => 0,
        Err(_) => {
            set_error("panic during elpian_manager_invoke");
            1
        }
    }
}

/// Advance every VM in the tree by `delta_ms`: due timers, budget enforcement,
/// and settling newly spawned children. 0 = ok.
///
/// # Safety
/// `rt` is NULL or a live manager.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_pump(rt: *mut ElpianManager, delta_ms: u64) -> c_int {
    let Some(rt) = rt.as_mut() else { return 1 };
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.pump(delta_ms))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(&format!("pump failed: {e}"));
            1
        }
        Err(_) => {
            set_error("panic during elpian_manager_pump");
            1
        }
    }
}

/// A JSON snapshot of the whole tree — ids, labels, states, per-VM and
/// aggregate usage — for a host dashboard. Caller frees with
/// [`elpian_manager_string_free`].
///
/// # Safety
/// `rt` is NULL or a live manager.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_stats(rt: *mut ElpianManager) -> *mut c_char {
    let Some(rt) = rt.as_ref() else {
        return std::ptr::null_mut();
    };
    let stats = catch_unwind(AssertUnwindSafe(|| rt.mgr.stats().to_string()))
        .unwrap_or_else(|_| json!({ "error": "panic during stats" }).to_string());
    CString::new(stats)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// New guest log lines since the last call, from every VM in the tree, as a
/// JSON string array. NULL when there is nothing new. Caller frees with
/// [`elpian_manager_string_free`].
///
/// # Safety
/// `rt` is NULL or a live manager.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_take_log(rt: *mut ElpianManager) -> *mut c_char {
    let Some(rt) = rt.as_mut() else {
        return std::ptr::null_mut();
    };
    let fresh = rt.mgr.take_log();
    if fresh.is_empty() {
        return std::ptr::null_mut();
    }
    CString::new(json!(fresh).to_string())
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// The last error on this thread, or "". Borrowed — do not free.
#[no_mangle]
pub extern "C" fn elpian_manager_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ptr())
}

/// Free a string this module returned.
///
/// # Safety
/// `s` is NULL or a string this module returned and has not yet freed.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Destroy the tree — every VM in it, since terminating the root terminates
/// all descendants by construction.
///
/// # Safety
/// `rt` is NULL or a live manager this module returned, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn elpian_manager_free(rt: *mut ElpianManager) {
    if !rt.is_null() {
        drop(Box::from_raw(rt));
    }
}
