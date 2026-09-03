//! Server components: the payload one returns, and the cache in front of it.
//!
//! # A component returns rather than renders
//!
//! A client-side guest calls `render` to submit a UI tree as a side effect. A
//! server component does not: it *returns* a payload. That is what makes it a
//! pure function of its arguments and the app's state, which is in turn what
//! makes it cacheable, testable without a host, and unable to half-render. The
//! server posture denies `Capability::Render` for exactly this reason.
//!
//! # The payload shape is not new
//!
//! It is the shape the Next.js bridge already parses
//! (`lib/src/integrations/nextjs_bridge.dart`) — `component`, `stylesheet`,
//! `meta`, `navigation`, `clientComponents` — minus `jsCode`. One parser, one
//! set of tests, and no third parallel format. `jsCode` is dropped deliberately:
//! it ships source for the device to compile, which is a second compile path on
//! the device and a much wider trust surface than a bundle that was signed and
//! verified. Islands are referenced by *name* instead, resolved out of the
//! client bundle the device already has.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

/// Why a returned value is not a usable component payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PayloadError {
    /// The function returned something that is not an object at all.
    NotAnObject,
    /// No `component` key, or it is not an object.
    MissingComponent,
    /// `jsCode` is refused rather than ignored: a component that emits it was
    /// written against the Next.js bridge's rules and would silently lose
    /// behaviour if the key were dropped quietly.
    JsCodeNotAllowed,
}

impl PayloadError {
    pub fn as_str(&self) -> &'static str {
        match self {
            PayloadError::NotAnObject => "a component must return an object",
            PayloadError::MissingComponent => "a component payload needs a \"component\" object",
            PayloadError::JsCodeNotAllowed => {
                "\"jsCode\" is not supported on the native path; reference an \
                 island by name in \"clientComponents\" instead"
            }
        }
    }
}

/// Cache directions a component may attach to its own payload.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Revalidation {
    /// Tags an action may invalidate by calling `cache.revalidate`.
    pub tags: Vec<String>,
    /// A time bound, in seconds. Absent means the entry lives until a tag
    /// invalidates it.
    pub seconds: Option<u64>,
}

/// A validated component payload.
#[derive(Debug, Clone, PartialEq)]
pub struct ComponentPayload {
    pub value: Value,
    pub revalidate: Revalidation,
}

impl ComponentPayload {
    /// Validate what a component returned.
    pub fn parse(returned: &Value) -> Result<ComponentPayload, PayloadError> {
        let object = returned.as_object().ok_or(PayloadError::NotAnObject)?;
        if !object
            .get("component")
            .map(Value::is_object)
            .unwrap_or(false)
        {
            return Err(PayloadError::MissingComponent);
        }
        if object.contains_key("jsCode") {
            return Err(PayloadError::JsCodeNotAllowed);
        }

        let revalidate = object
            .get("revalidate")
            .and_then(Value::as_object)
            .map(|r| Revalidation {
                tags: r
                    .get("tags")
                    .and_then(Value::as_array)
                    .map(|items| {
                        items
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default(),
                seconds: r.get("seconds").and_then(Value::as_u64),
            })
            .unwrap_or_default();

        Ok(ComponentPayload {
            value: returned.clone(),
            revalidate,
        })
    }

    /// The island names this payload references, if any.
    ///
    /// A device resolves each out of the client bundle it already fetched and
    /// verified. One it cannot resolve degrades to the payload's static
    /// rendering rather than failing the screen — an app that ships a component
    /// naming an island its client half does not have is a deployment mistake,
    /// and a blank screen is a worse answer than a non-interactive one.
    pub fn islands(&self) -> Vec<String> {
        self.value
            .get("clientComponents")
            .and_then(Value::as_object)
            .map(|map| {
                let mut names: Vec<String> = map.keys().cloned().collect();
                names.sort();
                names
            })
            .unwrap_or_default()
    }
}

/// One cached render.
#[derive(Clone)]
struct Entry {
    payload: Value,
    stored_at: Instant,
    ttl: Option<Duration>,
    tags: Vec<String>,
}

impl Entry {
    fn is_fresh(&self, now: Instant) -> bool {
        match self.ttl {
            Some(ttl) => now.duration_since(self.stored_at) < ttl,
            None => true,
        }
    }
}

/// The host's render cache.
///
/// Keyed by app, component and the *arguments*, because a component is a
/// function of them — two calls with different arguments are different renders,
/// and sharing an entry between them would serve one caller another's page.
#[derive(Clone, Default)]
pub struct RenderCache {
    entries: Arc<Mutex<HashMap<String, Entry>>>,
    /// A hard cap on entries, so an app calling a component with a million
    /// distinct arguments cannot evict the whole host's cache — or exhaust it.
    capacity: usize,
}

impl RenderCache {
    pub fn new(capacity: usize) -> RenderCache {
        RenderCache {
            entries: Arc::new(Mutex::new(HashMap::new())),
            capacity,
        }
    }

    /// The cache key. Arguments are serialised canonically — `serde_json`'s
    /// object maps preserve insertion order, so two logically equal argument
    /// objects written in different key orders would otherwise miss.
    fn key(app: &str, component: &str, args: &Value) -> String {
        format!("{app}\u{0}{component}\u{0}{}", canonical(args))
    }

    pub fn get(&self, app: &str, component: &str, args: &Value) -> Option<Value> {
        let key = Self::key(app, component, args);
        let now = Instant::now();
        let mut entries = self.lock();
        match entries.get(&key) {
            Some(entry) if entry.is_fresh(now) => Some(entry.payload.clone()),
            // A stale entry is removed on the way past rather than left to
            // accumulate; nothing else sweeps them.
            Some(_) => {
                entries.remove(&key);
                None
            }
            None => None,
        }
    }

    pub fn put(&self, app: &str, component: &str, args: &Value, payload: &ComponentPayload) {
        // A component that named neither a tag nor a TTL did not ask to be
        // cached. Caching it anyway would make a component that reads changing
        // state serve a stale page with no way to say otherwise.
        if payload.revalidate.tags.is_empty() && payload.revalidate.seconds.is_none() {
            return;
        }

        let mut entries = self.lock();
        if entries.len() >= self.capacity {
            // Drop the oldest. Not an LRU — this is a bound, not a hit-rate
            // optimisation, and an LRU here would need per-read bookkeeping on
            // the hot path to buy something the pool in S4 will revisit anyway.
            if let Some(oldest) = entries
                .iter()
                .min_by_key(|(_, e)| e.stored_at)
                .map(|(k, _)| k.clone())
            {
                entries.remove(&oldest);
            }
        }
        entries.insert(
            Self::key(app, component, args),
            Entry {
                payload: payload.value.clone(),
                stored_at: Instant::now(),
                ttl: payload.revalidate.seconds.map(Duration::from_secs),
                tags: payload.revalidate.tags.clone(),
            },
        );
    }

    /// Drop every entry of `app` carrying `tag`. Returns how many went.
    ///
    /// Scoped to one app: a tag is a name an app chose, and two apps both using
    /// `"notes"` are not talking about the same thing. An unscoped invalidation
    /// would let any app clear any other's cache by guessing a common word.
    pub fn revalidate(&self, app: &str, tag: &str) -> usize {
        let prefix = format!("{app}\u{0}");
        let mut entries = self.lock();
        let doomed: Vec<String> = entries
            .iter()
            .filter(|(key, entry)| key.starts_with(&prefix) && entry.tags.iter().any(|t| t == tag))
            .map(|(key, _)| key.clone())
            .collect();
        for key in &doomed {
            entries.remove(key);
        }
        doomed.len()
    }

    /// Drop every entry belonging to one app, whatever its tags. Returns how
    /// many went.
    pub fn clear_app(&self, app: &str) -> usize {
        let prefix = format!("{app}\u{0}");
        let mut entries = self.lock();
        let doomed: Vec<String> = entries
            .keys()
            .filter(|key| key.starts_with(&prefix))
            .cloned()
            .collect();
        for key in &doomed {
            entries.remove(key);
        }
        doomed.len()
    }

    pub fn len(&self) -> usize {
        self.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Entry>> {
        self.entries.lock().unwrap_or_else(|p| p.into_inner())
    }
}

/// Serialise with object keys sorted, so equal arguments produce equal keys
/// regardless of how the guest wrote them.
fn canonical(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let inner: Vec<String> = keys
                .into_iter()
                .map(|k| format!("{}:{}", json!(k), canonical(&map[k])))
                .collect();
            format!("{{{}}}", inner.join(","))
        }
        Value::Array(items) => {
            let inner: Vec<String> = items.iter().map(canonical).collect();
            format!("[{}]", inner.join(","))
        }
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(tags: &[&str], seconds: Option<u64>) -> ComponentPayload {
        let mut revalidate = serde_json::Map::new();
        if !tags.is_empty() {
            revalidate.insert("tags".into(), json!(tags));
        }
        if let Some(s) = seconds {
            revalidate.insert("seconds".into(), json!(s));
        }
        ComponentPayload::parse(&json!({
            "component": { "type": "text", "text": "hi" },
            "revalidate": Value::Object(revalidate),
        }))
        .unwrap()
    }

    #[test]
    fn a_payload_must_carry_a_component_object() {
        assert_eq!(
            ComponentPayload::parse(&json!("just a string")),
            Err(PayloadError::NotAnObject)
        );
        assert_eq!(
            ComponentPayload::parse(&json!({ "stylesheet": {} })),
            Err(PayloadError::MissingComponent)
        );
        assert_eq!(
            ComponentPayload::parse(&json!({ "component": "not an object" })),
            Err(PayloadError::MissingComponent)
        );
    }

    #[test]
    fn js_code_is_refused_rather_than_silently_dropped() {
        let result = ComponentPayload::parse(&json!({
            "component": { "type": "text" },
            "jsCode": "function C(){}",
        }));
        assert_eq!(result, Err(PayloadError::JsCodeNotAllowed));
    }

    #[test]
    fn argument_key_order_does_not_change_the_cache_key() {
        let cache = RenderCache::new(8);
        let entry = payload(&["notes"], None);
        cache.put("app", "List", &json!({ "a": 1, "b": 2 }), &entry);
        assert!(
            cache
                .get("app", "List", &json!({ "b": 2, "a": 1 }))
                .is_some(),
            "the same arguments written in another order must hit"
        );
        assert!(
            cache
                .get("app", "List", &json!({ "a": 1, "b": 3 }))
                .is_none(),
            "different arguments must miss"
        );
    }

    #[test]
    fn a_component_that_asked_for_nothing_is_not_cached() {
        let cache = RenderCache::new(8);
        let entry = ComponentPayload::parse(&json!({ "component": {} })).unwrap();
        cache.put("app", "Live", &json!(null), &entry);
        assert!(
            cache.get("app", "Live", &json!(null)).is_none(),
            "caching a component that named neither a tag nor a TTL would serve \
             stale state with no way for it to say otherwise"
        );
    }

    #[test]
    fn revalidating_a_tag_clears_only_that_apps_entries() {
        let cache = RenderCache::new(16);
        let tagged = payload(&["notes"], None);
        cache.put("mine", "List", &json!(null), &tagged);
        cache.put("theirs", "List", &json!(null), &tagged);

        assert_eq!(cache.revalidate("mine", "notes"), 1);
        assert!(cache.get("mine", "List", &json!(null)).is_none());
        assert!(
            cache.get("theirs", "List", &json!(null)).is_some(),
            "one app must not be able to clear another's cache by naming a \
             tag they happen to share"
        );
    }

    #[test]
    fn a_ttl_expires_the_entry() {
        let cache = RenderCache::new(8);
        cache.put("app", "Clock", &json!(null), &payload(&[], Some(0)));
        assert!(
            cache.get("app", "Clock", &json!(null)).is_none(),
            "a zero-second TTL is already stale"
        );
    }

    #[test]
    fn the_cache_is_bounded() {
        let cache = RenderCache::new(4);
        let entry = payload(&["t"], None);
        for n in 0..50 {
            cache.put("app", "List", &json!({ "page": n }), &entry);
        }
        assert!(cache.len() <= 4, "cache grew to {}", cache.len());
    }

    #[test]
    fn islands_are_listed_by_name() {
        let payload = ComponentPayload::parse(&json!({
            "component": { "type": "column" },
            "clientComponents": { "Counter": { "props": {} }, "Toggle": {} },
        }))
        .unwrap();
        assert_eq!(payload.islands(), vec!["Counter", "Toggle"]);
    }
}
