//! `elpiand` — the Elpian mini-app host.
//!
//! Serves registered mini apps: their client bytecode to devices, and their
//! server functions to those clients.
//!
//! # Two ways a registry can be laid out
//!
//! **A content-addressed store**, written by `elpian-pkg install`:
//!
//! ```text
//! <registry>/index.json    apps, versions, which one is active
//! <registry>/blobs/<xx>/…  bytecode, addressed by its own hash
//! ```
//!
//! This is the one that supports versions, staged deploys and rollback, and
//! whose blobs are verified against their own addresses on read.
//!
//! **A plain directory**, which anyone can assemble by hand:
//!
//! ```text
//! <registry>/<app-id>/app.json
//! <registry>/<app-id>/client.bc
//! <registry>/<app-id>/fn/<name>.bc
//! ```
//!
//! Both are supported, and the store takes precedence when both are present.
//! The plain layout is kept because a host you cannot start without a packaging
//! tool is a host that is hard to debug — being able to drop three files in a
//! directory and see it serve is worth the second code path.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use elpian_host::app::{AppDefinition, FunctionKind, NetworkMode};
use elpian_host::registry::RegistryStore;
use elpian_host::runtime::AppRuntime;
use elpian_vm::api::{Capability, ResourceLimits};

struct Config {
    host: String,
    port: u16,
    registry: PathBuf,
    workers: usize,
    queue: Option<usize>,
    data_root: Option<PathBuf>,
    web_root: Option<PathBuf>,
    artifact_root: Option<PathBuf>,
    /// `{"<app>": {"<SECRET>": "value"}}` — the values of apps' declared
    /// secrets (provider keys among them).
    secrets: Option<PathBuf>,
    /// Development: a declared secret the host holds no value for is read
    /// from the environment (`elpian run dev` passes this).
    dev: bool,
}

fn main() {
    let config = match parse_args() {
        Ok(config) => config,
        Err(message) => {
            eprintln!("elpiand: {message}\n\n{}", usage());
            std::process::exit(2);
        }
    };

    elpian_vm::api::init_vm_system();

    let runtime = match &config.data_root {
        Some(root) => AppRuntime::with_data_root(root.clone()),
        None => AppRuntime::new(),
    };

    let registry_result = if config.registry.as_os_str().is_empty() {
        Ok(0)
    } else {
        load_registry(&config.registry, &runtime)
    };
    match registry_result {
        Ok(0) if config.registry.as_os_str().is_empty() => {}
        Ok(0) => eprintln!(
            "elpiand: warning: no apps found in {}",
            config.registry.display()
        ),
        Ok(count) => println!(
            "[elpian] loaded {count} app(s) from {}",
            config.registry.display()
        ),
        Err(message) => {
            eprintln!("elpiand: {message}");
            std::process::exit(1);
        }
    }

    if let Some(path) = &config.secrets {
        match load_secrets(path, &runtime) {
            Ok(count) => println!("[elpian] {count} secret value(s) from {}", path.display()),
            Err(message) => {
                eprintln!("elpiand: {message}");
                std::process::exit(1);
            }
        }
    }
    let settings = elpian_host::agents::AgentSettings::from_env(config.dev);
    if let Some(provider) = &settings.provider_override {
        println!("[elpian] agents run on the {provider} provider (ELPIAN_AGENT_PROVIDER)");
    }
    if config.dev {
        println!("[elpian] development: declared secrets fall back to the environment");
    }
    runtime.set_agent_settings(settings);

    let listener = match std::net::TcpListener::bind((config.host.as_str(), config.port)) {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!(
                "elpiand: cannot bind {}:{}: {error}",
                config.host, config.port
            );
            std::process::exit(1);
        }
    };
    let addr = listener.local_addr().expect("bound");
    println!("[elpian] host listening on http://{addr}");
    for id in runtime.app_ids() {
        println!("[elpian]   /apps/{id}/manifest.json");
        if let Some(agents) = runtime.app_definition(&id).and_then(|a| a.agents) {
            for name in agents.agents.keys() {
                println!("[elpian]   POST /apps/{id}/agent/{name}");
            }
        }
    }

    let queue = config
        .queue
        .unwrap_or(elpian_host::httpcore::DEFAULT_QUEUE_PER_WORKER * config.workers.max(1));
    println!("[elpian] {} workers, queue depth {queue}", config.workers);
    // Keep the pool tidy: park idle instances, then unload ones that stayed
    // idle. Without this both are implemented and nothing calls them, so an
    // instance nothing has asked for holds memory until the process exits.
    let maintenance = elpian_host::pool::PoolMaintenance::start(
        Arc::clone(runtime.pool()),
        elpian_host::pool::PoolConfig::default(),
    );
    std::mem::forget(maintenance);

    let mut gateway = elpian_host::gateway::Gateway::new(Arc::clone(&runtime));
    if let Some(data_root) = &config.data_root {
        // The trail lives beside the data it describes, so moving one moves the
        // other.
        gateway.audit = elpian_host::identity::AdminAudit::persisted(
            1000,
            data_root.join("admin-audit.ndjson"),
        );
    }
    if let Some(web_root) = &config.web_root {
        println!(
            "[elpian] serving {} for unclaimed paths",
            web_root.display()
        );
        gateway = gateway.with_web_root(web_root.clone());
    }
    if let Some(artifact_root) = &config.artifact_root {
        println!(
            "[elpian] serving {} under /__elpian/",
            artifact_root.display()
        );
        gateway = gateway.with_artifact_root(artifact_root.clone());
    }
    let handle = elpian_host::httpcore::serve_with_queue(
        listener,
        config.workers,
        queue,
        elpian_host::gateway::gateway_handler(Arc::new(gateway)),
    );

    // The accept loop owns the process from here.
    std::mem::forget(handle);
    loop {
        std::thread::park();
    }
}

fn usage() -> String {
    "usage: elpiand --registry <dir> [--host H] [--port P] [--workers N] [--queue N]\n  \
                [--data-root DIR] [--web-root DIR] [--artifact-root DIR]\n  \
                [--secrets FILE] [--dev]"
        .into()
}

fn parse_args() -> Result<Config, String> {
    let mut config = Config {
        host: "127.0.0.1".into(),
        port: 4180,
        registry: PathBuf::new(),
        workers: std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4),
        queue: None,
        data_root: None,
        web_root: None,
        artifact_root: None,
        secrets: None,
        dev: false,
    };
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--dev" {
            config.dev = true;
            i += 1;
            continue;
        }
        let value = args
            .get(i + 1)
            .ok_or_else(|| format!("{} needs a value", args[i]))?;
        match args[i].as_str() {
            "--host" => config.host = value.clone(),
            "--port" => config.port = value.parse().map_err(|_| "invalid port".to_string())?,
            "--registry" => config.registry = PathBuf::from(value),
            "--workers" => {
                config.workers = value
                    .parse()
                    .map_err(|_| "invalid worker count".to_string())?
            }
            "--queue" => {
                config.queue = Some(
                    value
                        .parse()
                        .map_err(|_| "invalid queue depth".to_string())?,
                )
            }
            "--data-root" => config.data_root = Some(PathBuf::from(value)),
            "--web-root" => config.web_root = Some(PathBuf::from(value)),
            "--artifact-root" => config.artifact_root = Some(PathBuf::from(value)),
            "--secrets" => config.secrets = Some(PathBuf::from(value)),
            flag => return Err(format!("unknown flag {flag}")),
        }
        i += 2;
    }
    // A host with only a web root is a development server, which is a
    // legitimate way to run this and should not need a registry that has no
    // apps in it yet.
    if config.registry.as_os_str().is_empty() && config.web_root.is_none() {
        return Err("--registry or --web-root is required".into());
    }
    if !config.registry.as_os_str().is_empty() && !config.registry.is_dir() {
        return Err(format!("{} is not a directory", config.registry.display()));
    }
    if let Some(web_root) = &config.web_root {
        if !web_root.is_dir() {
            return Err(format!("{} is not a directory", web_root.display()));
        }
    }
    Ok(config)
}

fn load_registry(root: &Path, runtime: &Arc<AppRuntime>) -> Result<usize, String> {
    // A content-addressed store, if there is one.
    if root.join("index.json").is_file() {
        return load_store(root, runtime);
    }
    load_plain_directory(root, runtime)
}

/// Load the *deployed* version of every app in a content-addressed store.
///
/// An app with versions installed but none deployed is skipped with a
/// diagnostic rather than having one picked for it — "install" and "deploy" are
/// separate verbs precisely so an operator can stage a version and cut over
/// deliberately, and guessing here would take that back.
fn load_store(root: &Path, runtime: &Arc<AppRuntime>) -> Result<usize, String> {
    let store = RegistryStore::open(root).map_err(|e| e.message())?;
    let mut loaded = 0;
    for id in store.app_ids() {
        let Some(active) = store.active_version(&id) else {
            eprintln!("elpiand: {id} has no deployed version; skipping");
            continue;
        };
        match elpian_host::registry::definition_from(&store, &id, &active) {
            Ok(app) => {
                if runtime.register(app) {
                    println!("[elpian]   {id} {} (from the store)", active.version);
                    loaded += 1;
                } else {
                    eprintln!("elpiand: skipping {id:?}: not a valid app id");
                }
            }
            // One app whose blob is missing or corrupt must not stop the host
            // serving the rest.
            Err(error) => eprintln!("elpiand: skipping {id}: {}", error.message()),
        }
    }
    Ok(loaded)
}

fn load_plain_directory(root: &Path, runtime: &Arc<AppRuntime>) -> Result<usize, String> {
    // A build output (`elpian run build` / `dev`) is itself one app: its
    // manifest is `elpian.app.json` at the top.
    if root.join("elpian.app.json").is_file() && !root.join("app.json").is_file() {
        let app = load_app(root).map_err(|m| format!("{}: {m}", root.display()))?;
        let id = app.id.clone();
        if !runtime.register(app) {
            return Err(format!("{id:?} is not a valid app id"));
        }
        return Ok(1);
    }
    let mut loaded = 0;
    let entries = std::fs::read_dir(root).map_err(|e| format!("{}: {e}", root.display()))?;
    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }
        match load_app(&dir) {
            Ok(app) => {
                let id = app.id.clone();
                if runtime.register(app) {
                    loaded += 1;
                } else {
                    eprintln!("elpiand: skipping {id:?}: not a valid app id");
                }
            }
            // One malformed app must not stop the host from serving the rest:
            // a registry is a shared surface and a bad entry is an operational
            // problem for that app, not for every other tenant.
            Err(message) => eprintln!("elpiand: skipping {}: {message}", dir.display()),
        }
    }
    Ok(loaded)
}

fn load_app(dir: &Path) -> Result<AppDefinition, String> {
    let manifest_path = if dir.join("app.json").is_file() {
        dir.join("app.json")
    } else {
        dir.join("elpian.app.json")
    };
    let raw = std::fs::read_to_string(&manifest_path)
        .map_err(|e| format!("{}: {e}", manifest_path.display()))?;
    let manifest: serde_json::Value =
        serde_json::from_str(&raw).map_err(|e| format!("app.json is not valid JSON: {e}"))?;

    let id = manifest
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or("app.json has no \"id\"")?
        .to_string();

    let mut app = AppDefinition::new(id);

    if let Some(caps) = manifest.get("capabilities").and_then(|v| v.as_array()) {
        // An unknown capability name is dropped rather than rejected: a
        // manifest written against a newer host must still load on an older
        // one, and dropping fails closed.
        let parsed: Vec<Capability> = caps
            .iter()
            .filter_map(|v| v.as_str())
            .filter_map(Capability::from_str)
            .collect();
        app = app.with_capabilities(parsed);
    }

    if let Some(secrets) = manifest.get("secrets").and_then(|v| v.as_array()) {
        app = app.with_secrets(
            secrets
                .iter()
                .filter_map(|v| v.as_str())
                .map(str::to_string)
                .collect(),
        );
    }

    app = app.with_network(parse_network(manifest.get("network")));
    app = app.with_limits(parse_limits(manifest.get("limits")));

    let client = dir.join("client.bc");
    if client.is_file() {
        app = app.with_client(std::fs::read(&client).map_err(|e| format!("client.bc: {e}"))?);
    }

    // The function table is derived from the manifest, and each entry must have
    // a module on disk. A manifest naming a function with no bytecode is an
    // error rather than a silently missing route.
    let declared = manifest
        .get("functions")
        .and_then(|v| v.as_array())
        .ok_or("app.json has no \"functions\" array")?;
    for entry in declared {
        let name = entry
            .get("name")
            .and_then(|v| v.as_str())
            .ok_or("a function entry has no \"name\"")?;
        let kind = match entry.get("kind").and_then(|v| v.as_str()) {
            Some("component") => FunctionKind::Component,
            Some("action") | None => FunctionKind::Action,
            Some(other) => return Err(format!("{name}: unknown kind {other}")),
        };
        let module = dir.join("fn").join(format!("{name}.bc"));
        let bytecode = std::fs::read(&module).map_err(|e| format!("{}: {e}", module.display()))?;
        app = app.with_function(name, kind, bytecode);
    }

    // Function metadata, and the agents with their `agents/**` files. A
    // manifest error here skips the app like a missing module does.
    let files = elpian_host::agents::read_agent_files(dir)?;
    app = app.with_manifest(&manifest, files)?;

    Ok(app)
}

/// Load secret values: `{"<app>": {"<NAME>": "value"}}`. Only names an app
/// declares are ever readable by it; the rest are held and never served.
fn load_secrets(path: &Path, runtime: &Arc<AppRuntime>) -> Result<usize, String> {
    let raw = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let value: serde_json::Value = serde_json::from_str(&raw)
        .map_err(|e| format!("{}: not valid JSON: {e}", path.display()))?;
    let apps = value.as_object().ok_or_else(|| {
        format!(
            "{}: expected {{\"<app>\": {{\"<NAME>\": \"value\"}}}}",
            path.display()
        )
    })?;
    let mut count = 0;
    for (app, secrets) in apps {
        for (name, secret) in secrets.as_object().into_iter().flatten() {
            if let Some(secret) = secret.as_str() {
                runtime.secrets().put(app, name, secret.to_string());
                count += 1;
            }
        }
    }
    Ok(count)
}

fn parse_network(value: Option<&serde_json::Value>) -> NetworkMode {
    match value {
        Some(serde_json::Value::String(s)) if s == "open" => NetworkMode::Open,
        Some(serde_json::Value::Object(map)) => {
            let allowlist = map
                .get("allow")
                .and_then(|v| v.as_array())
                .map(|items| {
                    items
                        .iter()
                        .filter_map(|v| v.as_str())
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default();
            NetworkMode::Brokered { allowlist }
        }
        // Anything unrecognised, including absent, is closed. The default has
        // to be the safe one: an app whose network stanza was mistyped must not
        // silently get egress.
        _ => NetworkMode::Closed,
    }
}

fn parse_limits(value: Option<&serde_json::Value>) -> ResourceLimits {
    let mut limits = ResourceLimits::unlimited();
    let Some(map) = value.and_then(|v| v.as_object()) else {
        return limits;
    };
    if let Some(v) = map.get("instructions").and_then(|v| v.as_u64()) {
        limits.max_instructions = Some(v);
    }
    if let Some(v) = map.get("instructionsPerTurn").and_then(|v| v.as_u64()) {
        limits.max_instructions_per_turn = Some(v);
    }
    if let Some(v) = map.get("memoryBytes").and_then(|v| v.as_u64()) {
        limits.max_memory_bytes = Some(v);
    }
    if let Some(v) = map.get("storageBytes").and_then(|v| v.as_u64()) {
        limits.max_storage_bytes = Some(v);
    }
    if let Some(v) = map.get("callDepth").and_then(|v| v.as_u64()) {
        limits.max_call_depth = Some(v);
    }
    limits
}
