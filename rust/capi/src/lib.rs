//! # elpian-godot-capi — the C ABI the Godot GDExtension embeds
//!
//! The C++ side of the bridge (`victor/bridge/extension/`) cannot link Rust
//! directly, so this crate flattens the multi-VM [`manager::VmManager`] into a
//! small, panic-safe C surface (`elpian_godot_*`), mirrored by the
//! `extension/src/elpian_capi.h` header:
//!
//! ```text
//!  Godot (C++)                          this crate                 Elpian VMs
//!  ─────────────                        ───────────                ──────────
//!  ElpianVM node ── elpian_godot_new ─▶ VmManager::new_root ─────▶ root VM
//!               ── elpian_godot_set_host ─▶ engine bridge  (godot.* calls out)
//!               ── elpian_godot_run ────▶ run_root()       (main() + settle)
//!               ── elpian_godot_invoke ─▶ invoke()   (events/signals routed
//!                                                     to the owning VM)
//!               ── elpian_godot_pump ───▶ pump(dt)   (all VMs, budgets, settle)
//! ```
//!
//! One node now hosts a **tree of VMs**: the root program can spawn child VMs
//! (`askHost("vm.spawn", …)`) that share the same Godot scene, each sandboxed
//! to an assigned node subtree, with hierarchical lifecycle / resource /
//! permission control (see [`manager`]). The **host callback** stays the
//! single engine seam: every forwarded `askHost("godot.…")` arrives at the
//! registered [`ElpianGodotHostFn`] as `(api_name, args_json)` — already
//! sanitized and stamped with the calling VM's sandbox — and the C++
//! `GodotController` interprets the op reflectively against ClassDB.
//!
//! Threading contract: a manager and its callback belong to ONE thread
//! (Godot's main thread). The `Send` asserted in a few places is satisfied by
//! construction — the embedder never migrates the manager across threads —
//! exactly like every GDExtension that touches the scene tree.

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};

pub mod manager;

pub use manager::{BridgeFn, GuestLang, VmManager, ROOT_VM};

/// The `godot.dart` guest prelude, compiled ahead of the user program so the
/// `GD`/`GObj` reflective surface, the `VMs` orchestration facade and the
/// marshaling vocabulary are in scope.
pub const GODOT_PRELUDE: &str = include_str!("../../prelude/godot.dart");

/// The `godot.js` guest prelude — the JavaScript twin of `godot.dart`. Same
/// wire protocol, same `GD`/`GObj`/`VMs` surface, expressed in the Elpian-JS
/// subset the `js2elpian` front-end compiles.
pub const GODOT_PRELUDE_JS: &str = include_str!("../../prelude/godot.js");

/// The Victor UI kit (`ui.js`) — a full widget toolkit in JavaScript built on
/// Godot `Control` nodes over the bridge. Composed ahead of a JS guest when
/// its source imports it (`import 'ui.js';`).
pub const GODOT_UI_KIT_JS: &str = include_str!("../../prelude/ui.js");

/// Victor networking (`net.js`) — HTTP (Godot `HTTPRequest` + a cookie jar),
/// WebSocket (`WebSocketPeer` pumped on a guest timer) and a Socket.IO v4
/// client, all in the Elpian-JS subset. Composed ahead of a JS guest when its
/// source imports it (`import 'net.js';`); it depends only on `godot.js`.
pub const GODOT_NET_JS: &str = include_str!("../../prelude/net.js");

/// Caspar protocol client (`caspar.js`) — the Caspar-node signed binary action
/// protocol over a `StreamPeerTCP` (framing, dev login, RSA request signing
/// via Godot `Crypto`, creature signalling with correlation-id result routing)
/// plus `CaspiNet`, the CaspiGames service-discovery layer. Composed ahead of
/// a JS guest when its source imports it (`import 'caspar.js';`); it depends
/// only on `godot.js`.
pub const GODOT_CASPAR_JS: &str = include_str!("../../prelude/caspar.js");

/// The Flutter UI bridge (`flutter.js`) — the `FL` facade that drives a real
/// `libflutter` engine embedded in the GDExtension over the `flutter.op` seam
/// (declarative widget-tree ops → a fixed AOT interpreter app). Composed ahead
/// of a JS guest when its source imports it (`import 'flutter.js';`); it depends
/// only on `godot.js` (it reuses that prelude's callback registry so widget
/// events route back through the same namespaced-dispatch path).
pub const GODOT_FLUTTER_JS: &str = include_str!("../../prelude/flutter.js");

/// VReact (`react.js`) — a React-compatible runtime (element factory, the full
/// hook surface, and a keyed reconciler that mutates retained Godot nodes)
/// whose host config targets the VUI kit. Composed ahead of a JS guest when its
/// source imports it (`import 'react.js';`); because it builds on VUI, importing
/// it implies the UI kit even if `ui.js` is not imported explicitly. This is
/// what a compiled Next.js-on-Victor program (see `templates/victor-nextjs/`)
/// runs on.
pub const GODOT_REACT_JS: &str = include_str!("../../prelude/react.js");

/// The React Native bridge (`reactnative.js`) — the `RN` facade that drives a
/// **real React Native / Expo widget tree** (2D) plus embedded Godot `Scene3D`
/// worlds (3D) over the `rn.op`/`rn.batch` seam. It is the twin of `ui.js`, but
/// its host is React Native instead of Godot `Control` nodes, so a Victor app
/// becomes a first-class RN view tree on mobile, desktop and web while keeping
/// every 3D feature of Godot as an embedded surface. Composed ahead of a JS
/// guest when its source imports it (`import 'reactnative.js';`); it depends on
/// `godot.js` (it reuses that prelude's callback registry and marshaling so
/// widget events route through the same namespaced-dispatch path, and so the
/// contents of a `Scene3D` drive Godot with the ordinary `GD`/`G3` surface).
pub const GODOT_REACTNATIVE_JS: &str = include_str!("../../prelude/reactnative.js");

/// Service a guest host call: `(user, api_name, args_json)` → reply JSON.
/// Return NULL (or leave unregistered) to decline — the guest then sees `null`.
/// The returned buffer is released via the paired [`ElpianGodotHostFreeFn`].
pub type ElpianGodotHostFn = Option<
    extern "C" fn(user: *mut c_void, api_name: *const c_char, args_json: *const c_char) -> *mut c_char,
>;

/// Release a buffer previously returned by the host callback (same allocator).
pub type ElpianGodotHostFreeFn = Option<extern "C" fn(user: *mut c_void, s: *mut c_char)>;

/// Opaque runtime handle across the C boundary — the whole VM tree.
pub struct ElpianGodotRuntime {
    mgr: VmManager,
}

/// The registered C callback bundle, captured by the Rust engine bridge.
/// Carrying the raw `user` pointer across the `Send` bound is sound under the
/// crate's single-thread embedding contract (see module docs).
struct HostBridge {
    call: extern "C" fn(*mut c_void, *const c_char, *const c_char) -> *mut c_char,
    free: ElpianGodotHostFreeFn,
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
        let reply = unsafe { CStr::from_ptr(reply_ptr) }.to_string_lossy().into_owned();
        if let Some(free) = self.free {
            free(self.user, reply_ptr);
        }
        serde_json::from_str(&reply).ok()
    }
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("").unwrap());
}

fn set_error(msg: &str) {
    let c = CString::new(msg.replace('\0', " ")).unwrap_or_default();
    LAST_ERROR.with(|e| *e.borrow_mut() = c);
}

static NEXT_MACHINE: AtomicU64 = AtomicU64::new(1);

/// Compose the final guest program: the `godot.dart` prelude, then the user
/// source, with `import …;` directives stripped from both (the front-end has
/// no module system; the prelude *is* the import).
pub fn compose_godot_program(user_source: &str) -> String {
    let strip = |src: &str| -> String {
        src.lines()
            .map(|l| if l.trim_start().starts_with("import ") { "" } else { l })
            .collect::<Vec<_>>()
            .join("\n")
    };
    format!("{}\n\n{}", strip(GODOT_PRELUDE), strip(user_source))
}

/// Compose the final **JavaScript** guest program: the `godot.js` prelude —
/// plus the Victor UI kit (`ui.js`) and the VReact runtime (`react.js`) when
/// the user source imports them — then the user source, with `import …;`
/// directives stripped from all parts (the front-end has no module system; the
/// prelude *is* the import). VReact depends on VUI, so an `import 'react.js';`
/// pulls in the UI kit as well, in the required order godot.js → ui.js →
/// react.js → program.
pub fn compose_godot_program_js(user_source: &str) -> String {
    let strip = |src: &str| -> String {
        src.lines()
            .map(|l| if l.trim_start().starts_with("import ") { "" } else { l })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let imports = |needle: &str| -> bool {
        user_source
            .lines()
            .any(|l| l.trim_start().starts_with("import ") && l.contains(needle))
    };
    let wants_react = imports("react.js");
    // react.js is built on VUI, so it implies the UI kit.
    let wants_ui_kit = wants_react || imports("ui.js");
    let wants_net = imports("net.js");
    let wants_caspar = imports("caspar.js");
    let wants_flutter = imports("flutter.js");
    // reactnative.js is the React Native host's UI kit; it depends on godot.js
    // (marshaling + callback registry + the GD/G3 surface a Scene3D drives).
    let wants_reactnative = imports("reactnative.js");

    let mut parts: Vec<String> = vec![strip(GODOT_PRELUDE_JS)];
    if wants_net {
        // net.js depends only on godot.js; compose it before the UI layers so
        // widgets and components can reach the network from construction time.
        parts.push(strip(GODOT_NET_JS));
    }
    if wants_caspar {
        // caspar.js depends only on godot.js; compose it before the UI layers
        // so app scaffolding can open node connections from construction time.
        parts.push(strip(GODOT_CASPAR_JS));
    }
    if wants_flutter {
        // flutter.js depends only on godot.js (it reuses the callback registry
        // and marshaling); compose it before the UI layers so components can
        // mount Flutter surfaces from construction time.
        parts.push(strip(GODOT_FLUTTER_JS));
    }
    if wants_ui_kit {
        parts.push(strip(GODOT_UI_KIT_JS));
    }
    if wants_react {
        parts.push(strip(GODOT_REACT_JS));
    }
    if wants_reactnative {
        // Depends only on godot.js (already first); compose after the optional
        // UI layers so an app may import both and reach every facade.
        parts.push(strip(GODOT_REACTNATIVE_JS));
    }
    parts.push(strip(user_source));
    parts.join("\n\n")
}

fn c_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Create a VM tree whose root runs `guest_source`. `prepend_prelude != 0`
/// composes the `godot.dart` prelude ahead of the program (what the ElpianVM
/// node does). `max_host_calls` / `max_bytes_moved` bound the root's resource
/// meter (0 = unbounded). Returns NULL on a compile/limit error — read
/// `elpian_godot_last_error()`.
#[no_mangle]
pub extern "C" fn elpian_godot_new(
    guest_source: *const c_char,
    prepend_prelude: c_int,
    max_host_calls: u64,
    max_bytes_moved: u64,
) -> *mut ElpianGodotRuntime {
    new_runtime(guest_source, GuestLang::Dart, prepend_prelude, max_host_calls, max_bytes_moved)
}

/// [`elpian_godot_new`] with an explicit guest language: `language` is
/// `"js"`/`"javascript"` for a JavaScript root program (the `godot.js`
/// prelude — plus the `ui.js` UI kit when the program imports it — is
/// composed ahead), anything else (including NULL) means Dart. Children the
/// tree spawns inherit the root's language unless their spawn options say
/// otherwise.
#[no_mangle]
pub extern "C" fn elpian_godot_new_lang(
    guest_source: *const c_char,
    language: *const c_char,
    prepend_prelude: c_int,
    max_host_calls: u64,
    max_bytes_moved: u64,
) -> *mut ElpianGodotRuntime {
    let lang = match c_str(language) {
        Some(name) if name.eq_ignore_ascii_case("js") || name.eq_ignore_ascii_case("javascript") => {
            GuestLang::Js
        }
        _ => GuestLang::Dart,
    };
    new_runtime(guest_source, lang, prepend_prelude, max_host_calls, max_bytes_moved)
}

fn new_runtime(
    guest_source: *const c_char,
    lang: GuestLang,
    prepend_prelude: c_int,
    max_host_calls: u64,
    max_bytes_moved: u64,
) -> *mut ElpianGodotRuntime {
    let result = catch_unwind(|| {
        let source = match c_str(guest_source) {
            Some(s) => s,
            None => {
                set_error("guest_source is null or not UTF-8");
                return std::ptr::null_mut();
            }
        };
        let machine = format!("godot-vm-{}", NEXT_MACHINE.fetch_add(1, Ordering::Relaxed));
        match VmManager::new_root_lang(
            machine,
            source,
            lang,
            prepend_prelude != 0,
            max_host_calls,
            max_bytes_moved,
        ) {
            Ok(mgr) => Box::into_raw(Box::new(ElpianGodotRuntime { mgr })),
            Err(e) => {
                set_error(&format!("compile failed: {e}"));
                std::ptr::null_mut()
            }
        }
    });
    result.unwrap_or_else(|_| {
        set_error("panic during elpian_godot_new");
        std::ptr::null_mut()
    })
}

/// Register the host callback servicing the tree's forwarded `godot.*` calls.
/// Passing a NULL `host_fn` uninstalls (guests see `null` replies).
#[no_mangle]
pub extern "C" fn elpian_godot_set_host(
    rt: *mut ElpianGodotRuntime,
    host_fn: ElpianGodotHostFn,
    free_fn: ElpianGodotHostFreeFn,
    user: *mut c_void,
) {
    let Some(rt) = (unsafe { rt.as_mut() }) else { return };
    match host_fn {
        Some(call) => {
            let bridge = HostBridge { call, free: free_fn, user };
            rt.mgr.set_bridge(Some(Box::new(move |name, args| bridge.dispatch(name, args))));
        }
        None => rt.mgr.set_bridge(None),
    }
}

/// Run the root guest's `main()`, drain its due event-loop work, and settle
/// the VM tree (boot any children it spawned). 0 = ok.
///
/// Uses the real-time drain: a `main()` that installs a `Timer.periodic` (or a
/// long one-shot `Timer`) returns promptly instead of spinning the event loop
/// forever — the timer fires later, once per frame, via [`elpian_godot_pump`].
#[no_mangle]
pub extern "C" fn elpian_godot_run(rt: *mut ElpianGodotRuntime) -> c_int {
    let Some(rt) = (unsafe { rt.as_mut() }) else { return 1 };
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.run_root())) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(&format!("run failed: {e}"));
            1
        }
        Err(_) => {
            set_error("panic during elpian_godot_run");
            1
        }
    }
}

/// Invoke a named guest function with one JSON argument (missing functions are
/// a no-op). This is how the C++ node delivers lifecycle events
/// (`__godotEvent(["_process", delta])` — broadcast to every live VM) and
/// bridged signal emissions (`__godotDispatch([cbId, [args…]])` — routed to
/// the VM owning the namespaced callback id). Other names are delivered to the
/// root VM. 0 = ok.
#[no_mangle]
pub extern "C" fn elpian_godot_invoke(
    rt: *mut ElpianGodotRuntime,
    fn_name: *const c_char,
    json_arg: *const c_char,
) -> c_int {
    let Some(rt) = (unsafe { rt.as_mut() }) else { return 1 };
    let Some(name) = c_str(fn_name) else {
        set_error("fn_name is null or not UTF-8");
        return 1;
    };
    let arg: Value = match c_str(json_arg) {
        Some(s) if !s.is_empty() => serde_json::from_str(s).unwrap_or(Value::Null),
        _ => Value::Null,
    };
    let name = name.to_string();
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.invoke(&name, arg))) {
        Ok(()) => 0,
        Err(_) => {
            set_error("panic during elpian_godot_invoke");
            1
        }
    }
}

/// Advance every live VM's guest clock by `delta_ms` real milliseconds (the
/// engine frame delta), fire whatever timers/microtasks became due, then run
/// the tree's aggregate-budget sweep. Call once per engine frame. 0 = ok.
#[no_mangle]
pub extern "C" fn elpian_godot_pump(rt: *mut ElpianGodotRuntime, delta_ms: u64) -> c_int {
    let Some(rt) = (unsafe { rt.as_mut() }) else { return 1 };
    match catch_unwind(AssertUnwindSafe(|| rt.mgr.pump(delta_ms))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(&format!("pump failed: {e}"));
            1
        }
        Err(_) => {
            set_error("panic during elpian_godot_pump");
            1
        }
    }
}

/// New guest `print`/log lines since the last call — from every VM in the
/// tree, child lines prefixed `[vm<id>:<label>]` — as a JSON string array.
/// Caller frees with [`elpian_godot_string_free`]. NULL when nothing new.
#[no_mangle]
pub extern "C" fn elpian_godot_take_log(rt: *mut ElpianGodotRuntime) -> *mut c_char {
    let Some(rt) = (unsafe { rt.as_mut() }) else { return std::ptr::null_mut() };
    let fresh = rt.mgr.take_log();
    if fresh.is_empty() {
        return std::ptr::null_mut();
    }
    CString::new(json!(fresh).to_string())
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// A JSON snapshot of the whole VM tree (ids, labels, states, per-VM and
/// aggregate usage) for host-side dashboards. Caller frees with
/// [`elpian_godot_string_free`].
#[no_mangle]
pub extern "C" fn elpian_godot_stats_json(rt: *mut ElpianGodotRuntime) -> *mut c_char {
    let Some(rt) = (unsafe { rt.as_ref() }) else { return std::ptr::null_mut() };
    let stats = catch_unwind(AssertUnwindSafe(|| rt.mgr.stats().to_string()))
        .unwrap_or_else(|_| "null".to_string());
    CString::new(stats).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// The last error message for this thread ("" when none). Borrowed — do not
/// free; valid until the next `elpian_godot_*` call on this thread.
#[no_mangle]
pub extern "C" fn elpian_godot_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ptr())
}

/// Free a string returned by this library.
#[no_mangle]
pub extern "C" fn elpian_godot_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

/// Destroy the VM tree (every VM in it — terminating the root terminates all
/// descendants by construction).
#[no_mangle]
pub extern "C" fn elpian_godot_free(rt: *mut ElpianGodotRuntime) {
    if !rt.is_null() {
        unsafe { drop(Box::from_raw(rt)) };
    }
}
