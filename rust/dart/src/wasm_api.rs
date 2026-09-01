//! Minimal C-ABI entry points so the VM can run **in a browser** as a
//! `wasm32-unknown-unknown` module — no `wasm-bindgen` required.
//!
//! Protocol (all UTF-8 bytes in the module's linear memory):
//! 1. JS calls [`elpian_alloc`] to reserve `len` bytes and writes the Dart
//!    source there.
//! 2. JS calls [`elpian_run`], which compiles + runs the program (with a fixed
//!    clock for determinism), captures the scene the guest submitted via
//!    `dart:ui/FlutterView.render`, stores the JSON result, and returns its
//!    length.
//! 3. JS reads [`elpian_result_ptr`]`..+len` from memory to get the scene JSON.
//!
//! This is the seam a browser page (or the real engine embedder) renders from.

use std::sync::Mutex;

use crate::binding::{PointerEvent, PointerPhase};
use crate::{DartCapabilitySet, DartRuntime, ResourceMeter};

static RESULT: Mutex<Vec<u8>> = Mutex::new(Vec::new());

/// A persistent runtime for the interactive loop (init once, then pointer +
/// frame repeatedly).
static LIVE: Mutex<Option<DartRuntime>> = Mutex::new(None);

/// Reserve `len` bytes in wasm memory and return a pointer the host writes to.
#[no_mangle]
pub extern "C" fn elpian_alloc(len: usize) -> *mut u8 {
    let mut buf: Vec<u8> = Vec::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Free a buffer previously returned by [`elpian_alloc`].
///
/// # Safety
/// `ptr`/`len` must come from a prior [`elpian_alloc`] call.
#[no_mangle]
pub unsafe extern "C" fn elpian_free(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len));
}

/// Compile + run the Dart source at `ptr..+len`, capture the submitted scene,
/// store its JSON, and return the JSON byte length. On error, stores an
/// `{"error": "..."}` object instead.
///
/// # Safety
/// `ptr`/`len` must describe valid UTF-8 bytes in memory.
#[no_mangle]
pub unsafe extern "C" fn elpian_run(ptr: *const u8, len: usize) -> usize {
    let src = std::slice::from_raw_parts(ptr, len);
    let src = std::str::from_utf8(src).unwrap_or("");
    let json = run_to_scene_json(src);
    let bytes = json.into_bytes();
    let n = bytes.len();
    *RESULT.lock().unwrap() = bytes;
    n
}

/// Pointer to the result bytes stored by the last [`elpian_run`].
#[no_mangle]
pub extern "C" fn elpian_result_ptr() -> *const u8 {
    RESULT.lock().unwrap().as_ptr()
}

// ---- interactive loop: init once, then pointer/frame repeatedly ------------

/// Compile + run a Dart program once (defining its handlers) and keep the
/// runtime live for interaction. Returns 0 on success, 1 on failure.
///
/// # Safety
/// `ptr`/`len` must describe valid UTF-8 bytes in memory.
#[no_mangle]
pub unsafe extern "C" fn elpian_init(ptr: *const u8, len: usize) -> i32 {
    let src = std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).unwrap_or("");
    let id = format!("live-{}", next_id());
    match DartRuntime::from_dart(id, src, DartCapabilitySet::full(), ResourceMeter::unbounded()) {
        Ok(rt) => {
            let mut rt = rt.with_fixed_clock(0);
            let _ = rt.run();
            *LIVE.lock().unwrap() = Some(rt);
            0
        }
        Err(_) => 1,
    }
}

/// Initialize the live runtime from a **Flutter-style widget app** (the
/// [`crate::widgets`] framework prelude is prepended). Same lifecycle as
/// [`elpian_init`]: `elpian_pointer` delivers taps, `elpian_frame` renders.
/// Returns 0 on success, 1 on a compile error.
#[no_mangle]
pub unsafe extern "C" fn elpian_init_widgets(ptr: *const u8, len: usize) -> i32 {
    let src = std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).unwrap_or("");
    let id = format!("live-{}", next_id());
    match DartRuntime::from_widget_app(id, src, DartCapabilitySet::full(), ResourceMeter::unbounded()) {
        Ok(rt) => {
            let mut rt = rt.with_fixed_clock(0);
            let _ = rt.run();
            *LIVE.lock().unwrap() = Some(rt);
            0
        }
        Err(_) => 1,
    }
}

/// Initialize the live runtime from an app authored against the full
/// **`flutter.dart`** library (`import 'flutter.dart';`). The library
/// ([`crate::widgets::FLUTTER_LIB`]) is concatenated ahead of the app. Same
/// lifecycle as [`elpian_init`]. Returns 0 on success, 1 on a compile error.
#[no_mangle]
pub unsafe extern "C" fn elpian_init_flutter(ptr: *const u8, len: usize) -> i32 {
    let src = std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).unwrap_or("");
    let id = format!("live-{}", next_id());
    match DartRuntime::from_flutter_app(id, src, DartCapabilitySet::full(), ResourceMeter::unbounded()) {
        Ok(rt) => {
            let mut rt = rt.with_fixed_clock(0);
            let _ = rt.run();
            *LIVE.lock().unwrap() = Some(rt);
            0
        }
        Err(_) => 1,
    }
}

/// Deliver a pointer event to the live runtime's `onPointerEvent` handler.
#[no_mangle]
pub extern "C" fn elpian_pointer(x: f64, y: f64, down: i32) {
    if let Some(rt) = LIVE.lock().unwrap().as_mut() {
        let phase = if down == 1 { PointerPhase::Down } else { PointerPhase::Up };
        rt.dispatch_pointer(PointerEvent { pointer: 1, phase, x, y });
    }
}

/// Render one frame from the live runtime and store its scene JSON; returns the
/// JSON byte length (read via [`elpian_result_ptr`]).
#[no_mangle]
pub extern "C" fn elpian_frame() -> usize {
    let json = if let Some(rt) = LIVE.lock().unwrap().as_mut() {
        let scene = rt.render_frame(0).or_else(|| rt.last_scene());
        match scene {
            Some(s) => s.to_string(),
            None => "{\"error\":\"no frame\"}".to_string(),
        }
    } else {
        "{\"error\":\"not initialized\"}".to_string()
    };
    let bytes = json.into_bytes();
    let n = bytes.len();
    *RESULT.lock().unwrap() = bytes;
    n
}

fn run_to_scene_json(src: &str) -> String {
    // Each browser run needs a fresh VM id so the global registry doesn't collide.
    let id = format!("web-{}", next_id());
    let rt = DartRuntime::from_dart(
        id,
        src,
        DartCapabilitySet::full(),
        ResourceMeter::unbounded(),
    );
    let mut rt = match rt {
        Ok(rt) => rt.with_fixed_clock(0),
        Err(e) => return format!("{{\"error\":\"compile: {e:?}\"}}"),
    };
    if rt.run().is_err() {
        return "{\"error\":\"runtime\"}".to_string();
    }
    match rt.last_scene() {
        Some(scene) => scene.to_string(),
        None => "{\"error\":\"no scene submitted (call dart:ui/FlutterView.render)\"}".to_string(),
    }
}

fn next_id() -> u64 {
    static COUNTER: Mutex<u64> = Mutex::new(0);
    let mut c = COUNTER.lock().unwrap();
    *c += 1;
    *c
}
