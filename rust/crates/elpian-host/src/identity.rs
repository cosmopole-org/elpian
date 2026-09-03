//! Who is calling, and who may operate the host.
//!
//! # `ctx.user` may only ever come from a verified credential
//!
//! A server function that reads `ctx.user` and trusts it is making an
//! authorisation decision. If the identity came from anywhere the caller
//! controls — a request body field, a header the host copied through — then
//! every such decision is forgeable, and forgeable by exactly the person it is
//! protecting against.
//!
//! So identity is constructed here, from a credential this host verified, and
//! nowhere else. There is deliberately no way to set it from a payload.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// A verified caller.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Identity {
    /// Stable id for this caller within the host.
    pub id: String,
    /// Roles the host attached. An app may read these; it cannot set them.
    pub roles: Vec<String>,
}

impl Identity {
    pub fn has_role(&self, role: &str) -> bool {
        self.roles.iter().any(|r| r == role)
    }

    /// The shape a server function sees as `ctx.user`.
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({ "id": self.id, "roles": self.roles })
    }
}

/// Turns a credential into an identity, or refuses.
pub trait AuthProvider: Send + Sync {
    /// `credential` is whatever the caller presented — typically the value of
    /// an `Authorization` header. Returning `None` means anonymous, which is a
    /// legitimate answer: an app may serve anonymous callers.
    fn verify(&self, credential: Option<&str>) -> Option<Identity>;
}

/// Every caller is anonymous. The default, and the right one for a host that
/// has not been told how to authenticate.
pub struct AnonymousOnly;

impl AuthProvider for AnonymousOnly {
    fn verify(&self, _credential: Option<&str>) -> Option<Identity> {
        None
    }
}

/// A simple bearer-token provider: the operator registers tokens and the
/// identities they map to.
///
/// Deliberately not a JWT verifier or an OAuth client — those are integration
/// decisions with their own dependencies. What matters here is the *shape*: a
/// credential goes in, a verified identity comes out, and the host is the only
/// thing that can produce one.
#[derive(Default)]
pub struct StaticTokens {
    tokens: RwLock<HashMap<String, Identity>>,
}

impl StaticTokens {
    pub fn new() -> Arc<StaticTokens> {
        Arc::new(StaticTokens::default())
    }

    pub fn add(&self, token: &str, identity: Identity) {
        self.tokens
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .insert(token.to_string(), identity);
    }
}

impl AuthProvider for StaticTokens {
    fn verify(&self, credential: Option<&str>) -> Option<Identity> {
        let raw = credential?;
        // Accept both `Bearer xyz` and a bare token, so a caller that sends the
        // header the usual way and one that sends only the value both work.
        let token = raw.strip_prefix("Bearer ").unwrap_or(raw).trim();
        let tokens = self.tokens.read().unwrap_or_else(|p| p.into_inner());

        // Constant-time comparison against every registered token rather than a
        // map lookup. A hash lookup on a secret leaks through timing which
        // prefix matched, and the set of tokens is small enough that scanning
        // it costs nothing worth optimising.
        tokens
            .iter()
            .find(|(known, _)| {
                elpian_crypto::constant_time_eq(known.as_bytes(), token.as_bytes())
            })
            .map(|(_, identity)| identity.clone())
    }
}

/// Who may administer the host.
///
/// Separate from [`AuthProvider`] because they answer different questions and
/// must not share a credential: an app's user token is presented to app code,
/// and an operator token is not. Conflating them would mean any app that logged
/// its caller's token had logged an admin credential.
pub struct OperatorAuth {
    tokens: Vec<String>,
}

impl OperatorAuth {
    /// An admin surface with no tokens configured refuses everything.
    ///
    /// Not "allows everything" — an unconfigured admin API that is open is the
    /// failure mode that gets hosts taken over, and it fails silently, because
    /// nothing looks wrong until somebody finds it.
    pub fn new(tokens: Vec<String>) -> OperatorAuth {
        OperatorAuth { tokens }
    }

    pub fn is_configured(&self) -> bool {
        !self.tokens.is_empty()
    }

    pub fn authorize(&self, credential: Option<&str>) -> bool {
        let Some(raw) = credential else { return false };
        let token = raw.strip_prefix("Bearer ").unwrap_or(raw).trim();
        self.tokens
            .iter()
            .any(|known| elpian_crypto::constant_time_eq(known.as_bytes(), token.as_bytes()))
    }
}

/// One thing an operator did. Kept so "who changed what, when" has an answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdminEvent {
    pub at_ms: u64,
    pub action: String,
    pub app: String,
    pub detail: String,
    pub allowed: bool,
}

/// The admin audit trail.
///
/// Records refused attempts as well as successful ones — a run of refusals
/// against the admin API is the single most interesting thing this log can
/// contain, and a trail with only successes in it would not show it.
#[derive(Clone, Default)]
pub struct AdminAudit {
    events: Arc<RwLock<Vec<AdminEvent>>>,
    capacity: usize,
}

impl AdminAudit {
    pub fn new(capacity: usize) -> AdminAudit {
        AdminAudit {
            events: Arc::new(RwLock::new(Vec::new())),
            capacity,
        }
    }

    pub fn record(&self, event: AdminEvent) {
        let mut events = self.events.write().unwrap_or_else(|p| p.into_inner());
        events.push(event);
        // Bounded in memory. A durable trail is the operator's to arrange; what
        // must not happen is the host growing without limit because somebody is
        // hammering a refused endpoint.
        let capacity = if self.capacity == 0 { 1000 } else { self.capacity };
        if events.len() > capacity {
            let excess = events.len() - capacity;
            events.drain(0..excess);
        }
    }

    pub fn events(&self) -> Vec<AdminEvent> {
        self.events
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_admin_surface_with_no_tokens_refuses_everything() {
        let auth = OperatorAuth::new(vec![]);
        assert!(!auth.is_configured());
        assert!(!auth.authorize(None));
        assert!(!auth.authorize(Some("anything")));
        assert!(!auth.authorize(Some("Bearer ")));
    }

    #[test]
    fn an_operator_token_is_accepted_with_or_without_the_bearer_prefix() {
        let auth = OperatorAuth::new(vec!["s3cret".into()]);
        assert!(auth.authorize(Some("s3cret")));
        assert!(auth.authorize(Some("Bearer s3cret")));
        assert!(!auth.authorize(Some("s3cre")));
        assert!(!auth.authorize(Some("s3crett")));
        assert!(!auth.authorize(None));
    }

    #[test]
    fn an_identity_can_only_come_from_a_verified_credential() {
        let tokens = StaticTokens::new();
        tokens.add(
            "user-token",
            Identity {
                id: "alice".into(),
                roles: vec!["member".into()],
            },
        );

        assert_eq!(tokens.verify(Some("user-token")).unwrap().id, "alice");
        assert_eq!(tokens.verify(Some("Bearer user-token")).unwrap().id, "alice");
        // Anonymous is a legitimate answer, not an error.
        assert_eq!(tokens.verify(None), None);
        assert_eq!(tokens.verify(Some("guessed")), None);
    }

    #[test]
    fn roles_are_readable_but_never_settable_by_a_caller() {
        let identity = Identity {
            id: "alice".into(),
            roles: vec!["admin".into()],
        };
        assert!(identity.has_role("admin"));
        assert!(!identity.has_role("root"));
        assert_eq!(
            identity.to_json(),
            serde_json::json!({ "id": "alice", "roles": ["admin"] })
        );
    }

    #[test]
    fn the_audit_records_refusals_as_well_as_successes() {
        let audit = AdminAudit::new(10);
        audit.record(AdminEvent {
            at_ms: 1,
            action: "deploy".into(),
            app: "app".into(),
            detail: "1.0.0".into(),
            allowed: false,
        });
        audit.record(AdminEvent {
            at_ms: 2,
            action: "deploy".into(),
            app: "app".into(),
            detail: "1.0.0".into(),
            allowed: true,
        });
        let events = audit.events();
        assert_eq!(events.len(), 2);
        assert!(!events[0].allowed, "a run of refusals is the interesting case");
        assert!(events[1].allowed);
    }

    #[test]
    fn the_audit_is_bounded() {
        let audit = AdminAudit::new(4);
        for n in 0..50 {
            audit.record(AdminEvent {
                at_ms: n,
                action: "probe".into(),
                app: "app".into(),
                detail: String::new(),
                allowed: false,
            });
        }
        let events = audit.events();
        assert_eq!(events.len(), 4);
        assert_eq!(events.last().unwrap().at_ms, 49, "the newest are kept");
    }
}
