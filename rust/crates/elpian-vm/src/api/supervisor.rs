//! The supervisor: a background sweep that enforces what no single call can.
//!
//! Three of the governance rules the VM already implements can only be applied
//! by something that looks at instances *while they run*, on a clock of its own:
//!
//! * **Wall-clock deadlines.** The instruction budget bounds how much a guest
//!   computes, not how long it holds an instance. A guest parked in a host call
//!   that never returns burns no instructions and runs forever.
//! * **Aggregate tree budgets.** [`enforce_tree_budgets`] compares a VM's limits
//!   against its whole subtree's usage. Nothing calls it on its own; on a client
//!   it was expected to be driven once per frame, and a server has no frames.
//! * **Idle eviction.** An instance nothing has called for a while is holding
//!   memory for nobody. (The pool that acts on this arrives with the serverless
//!   workstream; the sweep reports the candidates now.)
//!
//! # Why this can work at all
//!
//! The sweep runs on its own thread and must never block on the instances it is
//! policing — a supervisor that waits for a runaway guest to finish is not a
//! supervisor. Two properties of the registry make that possible, and both were
//! put there for this:
//!
//! * an instance's control flag and busy clock live *beside* the VM, reachable
//!   with only a briefly-held shard lock, so the sweep observes and stops a
//!   guest that is mid-turn; and
//! * `terminate` lands at the guest's next interpreter step rather than waiting
//!   for the turn to end.
//!
//! The sweep therefore never takes a VM lock at all.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use super::{monotonic_millis, VMS};

/// What the sweep enforces, and how often.
#[derive(Clone, Debug)]
pub struct SupervisorConfig {
    /// How often to sweep. Every deadline is enforced to within one interval,
    /// so this is the resolution of every figure below.
    pub interval: Duration,
    /// How long one turn may run before the instance is terminated. `None`
    /// disables the deadline — appropriate for a client host driving a trusted
    /// app, never for a server running submitted code.
    pub turn_deadline: Option<Duration>,
    /// Whether to enforce aggregate subtree budgets each sweep.
    pub enforce_tree_budgets: bool,
    /// How long an instance may go without a turn before the sweep reports it
    /// as an eviction candidate. Reporting only — the sweep never destroys an
    /// idle instance, because only the embedder knows whether it is warm-pooled
    /// or simply quiet.
    pub idle_after: Option<Duration>,
}

impl Default for SupervisorConfig {
    fn default() -> Self {
        SupervisorConfig {
            interval: Duration::from_millis(100),
            turn_deadline: None,
            enforce_tree_budgets: true,
            idle_after: None,
        }
    }
}

/// What one sweep did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SweepReport {
    /// Instances terminated for overrunning [`SupervisorConfig::turn_deadline`],
    /// with how long the offending turn had been running.
    pub deadline_terminated: Vec<(String, Duration)>,
    /// Subtrees destroyed for an aggregate budget overrun:
    /// `(root, axis, destroyed ids)`.
    pub budget_violations: Vec<(String, String, Vec<String>)>,
    /// Instances idle longer than [`SupervisorConfig::idle_after`]. Reported,
    /// never acted on.
    pub idle_candidates: Vec<String>,
}

impl SweepReport {
    /// Whether the sweep found nothing — the common case, and worth checking
    /// before allocating a log line for it.
    pub fn is_quiet(&self) -> bool {
        self.deadline_terminated.is_empty()
            && self.budget_violations.is_empty()
            && self.idle_candidates.is_empty()
    }
}

/// Run one sweep synchronously and report what it did.
///
/// Exposed separately from [`Supervisor`] so an embedder with its own scheduler
/// — a client host on a frame tick, a test that wants determinism — can drive
/// the same enforcement without a background thread.
pub fn sweep(config: &SupervisorConfig) -> SweepReport {
    let mut report = SweepReport::default();

    // Without a monotonic clock there is nothing to compare against, so the
    // time-based rules are skipped rather than guessed at. Aggregate budgets
    // still apply — they are counted, not timed.
    let now = monotonic_millis();

    for (id, entry) in VMS.snapshot() {
        let busy_since = entry.busy_since_ms.load(Ordering::Acquire);

        if let (Some(deadline), Some(now)) = (config.turn_deadline, now) {
            // `0` means idle: a deadline only applies to a turn in flight.
            if busy_since != 0 {
                let running = Duration::from_millis(now.saturating_sub(busy_since));
                if running >= deadline {
                    // Lands at the guest's next interpreter step. The turn is
                    // still running and holding the VM lock, which is exactly
                    // why this goes through the control flag.
                    entry.control.request_terminate();
                    report.deadline_terminated.push((id.clone(), running));
                    continue;
                }
            }
        }

        if let (Some(idle_after), Some(now)) = (config.idle_after, now) {
            if busy_since == 0 {
                let last = entry.last_turn_end_ms.load(Ordering::Acquire);
                if last != 0 && Duration::from_millis(now.saturating_sub(last)) >= idle_after {
                    report.idle_candidates.push(id.clone());
                }
            }
        }
    }

    if config.enforce_tree_budgets {
        report.budget_violations = super::enforce_tree_budgets();
    }

    report
}

/// A running supervisor. Dropping it stops the sweep.
///
/// Not available on `wasm32-unknown-unknown`, which has neither threads nor a
/// clock. A compile error is the right failure there: the alternative is code
/// that builds and then traps at run time, which is exactly the shape of bug
/// that put a blank page on the web build. [`sweep`] remains available
/// everywhere for an embedder with its own scheduler.
#[cfg(not(all(target_arch = "wasm32", target_os = "unknown")))]
pub struct Supervisor {
    running: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

#[cfg(not(all(target_arch = "wasm32", target_os = "unknown")))]
impl Supervisor {
    /// Start sweeping on a background thread, handing each non-quiet report to
    /// `on_report`.
    ///
    /// `on_report` runs on the sweep thread and must not call back into a VM
    /// turn — log it, meter it, or send it somewhere. Blocking here delays
    /// every later sweep, which is how a deadline stops being enforced.
    pub fn start(
        config: SupervisorConfig,
        mut on_report: impl FnMut(SweepReport) + Send + 'static,
    ) -> Supervisor {
        let running = Arc::new(AtomicBool::new(true));
        let flag = running.clone();
        let handle = std::thread::Builder::new()
            .name("elpian-supervisor".into())
            .spawn(move || {
                while flag.load(Ordering::Acquire) {
                    let report = sweep(&config);
                    if !report.is_quiet() {
                        on_report(report);
                    }
                    // Sleep in slices so `stop` is observed promptly even when
                    // the interval is long.
                    let mut slept = Duration::ZERO;
                    while slept < config.interval && flag.load(Ordering::Acquire) {
                        let slice = config.interval.min(Duration::from_millis(20));
                        std::thread::sleep(slice);
                        slept += slice;
                    }
                }
            })
            .expect("supervisor thread should spawn");
        Supervisor {
            running,
            handle: Some(handle),
        }
    }

    /// Stop sweeping and wait for the thread to finish.
    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        self.running.store(false, Ordering::Release);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

#[cfg(not(all(target_arch = "wasm32", target_os = "unknown")))]
impl Drop for Supervisor {
    fn drop(&mut self) {
        self.shutdown();
    }
}
