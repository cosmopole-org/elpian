//! `dart:isolate` — ports and cooperative isolates.
//!
//! Full Dart isolates are share-nothing OS-thread actors. On a single embedded
//! Elpian VM we provide the **same `ReceivePort`/`SendPort` message-passing API
//! and semantics** as *cooperative* actors: messages are queued host-side and
//! delivered to the guest through the event loop, preserving send order. This is
//! the model most miniapp/interpreter systems use; it keeps the API and the
//! "communicate only by messages" discipline while running on one interpreter.
//! (True parallelism would require spawning additional VM instances — a later
//! step; the API here is forward-compatible with that.)

use std::collections::{HashSet, VecDeque};

use serde_json::Value;

/// Host-side port registry and message queue.
#[derive(Debug, Default)]
pub struct PortTable {
    ports: HashSet<u32>,
    queue: VecDeque<(u32, Value)>,
    /// Pending `Isolate.spawn` requests: (entry function name, message).
    spawns: VecDeque<(String, Value)>,
    next_id: u32,
}

impl PortTable {
    pub fn new() -> Self {
        PortTable::default()
    }

    /// `ReceivePort()` — allocate a port the guest can receive on.
    pub fn new_receive_port(&mut self) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        self.ports.insert(id);
        id
    }

    /// `sendPort.send(message)` — enqueue a message for delivery. Sending to an
    /// unknown port is an error (a closed/invalid port).
    pub fn send(&mut self, port: u32, message: Value) -> Result<(), String> {
        if !self.ports.contains(&port) {
            return Err(format!("StateError: send to unknown port {port}"));
        }
        self.queue.push_back((port, message));
        Ok(())
    }

    /// `port.close()`.
    pub fn close(&mut self, port: u32) -> bool {
        self.ports.remove(&port)
    }

    /// `Isolate.spawn(entry, message)` — queue a cooperative spawn.
    pub fn spawn(&mut self, entry: String, message: Value) {
        self.spawns.push_back((entry, message));
    }

    /// Next pending spawn, if any (drained before port messages).
    pub fn pop_spawn(&mut self) -> Option<(String, Value)> {
        self.spawns.pop_front()
    }

    /// Next pending port message in send order, if any.
    pub fn pop_message(&mut self) -> Option<(u32, Value)> {
        self.queue.pop_front()
    }

    pub fn has_pending(&self) -> bool {
        !self.queue.is_empty() || !self.spawns.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn messages_deliver_in_send_order() {
        let mut t = PortTable::new();
        let p = t.new_receive_port();
        t.send(p, json!("a")).unwrap();
        t.send(p, json!("b")).unwrap();
        assert_eq!(t.pop_message(), Some((p, json!("a"))));
        assert_eq!(t.pop_message(), Some((p, json!("b"))));
        assert_eq!(t.pop_message(), None);
    }

    #[test]
    fn send_to_unknown_port_errors() {
        let mut t = PortTable::new();
        assert!(t.send(999, json!("x")).is_err());
    }

    #[test]
    fn spawns_queue_and_drain() {
        let mut t = PortTable::new();
        t.spawn("worker".into(), json!({"n": 1}));
        assert_eq!(t.pop_spawn(), Some(("worker".to_string(), json!({"n": 1}))));
        assert_eq!(t.pop_spawn(), None);
    }
}
