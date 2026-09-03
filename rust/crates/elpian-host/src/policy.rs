//! Manifest ∩ grant — the policy model, ported from Dart.
//!
//! # Why this is a port rather than a new design
//!
//! `MiniAppPolicy.resolve` in `lib/src/superapp/mini_app.dart` already decides
//! what a mini app holds, and a device already applies it. A server that
//! resolved the same question differently would mean an app could hold one set
//! of capabilities on a phone and another on the host — and the difference
//! would only show up as a bug in whichever direction was more permissive.
//!
//! So this is deliberately a *port*, and the fixtures in
//! `test/fixtures/policy_corpus.json` are read by both languages. The tree
//! already showed what happens without that: `ElpianCapability` was missing
//! `surface` while the VM had it (fixed in S0.5).
//!
//! # The two intersections, and why both
//!
//! * ∩ with the **grant** is the security property: an app cannot take more
//!   than the host allows.
//! * ∩ with the **request** is least privilege: an app that asked for nothing
//!   but state does not silently receive the network because its grant was
//!   generous.
//!
//! With one exception, which is the subtle part: a manifest that requests
//! *nothing at all* is treated as requesting everything it was granted.
//! Otherwise an app that simply omitted the field would launch with no
//! capabilities and fail confusingly. Least privilege applies to what an app
//! **states**, not to what it forgot to state.

use std::collections::BTreeSet;

use elpian_vm::api::{Capability, ResourceLimits};

/// What an app says it needs. A request, not a grant.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Manifest {
    pub id: String,
    pub version: String,
    pub requested_capabilities: BTreeSet<Capability>,
    /// The budget the app would like. `None` means it did not ask.
    pub requested_limits: Option<ResourceLimits>,
    pub allows_children: bool,
}

/// What the host permits.
#[derive(Debug, Clone, PartialEq)]
pub struct Grant {
    pub capabilities: BTreeSet<Capability>,
    pub limits: ResourceLimits,
    pub may_host_children: bool,
    /// An optional allowlist of individual host APIs, finer than a capability.
    /// `None` means "anything the capabilities permit".
    pub allowed_apis: Option<BTreeSet<String>>,
}

impl Default for Grant {
    fn default() -> Self {
        Grant {
            capabilities: BTreeSet::new(),
            limits: ResourceLimits::unlimited(),
            may_host_children: false,
            allowed_apis: None,
        }
    }
}

/// What the app actually gets.
#[derive(Debug, Clone, PartialEq)]
pub struct Policy {
    pub capabilities: BTreeSet<Capability>,
    pub limits: ResourceLimits,
    pub may_host_children: bool,
    /// What the app asked for and did not get. Worth keeping: an app seeing
    /// unexpected denials can be told exactly which, instead of guessing.
    pub denied_requests: BTreeSet<Capability>,
    allowed_apis: Option<BTreeSet<String>>,
}

impl Policy {
    /// Resolve a manifest against a grant.
    pub fn resolve(manifest: &Manifest, grant: &Grant) -> Policy {
        // The empty-request rule. See the module comment.
        let requested = if manifest.requested_capabilities.is_empty() {
            grant.capabilities.clone()
        } else {
            manifest.requested_capabilities.clone()
        };

        let allowed: BTreeSet<Capability> = requested
            .intersection(&grant.capabilities)
            .copied()
            .collect();
        let denied: BTreeSet<Capability> =
            requested.difference(&grant.capabilities).copied().collect();

        Policy {
            may_host_children: manifest.allows_children
                && grant.may_host_children
                && allowed.contains(&Capability::VmManage),
            limits: tightest(manifest.requested_limits.as_ref(), &grant.limits),
            capabilities: allowed,
            denied_requests: denied,
            allowed_apis: grant.allowed_apis.clone(),
        }
    }

    /// Whether `api_name` is permitted: its capability must be held, and it
    /// must survive the grant's API allowlist if there is one.
    pub fn allows_api(&self, api_name: &str) -> bool {
        if !self.capabilities.contains(&Capability::for_api(api_name)) {
            return false;
        }
        match &self.allowed_apis {
            Some(list) => list.contains(api_name),
            None => true,
        }
    }
}

/// The tighter of two budgets, axis by axis.
///
/// `None` on either side means "unbounded from this side", so the other wins;
/// `None` on both stays `None`. Note this is *not* `min` on `Option` — that
/// would make `None` win, which would let an app widen its budget by omitting
/// an axis.
pub fn tightest(requested: Option<&ResourceLimits>, granted: &ResourceLimits) -> ResourceLimits {
    let Some(requested) = requested else {
        return *granted;
    };
    fn tighter(a: Option<u64>, b: Option<u64>) -> Option<u64> {
        match (a, b) {
            (None, b) => b,
            (a, None) => a,
            (Some(a), Some(b)) => Some(a.min(b)),
        }
    }
    ResourceLimits {
        max_instructions: tighter(requested.max_instructions, granted.max_instructions),
        max_instructions_per_turn: tighter(
            requested.max_instructions_per_turn,
            granted.max_instructions_per_turn,
        ),
        max_memory_bytes: tighter(requested.max_memory_bytes, granted.max_memory_bytes),
        max_storage_bytes: tighter(requested.max_storage_bytes, granted.max_storage_bytes),
        max_call_depth: tighter(requested.max_call_depth, granted.max_call_depth),
    }
}

/// Parse a capability set from wire names, dropping unknown ones.
///
/// Dropping rather than rejecting is deliberate and matches Dart: a manifest
/// written against a newer Elpian must not brick the app on an older host, and
/// dropping is the safe direction — it can only ever narrow what is asked for.
pub fn capabilities_from_names<'a>(
    names: impl IntoIterator<Item = &'a str>,
) -> BTreeSet<Capability> {
    names.into_iter().filter_map(Capability::from_str).collect()
}
