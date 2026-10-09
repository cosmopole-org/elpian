//! Conversations: append-only history plus the surfaces an agent created.
//!
//! In memory, keyed by (app, agent, user, conversation id) — the user is part
//! of the key, so one caller cannot continue another's conversation by
//! guessing its id. Idle conversations expire, and the store is capped.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::a2ui::Surfaces;

/// One conversation.
#[derive(Debug, Clone, Default)]
pub struct Conversation {
    pub id: String,
    /// Anthropic-shaped messages, append-only. Assistant content is stored as
    /// received (thinking blocks included) and echoed back unchanged.
    pub messages: Vec<Value>,
    /// Surfaces the agent created, with their components and last data model.
    pub surfaces: Surfaces,
    /// Tool calls the last assistant turn made that never got a result (the
    /// turn was cut off). Answered with errors before the next user turn, so
    /// the history stays well-formed.
    pub pending_tool_uses: Vec<String>,
    /// A turn has been admitted on this conversation and not finished; a
    /// second one is refused rather than interleaved.
    pub in_use: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct Key {
    app: String,
    agent: String,
    user: String,
    id: String,
}

struct Entry {
    conversation: Arc<Mutex<Conversation>>,
    last_used: Instant,
}

/// Why a conversation could not be opened.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenError {
    /// The id is not one this host accepts.
    BadId,
}

/// The store.
pub struct ConversationStore {
    entries: Mutex<HashMap<Key, Entry>>,
    ttl: Duration,
    cap: usize,
}

impl Default for ConversationStore {
    fn default() -> Self {
        ConversationStore::new(Duration::from_secs(30 * 60), 10_000)
    }
}

impl ConversationStore {
    pub fn new(ttl: Duration, cap: usize) -> Self {
        ConversationStore {
            entries: Mutex::new(HashMap::new()),
            ttl,
            cap: cap.max(1),
        }
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<Key, Entry>> {
        self.entries.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Open a conversation, creating it if it does not exist (for this user).
    /// Returns its id and handle.
    pub fn open(
        &self,
        app: &str,
        agent: &str,
        user: &str,
        id: Option<&str>,
    ) -> Result<(String, Arc<Mutex<Conversation>>), OpenError> {
        let id = match id {
            Some(id) if valid_id(id) => id.to_string(),
            Some(_) => return Err(OpenError::BadId),
            None => new_id(),
        };
        let key = Key {
            app: app.into(),
            agent: agent.into(),
            user: user.into(),
            id: id.clone(),
        };
        let now = Instant::now();
        let mut entries = self.lock();
        let ttl = self.ttl;
        entries.retain(|_, e| now.duration_since(e.last_used) < ttl);
        if let Some(entry) = entries.get_mut(&key) {
            entry.last_used = now;
            return Ok((id, Arc::clone(&entry.conversation)));
        }
        while entries.len() >= self.cap {
            let Some(oldest) = entries
                .iter()
                .min_by_key(|(_, e)| e.last_used)
                .map(|(k, _)| k.clone())
            else {
                break;
            };
            entries.remove(&oldest);
        }
        let conversation = Arc::new(Mutex::new(Conversation {
            id: id.clone(),
            ..Default::default()
        }));
        entries.insert(
            key,
            Entry {
                conversation: Arc::clone(&conversation),
                last_used: now,
            },
        );
        Ok((id, conversation))
    }

    /// Look a conversation up without creating it.
    pub fn get(
        &self,
        app: &str,
        agent: &str,
        user: &str,
        id: &str,
    ) -> Option<Arc<Mutex<Conversation>>> {
        let key = Key {
            app: app.into(),
            agent: agent.into(),
            user: user.into(),
            id: id.into(),
        };
        let entries = self.lock();
        entries
            .get(&key)
            .filter(|e| e.last_used.elapsed() < self.ttl)
            .map(|e| Arc::clone(&e.conversation))
    }

    /// Drop every conversation of one app (it was redeployed or removed).
    pub fn clear_app(&self, app: &str) -> usize {
        let mut entries = self.lock();
        let before = entries.len();
        entries.retain(|k, _| k.app != app);
        before - entries.len()
    }

    pub fn len(&self) -> usize {
        self.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

/// `[A-Za-z0-9_-]{1,128}`
pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// A fresh, unguessable conversation id.
pub fn new_id() -> String {
    let mut bytes = [0u8; 16];
    if getrandom::getrandom(&mut bytes).is_err() {
        // No OS randomness: fall back to something unique, if guessable.
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        bytes.copy_from_slice(&nanos.to_le_bytes());
    }
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("c_{hex}")
}
