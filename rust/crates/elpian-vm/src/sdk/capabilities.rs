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
// `Ord` is derived so capability sets can live in a `BTreeSet` and iterate
// deterministically. For a fieldless enum the ordering is declaration order,
// which is stable across runs — that matters because these sets are written
// into manifests and package indexes that must rebuild byte-identically.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
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
    /// Reading and mutating the host's document tree (`dom.*`).
    Dom,
    /// The 2D drawing surface (`canvas.*`).
    Canvas,
    /// Submitting a UI tree to the host renderer (`render`, `updateApp`).
    Render,
    /// Scheduling deferred work on the host clock (`setTimeout`, `setInterval`,
    /// `clearTimeout`, `clearInterval`). Separate from [`Capability::Clock`]:
    /// reading the time and being able to schedule against it are different
    /// grants.
    Timers,
    /// Reading the host environment (`env.get`) — viewport, locale, platform.
    Environment,
    /// Offloading guest compute onto the host's worker pool (`task.*`). Its own
    /// gate because it spends host threads, not just guest instructions.
    Tasks,
    /// The embedder-defined message pipe (`host.send`, `host.request`).
    HostMessaging,
    /// The host's drawing surface: the op seams a guest submits UI through
    /// (`godot.*`, `flutter.*`). One gate for both because they speak the same
    /// op vocabulary and a mini app that may draw at all may draw on whichever
    /// surface its host provides.
    Surface,
    /// Calling this mini app's *own* server functions (`server.*`).
    ///
    /// Its own gate, separate from [`Capability::Network`], because the two
    /// answer different questions. A mini app in a closed network posture holds
    /// no `Network` at all and still needs to reach its own backend: that pair
    /// — may talk to my server, may not talk to anything else — is the whole
    /// point of the closed cycle, and it is not expressible with one gate.
    ServerCall,
    /// Durable per-app key/value state (`kv.*`) and the declared secrets a
    /// server function may read (`secret.get`).
    ///
    /// Separate from [`Capability::Storage`], which is the fabricated
    /// filesystem: a server function is routinely given state without being
    /// given a filesystem.
    State,
    /// Any host API not mapped to a more specific capability.
    Other,
}

impl Capability {
    /// Map a host-API name to the capability that gates it.
    ///
    /// Family prefixes (`gpu.`, `net.`, `fs.`, `time.`, `random.`, `dom.`,
    /// `canvas.`, `task.`, `host.`) are matched so new APIs in a family inherit
    /// the right gate automatically. The handful of unprefixed legacy names the
    /// Flutter engine speaks are mapped individually.
    ///
    /// Every name the host actually serves should land on a specific gate.
    /// [`Capability::Other`] is the fail-safe for anything unrecognised, not a
    /// bucket to park real APIs in: when `dom.*`, `canvas.*`, `render` and the
    /// timers all shared it, a host could not deny a mini app the document tree
    /// without also denying it rendering and timers, which made the gate
    /// unusable in practice.
    pub fn for_api(api_name: &str) -> Capability {
        match api_name {
            // Unprefixed legacy names from the Flutter engine surface.
            "log" | "println" => Capability::Logging,
            "render" | "updateApp" => Capability::Render,
            "env.get" => Capability::Environment,
            "setTimeout" | "setInterval" | "clearTimeout" | "clearInterval" => Capability::Timers,
            "vm.import" => Capability::ModuleImport,
            _ => match api_name.split('.').next() {
                Some("gpu") => Capability::Gpu,
                Some("net") => Capability::Network,
                Some("fs") => Capability::Storage,
                Some("time") => Capability::Clock,
                Some("random") => Capability::Randomness,
                Some("vm") => Capability::VmManage,
                Some("godot") | Some("flutter") => Capability::Surface,
                Some("dom") => Capability::Dom,
                Some("canvas") => Capability::Canvas,
                Some("task") => Capability::Tasks,
                Some("host") => Capability::HostMessaging,
                Some("server") | Some("stream") => Capability::ServerCall,
                Some("kv") | Some("secret") | Some("cache") | Some("ctx") => Capability::State,
                // `stringify` and anything the host adds without a family.
                _ => Capability::Other,
            },
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
            Capability::Dom => "dom",
            Capability::Canvas => "canvas",
            Capability::Render => "render",
            Capability::Timers => "timers",
            Capability::Environment => "environment",
            Capability::Tasks => "tasks",
            Capability::HostMessaging => "host_messaging",
            Capability::Surface => "surface",
            Capability::ServerCall => "server_call",
            Capability::State => "state",
            Capability::Other => "other",
        }
    }

    /// Parse a capability from its stable name (host config ingestion).
    ///
    /// Deliberately an inherent `Option`-returning method rather than a
    /// `FromStr` impl: an unknown capability name is an ordinary "not one of
    /// ours" answer for a host reading config, not an error worth a type.
    #[allow(clippy::should_implement_trait)]
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
            "dom" => Capability::Dom,
            "canvas" => Capability::Canvas,
            "render" => Capability::Render,
            "timers" => Capability::Timers,
            "environment" => Capability::Environment,
            "tasks" => Capability::Tasks,
            "host_messaging" => Capability::HostMessaging,
            "surface" => Capability::Surface,
            "server_call" => Capability::ServerCall,
            "state" => Capability::State,
            "other" => Capability::Other,
            _ => return None,
        })
    }

    /// Every capability, for enumeration / bulk toggling.
    pub fn all() -> [Capability; 19] {
        [
            Capability::Logging,
            Capability::Gpu,
            Capability::ModuleImport,
            Capability::Network,
            Capability::Storage,
            Capability::Clock,
            Capability::Randomness,
            Capability::VmManage,
            Capability::Dom,
            Capability::Canvas,
            Capability::Render,
            Capability::Timers,
            Capability::Environment,
            Capability::Tasks,
            Capability::HostMessaging,
            Capability::Surface,
            Capability::ServerCall,
            Capability::State,
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
        CapabilitySet {
            overrides: HashMap::new(),
            default_allow: true,
        }
    }
}

impl CapabilitySet {
    /// All capabilities permitted unless explicitly revoked.
    pub fn allow_all() -> Self {
        CapabilitySet {
            overrides: HashMap::new(),
            default_allow: true,
        }
    }

    /// All capabilities denied unless explicitly granted. The starting point
    /// for sandboxing untrusted guests.
    pub fn deny_all() -> Self {
        CapabilitySet {
            overrides: HashMap::new(),
            default_allow: false,
        }
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
        self.overrides
            .get(&cap)
            .copied()
            .unwrap_or(self.default_allow)
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
    fn the_flutter_engine_surface_is_individually_gateable() {
        // The point of splitting `Other`: a host must be able to deny the
        // document tree without also denying rendering, timers or the clock.
        let mut caps = CapabilitySet::allow_all();
        caps.revoke(Capability::Dom);

        assert!(!caps.allows_api("dom.querySelector"));
        assert!(!caps.allows_api("dom.setStyle"));
        assert!(caps.allows_api("canvas.ctx.create"));
        assert!(caps.allows_api("render"));
        assert!(caps.allows_api("setTimeout"));
        assert!(caps.allows_api("env.get"));
    }

    #[test]
    fn engine_surface_names_map_to_specific_gates() {
        assert_eq!(Capability::for_api("dom.appendChild"), Capability::Dom);
        assert_eq!(Capability::for_api("canvas.ctx.fill"), Capability::Canvas);
        assert_eq!(Capability::for_api("render"), Capability::Render);
        assert_eq!(Capability::for_api("updateApp"), Capability::Render);
        assert_eq!(Capability::for_api("setTimeout"), Capability::Timers);
        assert_eq!(Capability::for_api("clearInterval"), Capability::Timers);
        assert_eq!(Capability::for_api("env.get"), Capability::Environment);
        assert_eq!(Capability::for_api("task.spawn"), Capability::Tasks);
        assert_eq!(Capability::for_api("host.send"), Capability::HostMessaging);
        // `println` is diagnostic output, the same class of effect as `log`.
        assert_eq!(Capability::for_api("println"), Capability::Logging);
        // `Other` stays the fail-safe for genuinely unrecognised names.
        assert_eq!(Capability::for_api("stringify"), Capability::Other);
        assert_eq!(Capability::for_api("something_new"), Capability::Other);
    }

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
        assert!(
            caps.allows_api("gpu.submit"),
            "other capabilities unaffected"
        );
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
