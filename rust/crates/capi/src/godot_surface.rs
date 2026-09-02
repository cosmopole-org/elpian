//! Godot's implementation of [`HostSurface`].
//!
//! Everything the multi-VM manager needs that is specific to a Godot scene.
//! It is deliberately small: the manager was written against a Godot scene and
//! turned out to depend on only five things, all of them here.

use elpian_runtime::{GuestLang, HostSurface};
use serde_json::{json, Value};

use crate::{compose_godot_program, compose_godot_program_js};

/// The Godot scene as a host for a tree of VMs.
pub struct GodotSurface;

impl HostSurface for GodotSurface {
    fn compose(&self, lang: GuestLang, user_source: &str) -> String {
        match lang {
            GuestLang::Dart => compose_godot_program(user_source),
            GuestLang::Js => compose_godot_program_js(user_source),
        }
    }

    fn op_prefix(&self) -> &str {
        "godot"
    }

    fn dispatch_fn(&self) -> &str {
        "__godotDispatch"
    }

    fn event_fn(&self) -> &str {
        "__godotEvent"
    }

    /// Ask the engine whether `node` is inside `sandbox`.
    ///
    /// Godot has a real scene tree, so this cannot be assumed: the C++ side
    /// walks it and answers. A `sandbox` of 0 is the unsandboxed root, which
    /// may assign any node.
    fn verify_containment(
        &self,
        bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        node: i64,
        sandbox: i64,
    ) -> bool {
        let mut chk = json!({ "chk": node });
        if sandbox != 0 {
            chk["__sbx"] = json!(sandbox);
        }
        matches!(bridge("godot.op", &[chk]), Some(v) if v.as_bool() == Some(true))
    }

    fn grant_handle(
        &self,
        bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        _vm: u64,
        handle: i64,
        sandbox: i64,
    ) -> bool {
        let mut op = json!({ "grant": handle, "sbx": sandbox });
        if sandbox != 0 {
            op["__sbx"] = json!(sandbox);
        }
        matches!(bridge("godot.op", &[op]), Some(v) if v.as_bool() == Some(true))
    }
}
