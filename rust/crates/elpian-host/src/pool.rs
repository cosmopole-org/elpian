//! Loading function instances on demand, and unloading them when nothing needs
//! them.
//!
//! # What "serverless" means here
//!
//! Until now every call created a VM, ran it, and destroyed it — which re-ran
//! the function's *module initialisation* every time. For a module that builds
//! a lookup table or compiles a template at load time, that is the dominant
//! cost of the call and it is paid on every one.
//!
//! A warm instance skips it. The instance stays registered between calls, its
//! module-level state intact, and the next call for the same function runs
//! straight into the function body.
//!
//! # Warm instances keep state, and that is a decision
//!
//! Module-level state survives between invocations of a warm instance, the way
//! it does on every other serverless platform. It is fast and it is what guest
//! authors expect — and it is also a path by which one caller's data can reach
//! another, for any function that stashes something derived from `ctx.user` in
//! a module variable.
//!
//! So it is opt-out per function: [`FunctionDef::stateless`] gets a fresh
//! instance every call. The default is reuse because that is what makes the
//! pool worth having, but the trade is named here rather than discovered later.
//! (The maintainer question in `STATUS.md` is whether that default is the right
//! way round; both are one line from here.)
//!
//! # Eviction
//!
//! An instance nothing has called for `idle_ttl` is unloaded. A pool over
//! `max_instances` unloads its least recently used. Neither ever takes a
//! *busy* instance: an instance in the middle of a call is not idle however
//! long ago it last finished one.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use elpian_vm::api;

use crate::app::{AppDefinition, FunctionDef};
use crate::posture::server_capabilities;

/// The machine id of an app's supervisor node.
///
/// Every instance of an app is adopted under this node, which makes the VM
/// tree's existing machinery apply to a *whole app* rather than to one
/// instance: `subtree_usage` gives the app's real total across every function,
/// `enforce_tree_budgets` can take down a runaway app as a unit, permission
/// intersection means a function can never hold more than its app holds, and
/// `destroy_vm_tree` unloads the app in one call.
///
/// None of that is new code. It is the client's governance machinery, pointed
/// at a server — which is the whole reason the tree was worth having.
fn supervisor_id(app: &str) -> String {
    format!("app::{app}")
}

/// How the pool is bounded.
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// How long an instance may sit idle before it is unloaded.
    pub idle_ttl: Duration,
    /// How long an instance may sit idle before it is *hibernated*.
    ///
    /// Shorter than [`PoolConfig::idle_ttl`], so an instance parks first and is
    /// unloaded later if it stays quiet. `None` disables hibernation and every
    /// idle instance simply waits to be evicted.
    ///
    /// Hibernating is `pause_vm`: the executor's whole continuation is
    /// preserved and it consumes no CPU. Waking it costs nothing but clearing
    /// the flag, so the next call skips module initialisation exactly as a warm
    /// instance does — which is the point. An app that goes quiet between
    /// bursts otherwise pays a cold start on every burst.
    pub hibernate_after: Option<Duration>,
    /// The most instances the whole host will hold warm.
    pub max_instances: usize,
    /// The most warm instances any one function may hold, so a single hot
    /// function cannot evict every other app's.
    pub max_per_function: usize,
}

impl Default for PoolConfig {
    fn default() -> Self {
        PoolConfig {
            idle_ttl: Duration::from_secs(300),
            hibernate_after: Some(Duration::from_secs(30)),
            max_instances: 256,
            max_per_function: 8,
        }
    }
}

/// Counters the host keeps per app. The repository's governance chapter said
/// outright that cost metering did not exist; this is where it starts.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Meters {
    pub invocations: u64,
    pub cold_starts: u64,
    /// Guest instructions executed, summed across invocations.
    pub instructions: u64,
    /// Wall-clock milliseconds spent inside guest turns.
    pub compute_ms: u64,
    /// Peak live guest memory observed, in bytes. A peak rather than a sum
    /// because memory is a *level*, and adding levels together measures nothing.
    pub peak_memory_bytes: u64,
    /// Bytes the app's state store holds.
    pub storage_bytes: u64,
}

#[derive(Clone, Default)]
pub struct MeterStore {
    by_app: Arc<Mutex<HashMap<String, Meters>>>,
}

impl MeterStore {
    pub fn record(&self, app: &str, sample: impl FnOnce(&mut Meters)) {
        let mut map = self.by_app.lock().unwrap_or_else(|p| p.into_inner());
        sample(map.entry(app.to_string()).or_default());
    }

    pub fn get(&self, app: &str) -> Meters {
        self.by_app
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(app)
            .cloned()
            .unwrap_or_default()
    }

    pub fn apps(&self) -> Vec<String> {
        let mut ids: Vec<String> = self
            .by_app
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .keys()
            .cloned()
            .collect();
        ids.sort();
        ids
    }
}

/// A loaded instance, warm or in use.
struct Instance {
    machine_id: String,
    /// `None` while the instance is out on a call — which is how the sweep
    /// tells busy from idle without consulting the VM.
    idle_since: Option<Instant>,
    /// Whether the instance is parked. A hibernated instance is still loaded
    /// and still warm; it just holds no CPU.
    hibernated: bool,
}

/// A leased instance. Returning it to the pool is [`Lease::release`]; dropping
/// it without releasing unloads it, which is the right behaviour for a call
/// that panicked — an instance whose call did not finish cleanly is not one to
/// hand to the next caller.
pub struct Lease {
    pub machine_id: String,
    pub cold_start: bool,
    key: String,
    pool: Arc<InstancePool>,
    released: bool,
}

impl Lease {
    /// Hand the instance back for reuse.
    pub fn release(mut self) {
        self.released = true;
        self.pool.give_back(&self.key, &self.machine_id);
    }

    /// Unload rather than reuse — for a stateless function, or an instance that
    /// trapped.
    pub fn discard(mut self) {
        self.released = true;
        self.pool.discard(&self.key, &self.machine_id);
    }
}

impl Drop for Lease {
    fn drop(&mut self) {
        if !self.released {
            self.pool.discard(&self.key, &self.machine_id);
        }
    }
}

/// The pool.
/// Machine ids must be unique across the whole **process**, not per pool.
///
/// The VM registry is a process-global map keyed by machine id, so two pools
/// numbering their instances independently would hand out the same id for the
/// same app and function — and one pool destroying its instance would destroy
/// the other's. Two pools in one process is not hypothetical: it is every test
/// binary, and any host serving two registries.
static NEXT_INSTANCE: AtomicU64 = AtomicU64::new(1);

pub struct InstancePool {
    config: PoolConfig,
    instances: Mutex<HashMap<String, Vec<Instance>>>,
    pub meters: MeterStore,
}

impl InstancePool {
    pub fn new(config: PoolConfig) -> Arc<InstancePool> {
        Arc::new(InstancePool {
            config,
            instances: Mutex::new(HashMap::new()),
            meters: MeterStore::default(),
        })
    }

    fn key(app: &str, function: &str) -> String {
        format!("{app}\u{0}{function}")
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Vec<Instance>>> {
        self.instances.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Take a warm instance for `function`, or load one.
    ///
    /// Governance is applied when the instance is *created*, and it is applied
    /// again on reuse — an app's grant can change between calls, and a warm
    /// instance carrying the old one would be a way to keep a capability after
    /// it was revoked.
    /// Ensure an app has a supervisor node, and return its id.
    ///
    /// The node runs no guest code — it is an empty program whose only purpose
    /// is to be a parent. Its limits are the app's, so the aggregate budget the
    /// tree enforces is the app's budget rather than a per-instance one.
    fn ensure_supervisor(&self, app: &AppDefinition) -> String {
        let id = supervisor_id(&app.id);
        if !api::vm_exists(id.clone()) {
            // An empty program: valid bytecode that does nothing.
            let empty = elpian_vm::sdk::compiler::compile_ast(
                serde_json::json!({ "type": "program", "body": [] }),
                0,
            );
            api::create_vm_from_bytecode(id.clone(), empty);
        }
        // Applied every time, not only on creation: an app's grant and limits
        // can change between calls, and a stale supervisor would enforce the
        // old budget on the whole app.
        api::set_capabilities(&id, server_capabilities(&app.effective_capabilities()));
        api::set_limits(&id, app.limits);
        id
    }

    /// Unload an app's supervisor node and, with it, every instance beneath.
    fn destroy_supervisor(app: &str) -> Vec<String> {
        api::destroy_vm_tree(&supervisor_id(app))
    }

    /// An app's usage across every instance it has, from the VM tree.
    pub fn app_usage(&self, app: &str) -> Option<elpian_vm::api::ResourceUsage> {
        api::subtree_usage(&supervisor_id(app))
    }

    pub fn acquire(self: &Arc<Self>, app: &AppDefinition, def: &FunctionDef) -> Lease {
        let key = Self::key(&app.id, &def.name);

        if !def.stateless {
            let warm = {
                let mut instances = self.lock();
                instances.get_mut(&key).and_then(|list| {
                    // Prefer an awake instance over a hibernated one: waking is
                    // cheap but not free, and there is no reason to disturb a
                    // parked instance while an awake one is available.
                    let index = list
                        .iter()
                        .position(|i| i.idle_since.is_some() && !i.hibernated)
                        .or_else(|| list.iter().position(|i| i.idle_since.is_some()))?;
                    let instance = &mut list[index];
                    instance.idle_since = None;
                    let was_hibernated = instance.hibernated;
                    instance.hibernated = false;
                    Some((instance.machine_id.clone(), was_hibernated))
                })
            };
            if let Some((machine_id, was_hibernated)) = warm {
                // Still registered? A supervisor budget sweep can have taken it
                // down between calls, and handing back an id the registry no
                // longer knows would fail the call for no reason the caller
                // could act on.
                if api::vm_exists(machine_id.clone()) {
                    if was_hibernated {
                        // Waking is just clearing the pause flag. The
                        // continuation was preserved, so the module does not
                        // re-initialise — which is the whole reason to park an
                        // instance rather than unload it.
                        api::clear_pause(&machine_id);
                    }
                    self.apply_governance(&machine_id, app);
                    return Lease {
                        machine_id,
                        cold_start: false,
                        key,
                        pool: Arc::clone(self),
                        released: false,
                    };
                }
                self.forget(&key, &machine_id);
            }
        }

        let machine_id = format!(
            "{}::{}::{}",
            app.id,
            def.name,
            NEXT_INSTANCE.fetch_add(1, Ordering::Relaxed)
        );
        api::create_vm_from_bytecode(machine_id.clone(), def.bytecode.clone());
        self.apply_governance(&machine_id, app);

        // Adopt it under the app's supervisor. Adoption also recomputes the
        // instance's *effective* capabilities as local ∧ ancestors, so a
        // function can never hold more than its app does however its own grant
        // was set.
        let supervisor = self.ensure_supervisor(app);
        api::adopt_vm(&supervisor, &machine_id);

        if !def.stateless {
            let mut instances = self.lock();
            let list = instances.entry(key.clone()).or_default();
            list.push(Instance {
                machine_id: machine_id.clone(),
                idle_since: None,
                hibernated: false,
            });
        }

        Lease {
            machine_id,
            cold_start: true,
            key,
            pool: Arc::clone(self),
            released: false,
        }
    }

    fn apply_governance(&self, machine_id: &str, app: &AppDefinition) {
        api::set_capabilities(
            machine_id,
            server_capabilities(&app.effective_capabilities()),
        );
        api::set_limits(machine_id, app.limits);
    }

    fn give_back(&self, key: &str, machine_id: &str) {
        let mut instances = self.lock();
        if let Some(list) = instances.get_mut(key) {
            if let Some(instance) = list.iter_mut().find(|i| i.machine_id == machine_id) {
                instance.idle_since = Some(Instant::now());
                return;
            }
        }
        // Not tracked (a stateless call, or already evicted): unload it.
        drop(instances);
        api::destroy_vm(machine_id.to_string());
    }

    fn discard(&self, key: &str, machine_id: &str) {
        self.forget(key, machine_id);
        api::destroy_vm(machine_id.to_string());
    }

    fn forget(&self, key: &str, machine_id: &str) {
        let mut instances = self.lock();
        if let Some(list) = instances.get_mut(key) {
            list.retain(|i| i.machine_id != machine_id);
            if list.is_empty() {
                instances.remove(key);
            }
        }
    }

    /// How many instances are currently loaded.
    pub fn loaded(&self) -> usize {
        self.lock().values().map(Vec::len).sum()
    }

    /// How many are warm and idle.
    pub fn idle(&self) -> usize {
        self.lock()
            .values()
            .flat_map(|l| l.iter())
            .filter(|i| i.idle_since.is_some())
            .count()
    }

    /// How many idle instances are parked.
    pub fn hibernated(&self) -> usize {
        self.lock()
            .values()
            .flat_map(|l| l.iter())
            .filter(|i| i.hibernated)
            .count()
    }

    /// Park instances that have been idle past `hibernate_after`.
    ///
    /// Returns the ids parked. A hibernated instance is still loaded and still
    /// counts against the pool's caps — it has simply stopped costing CPU.
    /// Eviction still applies to it, later, on the longer `idle_ttl`.
    pub fn hibernate_idle(&self, config: &PoolConfig) -> Vec<String> {
        let Some(after) = config.hibernate_after else {
            return Vec::new();
        };
        let now = Instant::now();
        let mut parked = Vec::new();
        {
            let mut instances = self.lock();
            for list in instances.values_mut() {
                for instance in list.iter_mut() {
                    let Some(since) = instance.idle_since else {
                        continue; // busy: not idle however long ago it last ran
                    };
                    if !instance.hibernated && now.duration_since(since) >= after {
                        instance.hibernated = true;
                        parked.push(instance.machine_id.clone());
                    }
                }
            }
        }
        for machine_id in &parked {
            api::pause_vm(machine_id);
        }
        parked
    }

    /// Unload what nothing needs: instances idle past the TTL, then the least
    /// recently used while the pool is over capacity or a function is over its
    /// share.
    ///
    /// Never takes a busy instance — an instance in the middle of a call is not
    /// idle however long ago it last finished one, and unloading it would
    /// destroy a VM out from under a running turn.
    pub fn evict_idle(&self) -> Vec<String> {
        self.evict_idle_with(&self.config.clone())
    }

    /// As [`InstancePool::evict_idle`], with an explicit configuration — for a
    /// supervisor sweeping on different terms, and for tests that need a
    /// deterministic TTL rather than a wall-clock wait.
    pub fn evict_idle_with(&self, config: &PoolConfig) -> Vec<String> {
        let now = Instant::now();
        let mut unloaded = Vec::new();

        {
            let mut instances = self.lock();

            // 1. Past the TTL.
            for list in instances.values_mut() {
                list.retain(|i| match i.idle_since {
                    Some(since) if now.duration_since(since) >= config.idle_ttl => {
                        unloaded.push(i.machine_id.clone());
                        false
                    }
                    _ => true,
                });
            }

            // 2. Over a function's share.
            for list in instances.values_mut() {
                while list.len() > config.max_per_function {
                    let Some(index) = oldest_idle(list) else {
                        break;
                    };
                    unloaded.push(list.remove(index).machine_id);
                }
            }

            // 3. Over the host's total.
            let mut total: usize = instances.values().map(Vec::len).sum();
            while total > config.max_instances {
                let victim = instances
                    .iter_mut()
                    .filter_map(|(key, list)| {
                        oldest_idle(list).map(|i| (key.clone(), i, list[i].idle_since))
                    })
                    .min_by_key(|(_, _, since)| *since)
                    .map(|(key, index, _)| (key, index));
                let Some((key, index)) = victim else { break };
                if let Some(list) = instances.get_mut(&key) {
                    unloaded.push(list.remove(index).machine_id);
                }
                total -= 1;
            }

            instances.retain(|_, list| !list.is_empty());
        }

        for machine_id in &unloaded {
            api::destroy_vm(machine_id.clone());
        }
        unloaded
    }

    /// Unload every instance of one app — the whole-app teardown an operator
    /// needs when suspending or redeploying.
    pub fn drain_app(&self, app_id: &str) -> Vec<String> {
        let prefix = format!("{app_id}\u{0}");
        let mut unloaded = Vec::new();
        {
            let mut instances = self.lock();
            let keys: Vec<String> = instances
                .keys()
                .filter(|k| k.starts_with(&prefix))
                .cloned()
                .collect();
            for key in keys {
                if let Some(list) = instances.remove(&key) {
                    unloaded.extend(list.into_iter().map(|i| i.machine_id));
                }
            }
        }
        // One call takes down the supervisor and everything under it, including
        // any instance the pool has lost track of. Then the pool's own view is
        // reconciled — belt and braces, because an instance the tree knows about
        // and the pool does not is exactly the kind that leaks.
        Self::destroy_supervisor(app_id);
        for machine_id in &unloaded {
            api::destroy_vm(machine_id.clone());
        }
        unloaded
    }
}

/// Index of the least recently idle instance, or `None` if all are busy.
fn oldest_idle(list: &[Instance]) -> Option<usize> {
    list.iter()
        .enumerate()
        .filter_map(|(i, inst)| inst.idle_since.map(|since| (i, since)))
        .min_by_key(|(_, since)| *since)
        .map(|(i, _)| i)
}
