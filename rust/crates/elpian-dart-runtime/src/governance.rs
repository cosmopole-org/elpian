//! Capability and resource governance for the Dart runtime layer.
//!
//! The user requirement is explicit: the `dart:*` foundational libraries must be
//! implemented *while respecting the controlling mechanisms* (access limiting /
//! resource limiting). Governance here is **two-layer**:
//!
//! 1. **VM layer (backstop).** `elpian-vm` already gates every `askHost` call by
//!    a coarse [`elpian_vm::…::Capability`] family; a disabled family
//!    short-circuits the call to a typed null before it ever reaches this crate.
//!
//! 2. **Dart layer (this module).** Each `dart:<library>` is mapped to a
//!    [`DartCapability`], and every serviced call is additionally checked here
//!    and metered. This gives per-library, Dart-meaningful access control
//!    (e.g. `dart:io` off but `dart:ui` on) that the coarse VM families cannot
//!    express, and per-call resource accounting on top of the VM's instruction/
//!    memory limits.

use std::collections::HashSet;

/// Dart-meaningful capability families. Finer-grained than the VM's coarse set:
/// each maps a *library* (or a class of side effect) to an access gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DartCapability {
    /// `dart:ui`, `dart:ui.Canvas`, scene building — anything that draws.
    Painting,
    /// `dart:typed_data` — in-VM byte buffers. Pure memory; no external access.
    TypedData,
    /// `dart:io` filesystem/socket access.
    Io,
    /// `dart:isolate` — spawning and messaging isolates.
    Isolate,
    /// `dart:ffi` — foreign native calls. Off by default (highest risk).
    Ffi,
    /// Clock / entropy (`DateTime.now`, `Random`).
    Environment,
}

/// The set of Dart capabilities currently granted to a runtime instance.
#[derive(Debug, Clone)]
pub struct DartCapabilitySet {
    granted: HashSet<DartCapability>,
}

impl DartCapabilitySet {
    /// A conservative default: pure/in-VM families on (painting, typed data,
    /// environment), external and native families off (io, isolate, ffi). This
    /// mirrors Dart/Flutter's own "deny by default for the dangerous surfaces"
    /// posture and keeps a freshly loaded miniapp sandboxed.
    pub fn sandboxed() -> Self {
        let mut granted = HashSet::new();
        granted.insert(DartCapability::Painting);
        granted.insert(DartCapability::TypedData);
        granted.insert(DartCapability::Environment);
        DartCapabilitySet { granted }
    }

    /// Everything granted — for trusted first-party app code.
    pub fn full() -> Self {
        use DartCapability::*;
        let mut granted = HashSet::new();
        for c in [Painting, TypedData, Io, Isolate, Ffi, Environment] {
            granted.insert(c);
        }
        DartCapabilitySet { granted }
    }

    pub fn grant(&mut self, cap: DartCapability) {
        self.granted.insert(cap);
    }

    pub fn revoke(&mut self, cap: DartCapability) {
        self.granted.remove(&cap);
    }

    pub fn allows(&self, cap: DartCapability) -> bool {
        self.granted.contains(&cap)
    }
}

/// Which [`DartCapability`] a `dart:<library>/...` api-name requires. The
/// api-name convention is `dart:<library>/<Class.method>`; we key on the library
/// segment. Unknown libraries require [`DartCapability::Ffi`] — the most
/// restrictive gate — so an unrecognized surface fails closed, never open.
pub fn required_capability(library: &str) -> DartCapability {
    match library {
        "ui" => DartCapability::Painting,
        "typed_data" => DartCapability::TypedData,
        "io" => DartCapability::Io,
        "isolate" => DartCapability::Isolate,
        "ffi" => DartCapability::Ffi,
        "core" | "async" | "math" | "convert" => DartCapability::Environment,
        _ => DartCapability::Ffi,
    }
}

/// Per-call resource accounting layered on top of the VM's own instruction and
/// memory limits. Tracks host-call count and bytes moved across the seam so a
/// runaway guest that stays under the instruction limit but floods the host with
/// allocations is still bounded.
#[derive(Debug, Clone)]
pub struct ResourceMeter {
    host_calls: u64,
    bytes_moved: u64,
    max_host_calls: Option<u64>,
    max_bytes_moved: Option<u64>,
}

impl ResourceMeter {
    pub fn new(max_host_calls: Option<u64>, max_bytes_moved: Option<u64>) -> Self {
        ResourceMeter {
            host_calls: 0,
            bytes_moved: 0,
            max_host_calls,
            max_bytes_moved,
        }
    }

    pub fn unbounded() -> Self {
        ResourceMeter::new(None, None)
    }

    pub fn host_calls(&self) -> u64 {
        self.host_calls
    }

    pub fn bytes_moved(&self) -> u64 {
        self.bytes_moved
    }

    /// Charge one host call moving `bytes`. Returns `Err` (which the runtime
    /// turns into a Dart error surfaced to the guest) if a limit is exceeded.
    pub fn charge(&mut self, bytes: u64) -> Result<(), String> {
        self.host_calls += 1;
        self.bytes_moved = self.bytes_moved.saturating_add(bytes);
        if let Some(max) = self.max_host_calls {
            if self.host_calls > max {
                return Err(format!("host-call limit exceeded ({max})"));
            }
        }
        if let Some(max) = self.max_bytes_moved {
            if self.bytes_moved > max {
                return Err(format!("host-byte limit exceeded ({max})"));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sandboxed_denies_native_and_io_but_allows_painting() {
        let caps = DartCapabilitySet::sandboxed();
        assert!(caps.allows(DartCapability::Painting));
        assert!(caps.allows(DartCapability::TypedData));
        assert!(!caps.allows(DartCapability::Io));
        assert!(!caps.allows(DartCapability::Ffi));
        assert!(!caps.allows(DartCapability::Isolate));
    }

    #[test]
    fn unknown_library_fails_closed_to_ffi_gate() {
        // An unrecognized dart:<lib> must require the most restrictive gate.
        assert_eq!(required_capability("something_new"), DartCapability::Ffi);
        assert_eq!(required_capability("ui"), DartCapability::Painting);
        assert_eq!(required_capability("io"), DartCapability::Io);
    }

    #[test]
    fn meter_enforces_call_ceiling() {
        let mut m = ResourceMeter::new(Some(2), None);
        assert!(m.charge(0).is_ok());
        assert!(m.charge(0).is_ok());
        assert!(m.charge(0).is_err());
    }

    #[test]
    fn meter_enforces_byte_ceiling() {
        let mut m = ResourceMeter::new(None, Some(10));
        assert!(m.charge(6).is_ok());
        assert!(m.charge(6).is_err());
    }
}
