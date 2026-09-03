//! What "one mini app" is, on the server side.
//!
//! The previous server had no such object — it knew about a single bytecode
//! blob given on the command line. Every governance question ("what may this
//! app do", "how much may it spend", "which functions does it have") needs
//! something to be asked *of*, and this is it.

use std::collections::BTreeMap;

use elpian_vm::api::{Capability, ResourceLimits};

/// What a server function is for.
///
/// The distinction is not cosmetic: an action returns JSON to its caller, while
/// a component returns a UI payload that the host may cache and the client
/// renders natively. They are invoked through different host APIs
/// (`server.call` vs `server.render`) and a client asking for the wrong one is
/// an error rather than a coincidence that happens to work.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FunctionKind {
    /// Returns JSON. May write.
    Action,
    /// Returns a UI payload. Expected to be a pure function of its arguments
    /// and the app's state, which is what makes the result cacheable.
    Component,
}

impl FunctionKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            FunctionKind::Action => "action",
            FunctionKind::Component => "component",
        }
    }
}

/// One server function: a name, a kind, and its own bytecode module.
///
/// One module per function is what makes independent load and unload possible,
/// which is the entire serverless requirement. A single bundle for the whole
/// app would have to be resident whenever any one function was called.
#[derive(Debug, Clone)]
pub struct FunctionDef {
    pub name: String,
    pub kind: FunctionKind,
    pub bytecode: Vec<u8>,
    /// Whether this function must get a fresh instance every call.
    ///
    /// The default is reuse, which is what makes a warm pool worth having and
    /// what guest authors expect. But module-level state survives reuse, so a
    /// function that stashes anything derived from `ctx.user` in a module
    /// variable has a path by which one caller's data reaches another. Setting
    /// this is how such a function says so.
    pub stateless: bool,
}

/// Whether an app may reach anything beyond its own two halves.
///
/// The gate that implements this is [`Capability::Network`]; this enum is the
/// *policy* the host resolves into that gate, and it exists separately because
/// `brokered` and `open` both grant the capability while meaning different
/// things about what the broker will then allow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NetworkMode {
    /// No egress from either half. The client VM's only reachable peer is this
    /// app's own server functions, and those hold no network capability at all.
    /// The pair can talk to each other through the host and to nothing else.
    Closed,
    /// Egress only to the listed origins, through the host's broker.
    Brokered { allowlist: Vec<String> },
    /// Unrestricted egress. Appropriate for first-party code and nothing else.
    Open,
}

impl NetworkMode {
    /// Whether a server function of this app may hold [`Capability::Network`].
    pub fn grants_network(&self) -> bool {
        !matches!(self, NetworkMode::Closed)
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            NetworkMode::Closed => "closed",
            NetworkMode::Brokered { .. } => "brokered",
            NetworkMode::Open => "open",
        }
    }
}

/// A registered mini app's server half.
#[derive(Debug, Clone)]
pub struct AppDefinition {
    pub id: String,
    /// Sorted by name, so listings and manifests are deterministic.
    pub functions: BTreeMap<String, FunctionDef>,
    /// What the app was granted. Intersected with the server posture before it
    /// reaches any instance, so a grant here can only ever narrow.
    pub capabilities: Vec<Capability>,
    /// Per-instance resource budget.
    pub limits: ResourceLimits,
    /// Secret names a function of this app may read.
    pub declared_secrets: Vec<String>,
    pub network: NetworkMode,
    /// The client half's bytecode, served to a device that fetches the app.
    ///
    /// Held here rather than as a separate registration so an app is one
    /// object: a version whose client and server halves could be registered
    /// independently could be served with the two out of step.
    pub client_bytecode: Option<Vec<u8>>,
}

impl AppDefinition {
    pub fn new(id: impl Into<String>) -> Self {
        AppDefinition {
            id: id.into(),
            functions: BTreeMap::new(),
            capabilities: Vec::new(),
            limits: ResourceLimits::unlimited(),
            declared_secrets: Vec::new(),
            network: NetworkMode::Closed,
            client_bytecode: None,
        }
    }

    pub fn with_function(
        mut self,
        name: impl Into<String>,
        kind: FunctionKind,
        bytecode: Vec<u8>,
    ) -> Self {
        let name = name.into();
        self.functions.insert(
            name.clone(),
            FunctionDef {
                name,
                kind,
                bytecode,
                stateless: false,
            },
        );
        self
    }

    /// Mark an already-added function as needing a fresh instance per call.
    pub fn stateless(mut self, name: &str) -> Self {
        if let Some(f) = self.functions.get_mut(name) {
            f.stateless = true;
        }
        self
    }

    pub fn with_capabilities(mut self, caps: Vec<Capability>) -> Self {
        self.capabilities = caps;
        self
    }

    pub fn with_limits(mut self, limits: ResourceLimits) -> Self {
        self.limits = limits;
        self
    }

    pub fn with_secrets(mut self, names: Vec<String>) -> Self {
        self.declared_secrets = names;
        self
    }

    pub fn with_network(mut self, mode: NetworkMode) -> Self {
        self.network = mode;
        self
    }

    pub fn with_client(mut self, bytecode: Vec<u8>) -> Self {
        self.client_bytecode = Some(bytecode);
        self
    }

    /// What a client is told about this app: where to fetch its bytecode, what
    /// it may call, and the network posture it must apply locally.
    ///
    /// The posture is advertised so a well-behaved client can enforce it too —
    /// as a courtesy, never as the boundary. The server does not trust a client
    /// to apply it, which is why the same rule is enforced again on every call
    /// that arrives.
    pub fn client_manifest(&self) -> serde_json::Value {
        let functions: Vec<serde_json::Value> = self
            .functions
            .values()
            .map(|f| serde_json::json!({ "name": f.name, "kind": f.kind.as_str() }))
            .collect();
        serde_json::json!({
            "app": self.id,
            "client": format!("/apps/{}/client.bc", self.id),
            "functions": functions,
            "network": self.network.as_str(),
        })
    }

    /// The capabilities an instance of this app actually receives.
    ///
    /// Three narrowings, in order: what the app asked for, intersected with
    /// what a server function may ever hold, minus the network unless the app's
    /// mode grants it. The last is what makes `closed` mean something — an app
    /// in a closed posture does not hold the gate at all, so its egress is not
    /// "blocked by the broker", it is absent.
    pub fn effective_capabilities(&self) -> Vec<Capability> {
        self.capabilities
            .iter()
            .copied()
            .filter(|c| crate::posture::SERVER_GRANTABLE.contains(c))
            .filter(|c| *c != Capability::Network || self.network.grants_network())
            .collect()
    }

    pub fn function(&self, name: &str) -> Option<&FunctionDef> {
        self.functions.get(name)
    }
}
