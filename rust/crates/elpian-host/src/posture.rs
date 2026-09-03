//! What a server-side function VM is allowed to do.
//!
//! The client posture and the server posture are not the same set with
//! different values in it — they are different *shapes*. A client mini app
//! draws, so it holds the surface and DOM gates and does not hold state. A
//! server function has no surface at all and does hold state. Writing the
//! server posture as "the client one, minus some things" would keep handing new
//! client capabilities to server functions by default, which is the wrong
//! direction for a default to fail in.
//!
//! So the server posture is written out positively: it starts from *nothing*
//! and names what a server function may do.

use elpian_vm::api::{Capability, CapabilitySet};

/// The capabilities a server function may ever be granted.
///
/// An app's manifest narrows this further; nothing widens it. A capability
/// absent here is absent for every server function of every app, however
/// trusted — because the corresponding host API is not implemented on the
/// server side at all, and a gate that lets a call through to nothing is worse
/// than no gate.
pub const SERVER_GRANTABLE: &[Capability] = &[
    // Diagnostics. A server function that cannot log is very hard to operate.
    Capability::Logging,
    // The reason a server function exists: durable state, and the secrets it
    // was declared to need.
    Capability::State,
    // A server function may call *this app's other* server functions. It may
    // not name another app's — the host resolves within the app it already
    // routed the request to.
    Capability::ServerCall,
    // Time and randomness. Both are non-deterministic and both are ordinary.
    Capability::Clock,
    Capability::Randomness,
    // The app-rooted filesystem. Confined by the host to the app's own
    // directory and charged against its storage budget.
    Capability::Storage,
    // Egress — but only ever through the broker, and only when the app's
    // network mode is not `closed`. See `S3`; until the broker lands this is
    // granted to no one.
    Capability::Network,
];

/// The capabilities that are *never* granted to a server function, each with
/// the reason. Kept as data rather than a comment so the test that asserts the
/// posture can read it, and so a new capability has to be classified rather
/// than silently defaulting.
pub const SERVER_DENIED: &[(Capability, &str)] = &[
    (
        Capability::Gpu,
        "there is no GPU on the server side of a mini app",
    ),
    (
        Capability::Surface,
        "a server function returns a payload; it never draws",
    ),
    (
        Capability::Dom,
        "there is no document tree on the server",
    ),
    (
        Capability::Canvas,
        "there is no drawing surface on the server",
    ),
    (
        Capability::Render,
        "a server component *returns* a UI payload rather than submitting one; \
         letting it call `render` would make it a side effect the host cannot cache",
    ),
    (
        Capability::Timers,
        "a function invocation is bounded by its deadline. A timer that outlives \
         the invocation has nothing to fire into, and one that does not is just \
         a slower way to spend the deadline",
    ),
    (
        Capability::ModuleImport,
        "an app's server code is what was packaged and verified. Pulling in a \
         module at run time is exactly the hole the package signature closes",
    ),
    (
        Capability::VmManage,
        "instances are the host's to create and destroy. A guest that could \
         spawn its own would be outside the pool, the meters and the budgets",
    ),
    (
        Capability::Tasks,
        "spends host threads rather than guest instructions, so it escapes the \
         invocation's budget",
    ),
    (
        Capability::Environment,
        "the client's environment (viewport, locale) is not the server's, and \
         serving a fabricated one invites code that quietly depends on it",
    ),
    (
        Capability::HostMessaging,
        "the embedder-defined pipe belongs to a client embedder. A server \
         function talks to its caller through its return value",
    ),
    (
        Capability::Other,
        "the fail-safe gate. Granting it would let through every host API that \
         has not been classified yet — including ones added after this app was \
         reviewed",
    ),
];

/// The starting posture for a server function: deny everything, then allow only
/// what `granted` names *and* [`SERVER_GRANTABLE`] permits.
///
/// The intersection is the point. An app manifest asking for `dom` does not get
/// it, and — more usefully — an app manifest asking for nothing in particular
/// does not quietly get everything, because the base is deny-all rather than
/// the VM's default allow-all.
pub fn server_capabilities(granted: &[Capability]) -> CapabilitySet {
    let mut caps = CapabilitySet::deny_all();
    for cap in granted {
        if SERVER_GRANTABLE.contains(cap) {
            caps.set(*cap, true);
        }
    }
    caps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_capability_is_classified() {
        for cap in Capability::all() {
            let grantable = SERVER_GRANTABLE.contains(&cap);
            let denied = SERVER_DENIED.iter().any(|(c, _)| *c == cap);
            assert!(
                grantable ^ denied,
                "{} is {} — every capability must be exactly one of grantable \
                 or denied, so adding one to the VM forces a decision here",
                cap.as_str(),
                if grantable { "both" } else { "neither" }
            );
        }
    }

    #[test]
    fn the_posture_starts_from_deny_all() {
        // An app that asks for nothing gets nothing — not the VM's allow-all
        // default.
        let caps = server_capabilities(&[]);
        for cap in Capability::all() {
            assert!(
                !caps.is_allowed(cap),
                "{} was allowed by an empty grant",
                cap.as_str()
            );
        }
    }

    #[test]
    fn a_grant_cannot_reach_past_the_posture() {
        // Even asked for explicitly, a denied capability stays denied.
        let caps = server_capabilities(&[Capability::Dom, Capability::VmManage, Capability::State]);
        assert!(!caps.is_allowed(Capability::Dom));
        assert!(!caps.is_allowed(Capability::VmManage));
        assert!(caps.is_allowed(Capability::State), "a grantable one still lands");
    }
}
