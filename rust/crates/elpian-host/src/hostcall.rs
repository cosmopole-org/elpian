//! The host-call envelope, and the trait a host implements to answer one.

use serde_json::Value;

/// One `askHost` call, parsed out of the VM's envelope.
#[derive(Debug, Clone, PartialEq)]
pub struct HostCall {
    /// Which instance made the call. The host uses it to scope state and
    /// filesystem access — never the guest, which cannot forge it because it
    /// never supplies it.
    pub machine_id: String,
    /// The API name, e.g. `kv.get`.
    pub api: String,
    /// The call's arguments, as the guest passed them.
    pub payload: Value,
}

impl HostCall {
    /// Parse the `{"machineId","apiName","payload"}` envelope the VM emits.
    pub fn parse(envelope: &str) -> Option<HostCall> {
        let value: Value = serde_json::from_str(envelope).ok()?;
        Some(HostCall {
            machine_id: value.get("machineId")?.as_str()?.to_string(),
            api: value.get("apiName")?.as_str()?.to_string(),
            payload: value.get("payload").cloned().unwrap_or(Value::Null),
        })
    }

    /// Positional argument `index`, or null.
    ///
    /// The guest SDK passes arguments as an array; a call made by hand may pass
    /// a bare value, which reads as argument 0. Being lenient here keeps a
    /// hand-written guest working without a special case at every call site.
    pub fn arg(&self, index: usize) -> &Value {
        match &self.payload {
            Value::Array(items) => items.get(index).unwrap_or(&Value::Null),
            other if index == 0 => other,
            _ => &Value::Null,
        }
    }

    /// Positional argument `index` as a string, if it is one.
    pub fn str_arg(&self, index: usize) -> Option<&str> {
        self.arg(index).as_str()
    }
}

/// What a host must be able to do to run a server function.
///
/// Implemented by the real host and by tests. Keeping it a trait is what lets
/// the invocation loop be tested without a filesystem, a store, or a socket.
pub trait HostServices {
    /// Answer one host call. The return value becomes the `askHost` result.
    ///
    /// Returning `Value::Null` is always safe: it is what the VM itself
    /// substitutes for a denied capability, so guest code already has to cope
    /// with it.
    fn service(&mut self, call: &HostCall) -> Value;

    /// Record an operator-facing diagnostic. Separate from servicing a guest's
    /// `log` call: this is the *host* talking about the guest.
    fn log(&mut self, message: &str);
}
