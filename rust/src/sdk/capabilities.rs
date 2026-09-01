//! Togglable, host-controlled capabilities for an Elpian VM instance.
//!
//! Every side-effecting thing a guest can reach — logging, GPU submission,
//! module import, the network, the fabricated filesystem, the clock, the random
//! source — is a *capability*. The host can switch each one on or off at any
//! time between turns. When a guest performs an `askHost` whose capability is
//! disabled, the executor does **not** suspend to the host: it short-circuits
//! the call to a typed null, so a guest can keep running deterministically with
//! an interface "unplugged" rather than crashing.
//!
//! Capabilities are derived from the host-API name by [`Capability::for_api`],
//! so the policy is enforced at the single `askHost` seam and automatically
//! covers every present and future API in a family (`net.*`, `fs.*`, …).

use std::collections::HashMap;

/// A class of side effect a guest may be permitted to perform.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Capability {
    /// Diagnostic logging (`log`).
    Logging,
    /// GPU command submission and resource APIs (`gpu.*`).
    Gpu,
    /// Importing and running external Elpian modules (`vm.import`).
    ModuleImport,
    /// Outbound/inbound networking (`net.*`).
    Network,
    /// The fabricated filesystem (`fs.*`) — native disk or browser storage.
    Storage,
    /// Wall-clock / monotonic time (`time.*`).
    Clock,
    /// Non-deterministic randomness (`random.*` and the `random` builtin).
    Randomness,
    /// Managing other VM instances (`vm.*` except `vm.import`): spawning child
    /// VMs, steering their lifecycle, limits and permissions. The gate of the
    /// multi-VM tree: a VM without it cannot create or control children.
    VmManage,
    /// Any host API not mapped to a more specific capability.
    Other,
}

impl Capability {
    /// Map a host-API name to the capability that gates it. Family prefixes
    /// (`gpu.`, `net.`, `fs.`, `time.`, `random.`) are matched so new APIs in a
    /// family inherit the right gate automatically.
    pub fn for_api(api_name: &str) -> Capability {
        if api_name == "log" {
            Capability::Logging
        } else if api_name == "vm.import" {
            Capability::ModuleImport
        } else if let Some(family) = api_name.split('.').next() {
            match family {
                "gpu" => Capability::Gpu,
                "net" => Capability::Network,
                "fs" => Capability::Storage,
                "time" => Capability::Clock,
                "random" => Capability::Randomness,
                "vm" => Capability::VmManage,
                _ => Capability::Other,
            }
        } else {
            Capability::Other
        }
    }

    /// Stable machine-readable name (for host config and diagnostics).
    pub fn as_str(&self) -> &'static str {
        match self {
            Capability::Logging => "logging",
            Capability::Gpu => "gpu",
            Capability::ModuleImport => "module_import",
            Capability::Network => "network",
            Capability::Storage => "storage",
            Capability::Clock => "clock",
            Capability::Randomness => "randomness",
            Capability::VmManage => "vm_manage",
            Capability::Other => "other",
        }
    }

    /// Parse a capability from its stable name (host config ingestion).
    pub fn from_str(name: &str) -> Option<Capability> {
        Some(match name {
            "logging" => Capability::Logging,
            "gpu" => Capability::Gpu,
            "module_import" => Capability::ModuleImport,
            "network" => Capability::Network,
            "storage" => Capability::Storage,
            "clock" => Capability::Clock,
            "randomness" => Capability::Randomness,
            "vm_manage" => Capability::VmManage,
            "other" => Capability::Other,
            _ => return None,
        })
    }

    /// Every capability, for enumeration / bulk toggling.
    pub fn all() -> [Capability; 9] {
        [
            Capability::Logging,
            Capability::Gpu,
            Capability::ModuleImport,
            Capability::Network,
            Capability::Storage,
            Capability::Clock,
            Capability::Randomness,
            Capability::VmManage,
            Capability::Other,
        ]
    }
}

/// The host-owned on/off state for every capability. Any entry not present
/// falls back to the set's `default_allow`.
#[derive(Clone, Debug)]
pub struct CapabilitySet {
    overrides: HashMap<Capability, bool>,
    default_allow: bool,
}

impl Default for CapabilitySet {
    fn default() -> Self {
        // Default posture mirrors the historical VM: everything the embedder
        // wires up is reachable. Hosts running untrusted code start from
        // `deny_all()` and grant explicitly.
        CapabilitySet { overrides: HashMap::new(), default_allow: true }
    }
}

impl CapabilitySet {
    /// All capabilities permitted unless explicitly revoked.
    pub fn allow_all() -> Self {
        CapabilitySet { overrides: HashMap::new(), default_allow: true }
    }

    /// All capabilities denied unless explicitly granted. The starting point
    /// for sandboxing untrusted guests.
    pub fn deny_all() -> Self {
        CapabilitySet { overrides: HashMap::new(), default_allow: false }
    }

    /// Turn a single capability on or off. Takes effect on the next guest call.
    pub fn set(&mut self, cap: Capability, allowed: bool) {
        self.overrides.insert(cap, allowed);
    }

    /// Grant a capability.
    pub fn grant(&mut self, cap: Capability) {
        self.set(cap, true);
    }

    /// Revoke a capability.
    pub fn revoke(&mut self, cap: Capability) {
        self.set(cap, false);
    }

    /// Whether a capability is currently permitted.
    pub fn is_allowed(&self, cap: Capability) -> bool {
        self.overrides.get(&cap).copied().unwrap_or(self.default_allow)
    }

    /// Whether the host API named `api_name` is currently permitted, resolving
    /// it to its gating capability first.
    pub fn allows_api(&self, api_name: &str) -> bool {
        self.is_allowed(Capability::for_api(api_name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_names_map_to_capabilities() {
        assert_eq!(Capability::for_api("log"), Capability::Logging);
        assert_eq!(Capability::for_api("gpu.submit"), Capability::Gpu);
        assert_eq!(Capability::for_api("net.fetch"), Capability::Network);
        assert_eq!(Capability::for_api("fs.read"), Capability::Storage);
        assert_eq!(Capability::for_api("time.now"), Capability::Clock);
        assert_eq!(Capability::for_api("random.bytes"), Capability::Randomness);
        assert_eq!(Capability::for_api("vm.import"), Capability::ModuleImport);
        assert_eq!(Capability::for_api("vm.spawn"), Capability::VmManage);
        assert_eq!(Capability::for_api("vm.terminate"), Capability::VmManage);
        assert_eq!(Capability::for_api("weird"), Capability::Other);
    }

    #[test]
    fn allow_all_then_revoke_one() {
        let mut caps = CapabilitySet::allow_all();
        assert!(caps.allows_api("net.fetch"));
        caps.revoke(Capability::Network);
        assert!(!caps.allows_api("net.fetch"));
        assert!(caps.allows_api("gpu.submit"), "other capabilities unaffected");
    }

    #[test]
    fn deny_all_then_grant_one() {
        let mut caps = CapabilitySet::deny_all();
        assert!(!caps.allows_api("fs.read"));
        caps.grant(Capability::Storage);
        assert!(caps.allows_api("fs.write"));
        assert!(!caps.allows_api("net.fetch"));
    }

    #[test]
    fn names_round_trip() {
        for cap in Capability::all() {
            assert_eq!(Capability::from_str(cap.as_str()), Some(cap));
        }
    }
}
