//! Durable per-app key/value state, and the secrets a server function may read.
//!
//! # Scoping is the host's job, not the guest's
//!
//! Every key a guest supplies is namespaced by the host under the app it
//! belongs to. The guest never sends an app id — it could not be trusted with
//! one — so there is no key a guest can construct that reaches another app's
//! state. That is a property of where the scoping happens, not of what the keys
//! look like, and it is why the store takes the app id from the caller rather
//! than from the payload.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::Value;

/// How much state one app may hold. Exceeding it fails the write rather than
/// evicting, because silently dropping a mini app's data is worse than telling
/// it the write failed.
#[derive(Debug, Clone)]
pub struct StateLimits {
    pub max_keys: usize,
    pub max_value_bytes: usize,
    pub max_total_bytes: usize,
}

impl Default for StateLimits {
    fn default() -> Self {
        StateLimits {
            max_keys: 10_000,
            max_value_bytes: 256 * 1024,
            max_total_bytes: 16 * 1024 * 1024,
        }
    }
}

/// Why a write was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StateError {
    TooManyKeys,
    ValueTooLarge,
    QuotaExceeded,
}

impl StateError {
    pub fn as_str(&self) -> &'static str {
        match self {
            StateError::TooManyKeys => "too many keys",
            StateError::ValueTooLarge => "value too large",
            StateError::QuotaExceeded => "storage quota exceeded",
        }
    }
}

#[derive(Default)]
struct AppState {
    entries: HashMap<String, Value>,
    bytes: usize,
}

/// The store. Shared across every instance of every app on this host.
///
/// In-memory for now, behind a narrow enough interface (`get`/`set`/`delete`/
/// `list`) that a disk or database backing can replace the map without any
/// caller changing. What must not change is the scoping: `app` is always the
/// host's, never the guest's.
#[derive(Clone, Default)]
pub struct StateStore {
    apps: Arc<Mutex<HashMap<String, AppState>>>,
    limits: StateLimits,
}

impl StateStore {
    pub fn new(limits: StateLimits) -> Self {
        StateStore {
            apps: Arc::new(Mutex::new(HashMap::new())),
            limits,
        }
    }

    fn with_app<R>(&self, app: &str, body: impl FnOnce(&mut AppState) -> R) -> R {
        let mut apps = self
            .apps
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        body(apps.entry(app.to_string()).or_default())
    }

    pub fn get(&self, app: &str, key: &str) -> Option<Value> {
        self.with_app(app, |state| state.entries.get(key).cloned())
    }

    pub fn set(&self, app: &str, key: &str, value: Value) -> Result<(), StateError> {
        let encoded = value.to_string().len();
        if encoded > self.limits.max_value_bytes {
            return Err(StateError::ValueTooLarge);
        }
        self.with_app(app, |state| {
            let previous = state
                .entries
                .get(key)
                .map(|v| v.to_string().len())
                .unwrap_or(0);
            if previous == 0 && state.entries.len() >= self.limits.max_keys {
                return Err(StateError::TooManyKeys);
            }
            let next_total = state.bytes.saturating_sub(previous) + encoded;
            if next_total > self.limits.max_total_bytes {
                return Err(StateError::QuotaExceeded);
            }
            state.bytes = next_total;
            state.entries.insert(key.to_string(), value);
            Ok(())
        })
    }

    pub fn delete(&self, app: &str, key: &str) -> bool {
        self.with_app(app, |state| match state.entries.remove(key) {
            Some(old) => {
                state.bytes = state.bytes.saturating_sub(old.to_string().len());
                true
            }
            None => false,
        })
    }

    /// Keys beginning with `prefix`, sorted.
    ///
    /// Sorted because a guest that lists and renders needs a stable order, and
    /// a `HashMap`'s iteration order changes between runs — which would make a
    /// server component's output non-deterministic and so uncacheable.
    pub fn list(&self, app: &str, prefix: &str) -> Vec<String> {
        self.with_app(app, |state| {
            let mut keys: Vec<String> = state
                .entries
                .keys()
                .filter(|k| k.starts_with(prefix))
                .cloned()
                .collect();
            keys.sort();
            keys
        })
    }

    /// Total bytes an app is holding — the figure the storage meter reads.
    pub fn bytes_used(&self, app: &str) -> usize {
        self.with_app(app, |state| state.bytes)
    }
}

/// Secrets an app's server functions may read by name.
///
/// Values are injected by the operator and never packaged with the app, never
/// logged, and never returned to a client. The names an app may read come from
/// its manifest, so a guest asking for a name it did not declare gets null —
/// the same answer as a name that does not exist, deliberately, so the guest
/// cannot probe for which secrets the host holds.
#[derive(Clone, Default)]
pub struct SecretStore {
    by_app: Arc<Mutex<HashMap<String, HashMap<String, String>>>>,
}

impl SecretStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn put(&self, app: &str, name: &str, value: String) {
        let mut map = self
            .by_app
            .lock()
            .unwrap_or_else(|p| p.into_inner());
        map.entry(app.to_string())
            .or_default()
            .insert(name.to_string(), value);
    }

    /// Read a secret, but only if `declared` names it.
    pub fn get(&self, app: &str, name: &str, declared: &[String]) -> Option<String> {
        if !declared.iter().any(|d| d == name) {
            return None;
        }
        let map = self.by_app.lock().unwrap_or_else(|p| p.into_inner());
        map.get(app).and_then(|s| s.get(name)).cloned()
    }
}
