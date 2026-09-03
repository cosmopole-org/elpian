//! The registry: what apps exist, at what versions, and where their bytecode
//! lives.
//!
//! # Content addressing
//!
//! Every bytecode blob is stored under `sha256:<hex>` of its own bytes. Three
//! things follow, and all three matter:
//!
//! * **Deduplication is free.** Two versions of an app that changed one
//!   function share every other function's blob, so a rollback target costs
//!   almost nothing to keep.
//! * **Verification is trivial.** A device fetching a blob is told the hash by
//!   the manifest and can check what it received. A registry that served the
//!   wrong bytes gets caught by the client, not trusted by it.
//! * **A write is idempotent.** Storing a blob that is already there is a
//!   no-op, so a half-finished install can simply be repeated.
//!
//! # The index is swapped, never edited in place
//!
//! `index.json` is written to a temporary file, flushed, and renamed over the
//! old one. A crash therefore leaves either the old index or the new one —
//! never half of one. Editing in place would leave a registry that cannot be
//! read at all, which takes down every app on the host rather than the one
//! being deployed.

use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

use serde_json::{json, Value};

/// A version of an app, as recorded in the index.
#[derive(Debug, Clone, PartialEq)]
pub struct VersionRecord {
    pub version: String,
    /// Content address of the client half, if it has one.
    pub client: Option<String>,
    /// Function name → `(kind, content address)`.
    pub functions: BTreeMap<String, (String, String)>,
    pub capabilities: Vec<String>,
    pub secrets: Vec<String>,
    pub network: Value,
    pub limits: Value,
    /// When this version was installed, in milliseconds since the epoch.
    pub installed_at: u64,
}

/// One app's entry.
#[derive(Debug, Clone, PartialEq)]
pub struct AppRecord {
    pub id: String,
    /// Which version is currently served. `None` while an app is installed but
    /// not yet deployed — an operator can stage a version and cut over
    /// separately.
    pub active: Option<String>,
    pub versions: BTreeMap<String, VersionRecord>,
}

/// Why a registry operation failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegistryError {
    Io(String),
    /// A blob's bytes did not hash to the address it was stored under.
    Corrupt { address: String },
    UnknownApp(String),
    UnknownVersion { app: String, version: String },
    /// Deploying a version older than the one already active.
    Downgrade { app: String, from: String, to: String },
    /// The index on disk is not something this host can read.
    MalformedIndex(String),
}

impl RegistryError {
    pub fn message(&self) -> String {
        match self {
            RegistryError::Io(e) => format!("registry io: {e}"),
            RegistryError::Corrupt { address } => {
                format!("blob {address} does not match its content address")
            }
            RegistryError::UnknownApp(app) => format!("no such app: {app}"),
            RegistryError::UnknownVersion { app, version } => {
                format!("{app} has no version {version}")
            }
            RegistryError::Downgrade { app, from, to } => {
                format!("{app} is at {from}; refusing to deploy older {to}")
            }
            RegistryError::MalformedIndex(e) => format!("registry index is unreadable: {e}"),
        }
    }
}

/// The on-disk registry.
pub struct RegistryStore {
    root: PathBuf,
    index: RwLock<BTreeMap<String, AppRecord>>,
}

impl RegistryStore {
    /// Open (or create) a registry at `root`.
    pub fn open(root: impl Into<PathBuf>) -> Result<RegistryStore, RegistryError> {
        let root = root.into();
        std::fs::create_dir_all(root.join("blobs"))
            .map_err(|e| RegistryError::Io(e.to_string()))?;

        let index = match std::fs::read_to_string(root.join("index.json")) {
            Ok(raw) => parse_index(&raw)?,
            // A registry that has never been written is empty, not broken.
            Err(_) => BTreeMap::new(),
        };

        Ok(RegistryStore {
            root,
            index: RwLock::new(index),
        })
    }

    fn blob_path(&self, address: &str) -> PathBuf {
        // Split on the first two hex characters, so a registry with a hundred
        // thousand blobs is not one directory with a hundred thousand entries —
        // which some filesystems handle badly and every `ls` handles badly.
        let hex = address.strip_prefix("sha256:").unwrap_or(address);
        let (prefix, rest) = hex.split_at(2.min(hex.len()));
        self.root.join("blobs").join(prefix).join(rest)
    }

    /// Store a blob and return its content address. Idempotent.
    pub fn put_blob(&self, data: &[u8]) -> Result<String, RegistryError> {
        let address = elpian_crypto::content_address(data);
        let path = self.blob_path(&address);
        if path.exists() {
            // Already there, and its name is its hash — so it is already the
            // right bytes. Nothing to do.
            return Ok(address);
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| RegistryError::Io(e.to_string()))?;
        }
        write_atomically(&path, data)?;
        Ok(address)
    }

    /// Read a blob, verifying it against its own address.
    ///
    /// The check is not paranoia about the disk: it is what makes a registry
    /// safe to serve from after a partial write, a bad restore, or a filesystem
    /// that lost a page. Serving bytecode that is not what was installed is the
    /// worst failure this component has.
    pub fn get_blob(&self, address: &str) -> Result<Vec<u8>, RegistryError> {
        let data = std::fs::read(self.blob_path(address))
            .map_err(|e| RegistryError::Io(e.to_string()))?;
        if elpian_crypto::content_address(&data) != address {
            return Err(RegistryError::Corrupt {
                address: address.to_string(),
            });
        }
        Ok(data)
    }

    /// Install a version. Does not make it active — see [`RegistryStore::deploy`].
    pub fn install(&self, app_id: &str, record: VersionRecord) -> Result<(), RegistryError> {
        {
            let mut index = self.write_index();
            let app = index
                .entry(app_id.to_string())
                .or_insert_with(|| AppRecord {
                    id: app_id.to_string(),
                    active: None,
                    versions: BTreeMap::new(),
                });
            app.versions.insert(record.version.clone(), record);
        }
        self.persist()
    }

    /// Make a version the one that is served.
    ///
    /// Refuses to go backwards unless `force`. An accidental redeploy of an old
    /// artifact is a common and expensive mistake, and the registry is the last
    /// place that can notice it — by the time it is serving, it is live.
    pub fn deploy(&self, app_id: &str, version: &str, force: bool) -> Result<(), RegistryError> {
        {
            let mut index = self.write_index();
            let app = index
                .get_mut(app_id)
                .ok_or_else(|| RegistryError::UnknownApp(app_id.to_string()))?;
            if !app.versions.contains_key(version) {
                return Err(RegistryError::UnknownVersion {
                    app: app_id.to_string(),
                    version: version.to_string(),
                });
            }
            if let Some(active) = &app.active {
                if !force && compare_versions(version, active) == std::cmp::Ordering::Less {
                    return Err(RegistryError::Downgrade {
                        app: app_id.to_string(),
                        from: active.clone(),
                        to: version.to_string(),
                    });
                }
            }
            app.active = Some(version.to_string());
        }
        self.persist()
    }

    /// Remove a version. The active one cannot be removed — that would leave
    /// the app pointing at nothing, which is worse than keeping a version
    /// somebody wanted gone.
    pub fn remove_version(&self, app_id: &str, version: &str) -> Result<(), RegistryError> {
        {
            let mut index = self.write_index();
            let app = index
                .get_mut(app_id)
                .ok_or_else(|| RegistryError::UnknownApp(app_id.to_string()))?;
            if app.active.as_deref() == Some(version) {
                return Err(RegistryError::Downgrade {
                    app: app_id.to_string(),
                    from: version.to_string(),
                    to: "(removal of the active version)".into(),
                });
            }
            if app.versions.remove(version).is_none() {
                return Err(RegistryError::UnknownVersion {
                    app: app_id.to_string(),
                    version: version.to_string(),
                });
            }
        }
        self.persist()
    }

    pub fn app(&self, app_id: &str) -> Option<AppRecord> {
        self.read_index().get(app_id).cloned()
    }

    /// The version currently served for an app.
    pub fn active_version(&self, app_id: &str) -> Option<VersionRecord> {
        let index = self.read_index();
        let app = index.get(app_id)?;
        let active = app.active.as_ref()?;
        app.versions.get(active).cloned()
    }

    pub fn app_ids(&self) -> Vec<String> {
        self.read_index().keys().cloned().collect()
    }

    fn read_index(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, AppRecord>> {
        self.index.read().unwrap_or_else(|p| p.into_inner())
    }

    fn write_index(&self) -> std::sync::RwLockWriteGuard<'_, BTreeMap<String, AppRecord>> {
        self.index.write().unwrap_or_else(|p| p.into_inner())
    }

    /// Write the index out, atomically.
    fn persist(&self) -> Result<(), RegistryError> {
        let rendered = render_index(&self.read_index());
        write_atomically(&self.root.join("index.json"), rendered.as_bytes())
    }
}

/// Write `data` to `path` by writing a temporary file, flushing it, and
/// renaming it over the target.
///
/// The rename is what makes this atomic on every filesystem that matters: a
/// reader sees either the whole old file or the whole new one. Writing in place
/// leaves a window where the file is truncated, and for the index that window
/// takes down every app on the host.
fn write_atomically(path: &Path, data: &[u8]) -> Result<(), RegistryError> {
    let temp = path.with_extension(format!("tmp{}", std::process::id()));
    {
        let mut file =
            std::fs::File::create(&temp).map_err(|e| RegistryError::Io(e.to_string()))?;
        file.write_all(data)
            .map_err(|e| RegistryError::Io(e.to_string()))?;
        // Flush to the device, not just out of the process buffer: a rename
        // that lands before the data does leaves a valid name over empty
        // content, which is the failure this whole dance exists to avoid.
        file.sync_all().map_err(|e| RegistryError::Io(e.to_string()))?;
    }
    std::fs::rename(&temp, path).map_err(|e| RegistryError::Io(e.to_string()))
}

fn render_index(index: &BTreeMap<String, AppRecord>) -> String {
    let apps: Vec<Value> = index
        .values()
        .map(|app| {
            let versions: Vec<Value> = app
                .versions
                .values()
                .map(|v| {
                    let functions: Vec<Value> = v
                        .functions
                        .iter()
                        .map(|(name, (kind, address))| {
                            json!({ "name": name, "kind": kind, "blob": address })
                        })
                        .collect();
                    json!({
                        "version": v.version,
                        "client": v.client,
                        "functions": functions,
                        "capabilities": v.capabilities,
                        "secrets": v.secrets,
                        "network": v.network,
                        "limits": v.limits,
                        "installedAt": v.installed_at,
                    })
                })
                .collect();
            json!({ "id": app.id, "active": app.active, "versions": versions })
        })
        .collect();

    // Pretty-printed and key-ordered (BTreeMap) so a registry is diffable and
    // an operator can read what changed between two deploys.
    serde_json::to_string_pretty(&json!({ "schema": 1, "apps": apps }))
        .unwrap_or_else(|_| "{}".into())
}

fn parse_index(raw: &str) -> Result<BTreeMap<String, AppRecord>, RegistryError> {
    let value: Value =
        serde_json::from_str(raw).map_err(|e| RegistryError::MalformedIndex(e.to_string()))?;
    let mut out = BTreeMap::new();

    let apps = value["apps"]
        .as_array()
        .ok_or_else(|| RegistryError::MalformedIndex("no apps array".into()))?;

    for app in apps {
        let id = app["id"]
            .as_str()
            .ok_or_else(|| RegistryError::MalformedIndex("an app has no id".into()))?
            .to_string();
        let mut versions = BTreeMap::new();
        for v in app["versions"].as_array().unwrap_or(&Vec::new()) {
            let version = v["version"].as_str().unwrap_or_default().to_string();
            let mut functions = BTreeMap::new();
            for f in v["functions"].as_array().unwrap_or(&Vec::new()) {
                let (Some(name), Some(blob)) = (f["name"].as_str(), f["blob"].as_str()) else {
                    continue;
                };
                functions.insert(
                    name.to_string(),
                    (
                        f["kind"].as_str().unwrap_or("action").to_string(),
                        blob.to_string(),
                    ),
                );
            }
            versions.insert(
                version.clone(),
                VersionRecord {
                    version,
                    client: v["client"].as_str().map(str::to_string),
                    functions,
                    capabilities: v["capabilities"]
                        .as_array()
                        .map(|a| {
                            a.iter()
                                .filter_map(Value::as_str)
                                .map(str::to_string)
                                .collect()
                        })
                        .unwrap_or_default(),
                    secrets: v["secrets"]
                        .as_array()
                        .map(|a| {
                            a.iter()
                                .filter_map(Value::as_str)
                                .map(str::to_string)
                                .collect()
                        })
                        .unwrap_or_default(),
                    network: v["network"].clone(),
                    limits: v["limits"].clone(),
                    installed_at: v["installedAt"].as_u64().unwrap_or(0),
                },
            );
        }
        out.insert(
            id.clone(),
            AppRecord {
                id,
                active: app["active"].as_str().map(str::to_string),
                versions,
            },
        );
    }
    Ok(out)
}

/// Compare two dotted version strings numerically, segment by segment.
///
/// Not a full semver implementation — that would need prerelease and build
/// metadata rules nothing here uses yet. What it must get right is that `1.10.0`
/// is newer than `1.9.0`, which a string comparison gets backwards, and that is
/// the comparison the downgrade check depends on.
pub fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    let parse = |s: &str| -> Vec<u64> {
        s.split(['.', '-'])
            .map(|part| part.parse::<u64>().unwrap_or(0))
            .collect()
    };
    let (a, b) = (parse(a), parse(b));
    for i in 0..a.len().max(b.len()) {
        let (x, y) = (a.get(i).copied().unwrap_or(0), b.get(i).copied().unwrap_or(0));
        match x.cmp(&y) {
            std::cmp::Ordering::Equal => continue,
            other => return other,
        }
    }
    std::cmp::Ordering::Equal
}

/// Turn an installed version into a runnable [`AppDefinition`].
///
/// Kept here rather than on `AppDefinition` so the app model stays free of the
/// registry's storage concerns — a definition assembled in a test or by an
/// embedder should not have to know what a content address is.
pub fn definition_from(
    store: &RegistryStore,
    app_id: &str,
    record: &VersionRecord,
) -> Result<crate::app::AppDefinition, RegistryError> {
    use crate::app::{AppDefinition, FunctionKind, NetworkMode};
    use elpian_vm::api::{Capability, ResourceLimits};

    let mut app = AppDefinition::new(app_id);

    // Unknown capability names are dropped rather than rejected, matching the
    // manifest reader and the Dart side: an app installed against a newer host
    // must still load on an older one, and dropping can only narrow.
    app = app.with_capabilities(
        record
            .capabilities
            .iter()
            .filter_map(|name| Capability::from_str(name))
            .collect::<Vec<Capability>>(),
    );
    app = app.with_secrets(record.secrets.clone());
    app = app.with_network(network_from(&record.network));
    app = app.with_limits(limits_from(&record.limits));

    if let Some(address) = &record.client {
        // Reading through the store verifies the blob against its own address,
        // so a registry that lost a page serves nothing rather than serving
        // bytecode that is not what was installed.
        app = app.with_client(store.get_blob(address)?);
    }

    for (name, (kind, address)) in &record.functions {
        let kind = match kind.as_str() {
            "component" => FunctionKind::Component,
            _ => FunctionKind::Action,
        };
        app = app.with_function(name, kind, store.get_blob(address)?);
    }

    let _ = NetworkMode::Closed;
    let _: Option<ResourceLimits> = None;
    Ok(app)
}

fn network_from(value: &Value) -> crate::app::NetworkMode {
    use crate::app::NetworkMode;
    match value {
        Value::String(s) if s == "open" => NetworkMode::Open,
        Value::Object(map) => NetworkMode::Brokered {
            allowlist: map
                .get("allow")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default(),
        },
        // Anything unrecognised, including absent, is closed. The default has
        // to be the safe one.
        _ => NetworkMode::Closed,
    }
}

fn limits_from(value: &Value) -> elpian_vm::api::ResourceLimits {
    use elpian_vm::api::ResourceLimits;
    let mut limits = ResourceLimits::unlimited();
    let Some(map) = value.as_object() else {
        return limits;
    };
    limits.max_instructions = map.get("instructions").and_then(Value::as_u64);
    limits.max_instructions_per_turn = map.get("instructionsPerTurn").and_then(Value::as_u64);
    limits.max_memory_bytes = map.get("memoryBytes").and_then(Value::as_u64);
    limits.max_storage_bytes = map.get("storageBytes").and_then(Value::as_u64);
    limits.max_call_depth = map.get("callDepth").and_then(Value::as_u64);
    limits
}

/// Milliseconds since the epoch.
pub fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
