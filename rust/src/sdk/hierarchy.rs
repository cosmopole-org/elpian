//! The VM tree: parent/child relations between VM instances plus the
//! hierarchical governance rules that ride on them.
//!
//! A VM may instantiate other VMs; the instantiator becomes the **parent** and
//! holds full control of the child (lifecycle, limits, permissions). Three
//! invariants define the tree:
//!
//! 1. **Lifecycle binding** — terminating a VM terminates its whole descendant
//!    subtree ([`VmHierarchy::subtree`] enumerates it, the embedder applies the
//!    terminate to each).
//! 2. **Aggregate resource accounting** — a parent's consumption is measured as
//!    its *own* usage plus the usage of every VM in its descendant subtree.
//!    A parent whose aggregate blows its own budget takes its entire subtree
//!    down with it (so a hung child that the parent never handles eventually
//!    costs the parent, its other children, and the hung child their lives —
//!    the "handle it or share its fate" rule).
//! 3. **Permission intersection** — a VM's *effective* capability set is the
//!    AND of the *locally granted* sets along its ancestor path. A parent that
//!    lacks a permission can never confer it; a parent that has one may grant
//!    it to any child, and an on-the-fly change anywhere in the path is
//!    recomputed for the whole descendant subtree at once.
//!
//! The structure is pure data (no statics, no locks) so it is unit-testable in
//! isolation; the process-wide instance and the functions combining it with the
//! live VM registry live in [`crate::api`].

use std::collections::HashMap;

use crate::sdk::capabilities::{Capability, CapabilitySet};
use crate::sdk::limits::{ResourceLimits, ResourceUsage};

/// Parent/child edges between VM instances (keyed by machine id) plus each
/// VM's locally-granted capability set.
#[derive(Default)]
pub struct VmHierarchy {
    parent: HashMap<String, String>,
    children: HashMap<String, Vec<String>>,
    /// The grants each VM was given by its creator (before ancestor
    /// intersection). A VM absent from this map is treated as allow-all —
    /// the posture of a standalone/root VM.
    local_caps: HashMap<String, CapabilitySet>,
}

impl VmHierarchy {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record `child` as a child of `parent`. Returns `false` (and changes
    /// nothing) if the edge would create a cycle or `child` already has a
    /// parent.
    pub fn adopt(&mut self, parent: &str, child: &str) -> bool {
        if parent == child || self.parent.contains_key(child) {
            return false;
        }
        // Reject cycles: `parent` must not be a descendant of `child`.
        let mut cursor = Some(parent.to_string());
        while let Some(id) = cursor {
            if id == child {
                return false;
            }
            cursor = self.parent.get(&id).cloned();
        }
        self.parent.insert(child.to_string(), parent.to_string());
        self.children.entry(parent.to_string()).or_default().push(child.to_string());
        true
    }

    pub fn parent_of(&self, id: &str) -> Option<&str> {
        self.parent.get(id).map(|s| s.as_str())
    }

    pub fn children_of(&self, id: &str) -> &[String] {
        self.children.get(id).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// `id` plus every descendant, pre-order (parents before children).
    pub fn subtree(&self, id: &str) -> Vec<String> {
        let mut out = vec![id.to_string()];
        let mut i = 0;
        while i < out.len() {
            let current = out[i].clone();
            if let Some(kids) = self.children.get(&current) {
                out.extend(kids.iter().cloned());
            }
            i += 1;
        }
        out
    }

    /// Whether `ancestor` is `id` itself or on `id`'s parent chain.
    pub fn is_ancestor_or_self(&self, ancestor: &str, id: &str) -> bool {
        let mut cursor = Some(id.to_string());
        while let Some(current) = cursor {
            if current == ancestor {
                return true;
            }
            cursor = self.parent.get(&current).cloned();
        }
        false
    }

    /// Remove `id` and its whole subtree from the hierarchy, returning the
    /// removed ids (pre-order). The edge to `id`'s parent is severed too.
    pub fn remove_subtree(&mut self, id: &str) -> Vec<String> {
        let ids = self.subtree(id);
        if let Some(p) = self.parent.remove(id) {
            if let Some(kids) = self.children.get_mut(&p) {
                kids.retain(|k| k != id);
            }
        }
        for vm in &ids {
            self.parent.remove(vm);
            self.children.remove(vm);
            self.local_caps.remove(vm);
        }
        ids
    }

    /// Replace the locally-granted capability set of one VM.
    pub fn set_local_caps(&mut self, id: &str, caps: CapabilitySet) {
        self.local_caps.insert(id.to_string(), caps);
    }

    /// Toggle one locally-granted capability of one VM.
    pub fn set_local_capability(&mut self, id: &str, cap: Capability, allowed: bool) {
        self.local_caps
            .entry(id.to_string())
            .or_insert_with(CapabilitySet::allow_all)
            .set(cap, allowed);
    }

    /// The locally-granted set of one VM (allow-all when never restricted).
    pub fn local_caps(&self, id: &str) -> CapabilitySet {
        self.local_caps.get(id).cloned().unwrap_or_else(CapabilitySet::allow_all)
    }

    /// The **effective** capability set of one VM: the intersection (logical
    /// AND, per capability) of the locally-granted sets along the path from
    /// the root ancestor down to the VM itself. This is the set the executor
    /// must enforce; recompute it (for the whole affected subtree) whenever a
    /// local grant anywhere on the path changes.
    pub fn effective_caps(&self, id: &str) -> CapabilitySet {
        let mut eff = CapabilitySet::allow_all();
        let mut cursor = Some(id.to_string());
        while let Some(current) = cursor {
            let local = self.local_caps(&current);
            for cap in Capability::all() {
                if !local.is_allowed(cap) {
                    eff.set(cap, false);
                }
            }
            cursor = self.parent.get(&current).cloned();
        }
        eff
    }

    /// Every VM currently known to the hierarchy that has no parent (subtree
    /// roots), for whole-forest sweeps.
    pub fn roots(&self) -> Vec<String> {
        let mut out: Vec<String> = self
            .children
            .keys()
            .filter(|id| !self.parent.contains_key(*id))
            .cloned()
            .collect();
        out.sort();
        out
    }
}

/// Sum two usage tallies the way subtree aggregation wants: additive budgets
/// add, depth-like gauges take the max.
pub fn accumulate_usage(total: &mut ResourceUsage, u: &ResourceUsage) {
    total.instructions = total.instructions.saturating_add(u.instructions);
    total.instructions_this_turn =
        total.instructions_this_turn.saturating_add(u.instructions_this_turn);
    total.memory_bytes = total.memory_bytes.saturating_add(u.memory_bytes);
    total.peak_memory_bytes = total.peak_memory_bytes.saturating_add(u.peak_memory_bytes);
    total.storage_bytes = total.storage_bytes.saturating_add(u.storage_bytes);
    total.call_depth = total.call_depth.max(u.call_depth);
    total.peak_call_depth = total.peak_call_depth.max(u.peak_call_depth);
}

/// Whether an aggregate subtree usage breaks the subtree root's own budgets.
/// Only the *cumulative* budgets participate (instructions, memory, storage);
/// per-turn and call-depth caps are inherently per-instance and stay enforced
/// by each instance's own governor.
pub fn aggregate_exceeds(limits: &ResourceLimits, aggregate: &ResourceUsage) -> Option<&'static str> {
    if let Some(max) = limits.max_instructions {
        if aggregate.instructions > max {
            return Some("instructions");
        }
    }
    if let Some(max) = limits.max_memory_bytes {
        if aggregate.memory_bytes > max {
            return Some("memory");
        }
    }
    if let Some(max) = limits.max_storage_bytes {
        if aggregate.storage_bytes > max {
            return Some("storage");
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adopt_builds_a_tree_and_rejects_cycles() {
        let mut h = VmHierarchy::new();
        assert!(h.adopt("root", "a"));
        assert!(h.adopt("root", "b"));
        assert!(h.adopt("a", "a1"));
        assert!(!h.adopt("a1", "root"), "cycle rejected");
        assert!(!h.adopt("b", "a1"), "second parent rejected");
        assert_eq!(h.subtree("root"), vec!["root", "a", "b", "a1"]);
        assert_eq!(h.subtree("a"), vec!["a", "a1"]);
        assert!(h.is_ancestor_or_self("root", "a1"));
        assert!(h.is_ancestor_or_self("a", "a"));
        assert!(!h.is_ancestor_or_self("b", "a1"));
    }

    #[test]
    fn remove_subtree_severs_the_whole_branch() {
        let mut h = VmHierarchy::new();
        h.adopt("root", "a");
        h.adopt("a", "a1");
        h.adopt("a1", "a2");
        let removed = h.remove_subtree("a");
        assert_eq!(removed, vec!["a", "a1", "a2"]);
        assert_eq!(h.subtree("root"), vec!["root"]);
        assert!(h.parent_of("a1").is_none());
    }

    #[test]
    fn effective_caps_intersect_down_the_ancestor_path() {
        let mut h = VmHierarchy::new();
        h.adopt("root", "child");
        h.adopt("child", "grandchild");

        // Everyone starts allow-all.
        assert!(h.effective_caps("grandchild").is_allowed(Capability::Network));

        // Revoking on the middle VM shadows the whole branch below it…
        h.set_local_capability("child", Capability::Network, false);
        assert!(!h.effective_caps("child").is_allowed(Capability::Network));
        assert!(!h.effective_caps("grandchild").is_allowed(Capability::Network));
        // …even if the grandchild is locally granted.
        h.set_local_capability("grandchild", Capability::Network, true);
        assert!(!h.effective_caps("grandchild").is_allowed(Capability::Network));

        // Re-granting on the middle VM restores the grandchild.
        h.set_local_capability("child", Capability::Network, true);
        assert!(h.effective_caps("grandchild").is_allowed(Capability::Network));

        // A root revocation dominates everything.
        h.set_local_capability("root", Capability::Network, false);
        assert!(!h.effective_caps("grandchild").is_allowed(Capability::Network));
        // Unrelated capabilities stay untouched.
        assert!(h.effective_caps("grandchild").is_allowed(Capability::Storage));
    }

    #[test]
    fn aggregate_usage_adds_budgets_and_maxes_depths() {
        let mut total = ResourceUsage::default();
        accumulate_usage(
            &mut total,
            &ResourceUsage { instructions: 10, memory_bytes: 100, call_depth: 3, ..Default::default() },
        );
        accumulate_usage(
            &mut total,
            &ResourceUsage { instructions: 5, memory_bytes: 50, call_depth: 7, ..Default::default() },
        );
        assert_eq!(total.instructions, 15);
        assert_eq!(total.memory_bytes, 150);
        assert_eq!(total.call_depth, 7);
    }

    #[test]
    fn aggregate_budget_check_flags_the_right_axis() {
        let limits = ResourceLimits {
            max_instructions: Some(100),
            max_memory_bytes: Some(1000),
            ..ResourceLimits::unlimited()
        };
        let ok = ResourceUsage { instructions: 100, memory_bytes: 1000, ..Default::default() };
        assert_eq!(aggregate_exceeds(&limits, &ok), None);
        let too_much =
            ResourceUsage { instructions: 101, memory_bytes: 10, ..Default::default() };
        assert_eq!(aggregate_exceeds(&limits, &too_much), Some("instructions"));
        let fat = ResourceUsage { instructions: 1, memory_bytes: 2000, ..Default::default() };
        assert_eq!(aggregate_exceeds(&limits, &fat), Some("memory"));
    }
}
