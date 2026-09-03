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

/// How the pool is bounded.
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// How long an instance may sit idle before it is unloaded.
    pub idle_ttl: Duration,
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
    pub fn acquire(self: &Arc<Self>, app: &AppDefinition, def: &FunctionDef) -> Lease {
        let key = Self::key(&app.id, &def.name);

        if !def.stateless {
            let warm = {
                let mut instances = self.lock();
                instances.get_mut(&key).and_then(|list| {
                    list.iter_mut().find(|i| i.idle_since.is_some()).map(|i| {
                        i.idle_since = None;
                        i.machine_id.clone()
                    })
                })
            };
            if let Some(machine_id) = warm {
                // Still registered? A supervisor budget sweep can have taken it
                // down between calls, and handing back an id the registry no
                // longer knows would fail the call for no reason the caller
                // could act on.
                if api::vm_exists(machine_id.clone()) {
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

        if !def.stateless {
            let mut instances = self.lock();
            let list = instances.entry(key.clone()).or_default();
            list.push(Instance {
                machine_id: machine_id.clone(),
                idle_since: None,
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
