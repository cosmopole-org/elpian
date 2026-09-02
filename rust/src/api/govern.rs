//! The governance control plane in JSON form.
//!
//! The typed functions in [`crate::api`] — `set_limits`, `usage`,
//! `set_capability`, `pause_vm`, `subtree_usage`, `enforce_tree_budgets` and
//! the rest — were reachable only from Rust. The C ABI exported creation and
//! execution and nothing else, so a Flutter host embedding Elpian could not set
//! a budget, read a meter, revoke a permission or pause a mini app. Every
//! mechanism the framework governs mini apps with stopped at the Rust edge.
//!
//! This module is the crossing point. Each function takes and returns JSON so
//! one narrow C ABI (and one set of Dart bindings) covers the whole surface
//! without a struct per call. The shapes are stable and documented here because
//! they are a public contract, not an implementation detail.
//!
//! ## Shapes
//!
//! **Limits** — every field optional; a missing or null field means "no limit".
//! ```json
//! { "maxInstructions": 50000000, "maxInstructionsPerTurn": 5000000,
//!   "maxMemoryBytes": 67108864, "maxStorageBytes": 16777216,
//!   "maxCallDepth": 1024 }
//! ```
//!
//! **Usage** — all fields always present.
//! ```json
//! { "instructions": 1234, "instructionsThisTurn": 12, "memoryBytes": 4096,
//!   "peakMemoryBytes": 8192, "storageBytes": 0, "callDepth": 2,
//!   "peakCallDepth": 7 }
//! ```
//!
//! **Capabilities** — a map of capability name to whether it is permitted,
//! carrying every capability the VM knows so a host never has to guess the set.
//! ```json
//! { "logging": true, "network": false, "dom": true, … }
//! ```
//!
//! **Errors** — a function that cannot act reports it in band rather than
//! guessing a value: `{"error": "vm_not_found"}`.

use serde_json::{json, Map, Value};

use super::{Capability, CapabilitySet, ResourceLimits, ResourceUsage};

fn err(message: &str) -> Value {
    json!({ "error": message })
}

const NOT_FOUND: &str = "vm_not_found";

// ---- Conversions -----------------------------------------------------------

/// Read an optional byte/step budget. Absent, null, or a negative number all
/// mean "unbounded", so a host can clear one field without restating the rest.
fn budget(v: &Value, key: &str) -> Option<u64> {
    match v.get(key) {
        None | Some(Value::Null) => None,
        Some(n) => n.as_u64(),
    }
}

/// Parse a limits object. Unknown keys are ignored, so a newer host talking to
/// an older VM degrades rather than failing.
pub fn limits_from_json(v: &Value) -> ResourceLimits {
    ResourceLimits {
        max_instructions: budget(v, "maxInstructions"),
        max_instructions_per_turn: budget(v, "maxInstructionsPerTurn"),
        max_memory_bytes: budget(v, "maxMemoryBytes"),
        max_storage_bytes: budget(v, "maxStorageBytes"),
        max_call_depth: budget(v, "maxCallDepth"),
    }
}

pub fn limits_to_json(l: &ResourceLimits) -> Value {
    json!({
        "maxInstructions": l.max_instructions,
        "maxInstructionsPerTurn": l.max_instructions_per_turn,
        "maxMemoryBytes": l.max_memory_bytes,
        "maxStorageBytes": l.max_storage_bytes,
        "maxCallDepth": l.max_call_depth,
    })
}

pub fn usage_to_json(u: &ResourceUsage) -> Value {
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

pub fn capabilities_to_json(caps: &CapabilitySet) -> Value {
    let mut map = Map::new();
    for cap in Capability::all() {
        map.insert(cap.as_str().to_string(), Value::Bool(caps.is_allowed(cap)));
    }
    Value::Object(map)
}

// ---- Resource limits and meters --------------------------------------------

/// Apply a limits policy. `limits_json` is a limits object; returns
/// `{"ok": true}` or an error.
pub fn set_limits_json(machine_id: &str, limits_json: &str) -> Value {
    let Ok(parsed) = serde_json::from_str::<Value>(limits_json) else {
        return err("invalid_limits_json");
    };
    if super::set_limits(machine_id, limits_from_json(&parsed)) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

/// The VM's current limits policy.
pub fn limits_json(machine_id: &str) -> Value {
    match super::limits(machine_id) {
        Some(l) => limits_to_json(&l),
        None => err(NOT_FOUND),
    }
}

/// The VM's own live usage.
pub fn usage_json(machine_id: &str) -> Value {
    match super::usage(machine_id) {
        Some(u) => usage_to_json(&u),
        None => err(NOT_FOUND),
    }
}

/// The VM's usage **plus its whole descendant subtree** — the figure a parent
/// is accountable for, and the one a parent's own budget is checked against.
pub fn subtree_usage_json(machine_id: &str) -> Value {
    match super::subtree_usage(machine_id) {
        Some(u) => usage_to_json(&u),
        None => err(NOT_FOUND),
    }
}

/// Charge the storage governor on the host filesystem's behalf.
pub fn charge_storage_json(machine_id: &str, delta: i64) -> Value {
    match super::charge_storage(machine_id, delta) {
        Ok(()) => json!({ "ok": true }),
        Err(e) => err(&e),
    }
}

// ---- Capabilities ----------------------------------------------------------

/// Grant or revoke one capability. Records a *local* grant and recomputes the
/// effective set across the VM's descendant subtree, so a parent that lacks a
/// capability still cannot confer it on a child.
pub fn set_capability_json(machine_id: &str, capability: &str, allowed: bool) -> Value {
    let Some(cap) = Capability::from_str(capability) else {
        return err("unknown_capability");
    };
    if super::set_capability(machine_id, cap, allowed) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

/// Replace the VM's whole local capability set from a `{name: bool}` map.
/// Names absent from the map are left as they were.
pub fn set_capabilities_json(machine_id: &str, caps_json: &str) -> Value {
    let Ok(Value::Object(map)) = serde_json::from_str::<Value>(caps_json) else {
        return err("invalid_capabilities_json");
    };
    let mut caps = super::local_capabilities(machine_id);
    for (name, allowed) in map {
        let Some(cap) = Capability::from_str(&name) else {
            return err("unknown_capability");
        };
        let Some(allowed) = allowed.as_bool() else {
            return err("capability_value_must_be_bool");
        };
        caps.set(cap, allowed);
    }
    if super::set_capabilities(machine_id, caps) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

/// Deny everything, then grant only the named capabilities. The starting
/// posture for an untrusted mini app.
pub fn sandbox_capabilities_json(machine_id: &str, granted_json: &str) -> Value {
    let Ok(Value::Array(names)) = serde_json::from_str::<Value>(granted_json) else {
        return err("invalid_capability_list");
    };
    let mut caps = CapabilitySet::deny_all();
    for name in names {
        let Some(name) = name.as_str() else {
            return err("capability_names_must_be_strings");
        };
        let Some(cap) = Capability::from_str(name) else {
            return err("unknown_capability");
        };
        caps.grant(cap);
    }
    if super::set_capabilities(machine_id, caps) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

/// What the VM was granted directly, before intersection with its ancestors.
pub fn local_capabilities_json(machine_id: &str) -> Value {
    capabilities_to_json(&super::local_capabilities(machine_id))
}

/// What the VM may actually do: its local grants AND every ancestor's. This is
/// the set the executor enforces.
pub fn effective_capabilities_json(machine_id: &str) -> Value {
    capabilities_to_json(&super::effective_capabilities(machine_id))
}

/// Whether one host API is currently permitted for this VM.
pub fn capability_allows_json(machine_id: &str, api_name: &str) -> Value {
    json!({ "allowed": super::capability_allows(machine_id, api_name) })
}

// ---- Lifecycle -------------------------------------------------------------

/// Run state, trap reason and whether a turn is in flight, in one read — the
/// three things a host dashboard wants together.
pub fn state_json(machine_id: &str) -> Value {
    let Some(state) = super::run_state(machine_id) else {
        return err(NOT_FOUND);
    };
    json!({
        "state": state.as_str(),
        "trapReason": super::trap_reason(machine_id),
        "processing": super::vm_is_processing(machine_id),
    })
}

pub fn pause_json(machine_id: &str) -> Value {
    if super::pause_vm(machine_id) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

pub fn resume_json(machine_id: &str) -> Value {
    if super::clear_pause(machine_id) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

pub fn terminate_json(machine_id: &str) -> Value {
    if super::terminate_vm(machine_id) {
        json!({ "ok": true })
    } else {
        err(NOT_FOUND)
    }
}

// ---- The tree --------------------------------------------------------------

/// Make `child` a child of `parent`, clipping the child's effective
/// capabilities to the new ancestor path at once.
pub fn adopt_json(parent_id: &str, child_id: &str) -> Value {
    if super::adopt_vm(parent_id, child_id) {
        json!({ "ok": true })
    } else {
        err("adopt_rejected")
    }
}

/// A VM's place in the tree: its parent, its direct children, and its whole
/// descendant subtree in pre-order.
pub fn tree_json(machine_id: &str) -> Value {
    json!({
        "parent": super::vm_parent(machine_id),
        "children": super::vm_children(machine_id),
        "subtree": super::vm_subtree(machine_id),
    })
}

/// Terminate / pause / destroy a VM and everything below it. Returns the ids
/// actually affected, so a host can reconcile its own bookkeeping.
pub fn terminate_tree_json(machine_id: &str) -> Value {
    json!({ "affected": super::terminate_vm_tree(machine_id) })
}

pub fn pause_tree_json(machine_id: &str) -> Value {
    json!({ "affected": super::pause_vm_tree(machine_id) })
}

pub fn destroy_tree_json(machine_id: &str) -> Value {
    json!({ "affected": super::destroy_vm_tree(machine_id) })
}

/// Sweep every tree and destroy any branch whose aggregate usage has broken its
/// own root's budget — the "handle it or share its fate" rule. Returns one
/// entry per violation.
///
/// ```json
/// [{ "machineId": "app-a", "axis": "instructions",
///    "destroyed": ["app-a", "app-a-child"] }]
/// ```
pub fn enforce_tree_budgets_json() -> Value {
    Value::Array(
        super::enforce_tree_budgets()
            .into_iter()
            .map(|(id, axis, destroyed)| {
                json!({ "machineId": id, "axis": axis, "destroyed": destroyed })
            })
            .collect(),
    )
}

/// One call answering everything a host dashboard shows for a VM and its
/// branch: state, limits, own usage, subtree usage, both capability sets, and
/// the tree around it. Saves a host round-tripping six calls per frame.
pub fn snapshot_json(machine_id: &str) -> Value {
    if super::run_state(machine_id).is_none() {
        return err(NOT_FOUND);
    }
    json!({
        "machineId": machine_id,
        "state": state_json(machine_id),
        "limits": limits_json(machine_id),
        "usage": usage_json(machine_id),
        "subtreeUsage": subtree_usage_json(machine_id),
        "localCapabilities": local_capabilities_json(machine_id),
        "effectiveCapabilities": effective_capabilities_json(machine_id),
        "tree": tree_json(machine_id),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limits_round_trip_through_json() {
        let original = ResourceLimits::sandboxed();
        let parsed = limits_from_json(&limits_to_json(&original));
        assert_eq!(parsed, original);
    }

    #[test]
    fn an_absent_or_null_field_means_unbounded() {
        let l = limits_from_json(&json!({ "maxInstructions": 10, "maxMemoryBytes": null }));
        assert_eq!(l.max_instructions, Some(10));
        assert_eq!(l.max_memory_bytes, None);
        assert_eq!(l.max_call_depth, None, "absent fields are unbounded too");
    }

    #[test]
    fn unknown_limit_keys_are_ignored_rather_than_rejected() {
        // A newer host talking to an older VM must degrade, not fail.
        let l = limits_from_json(&json!({ "maxInstructions": 5, "maxFutureThing": 99 }));
        assert_eq!(l.max_instructions, Some(5));
    }

    #[test]
    fn capabilities_json_carries_every_capability() {
        let json = capabilities_to_json(&CapabilitySet::deny_all());
        let map = json.as_object().unwrap();
        assert_eq!(map.len(), Capability::all().len());
        for cap in Capability::all() {
            assert_eq!(
                map.get(cap.as_str()),
                Some(&Value::Bool(false)),
                "{} missing or wrong",
                cap.as_str()
            );
        }
    }
}
