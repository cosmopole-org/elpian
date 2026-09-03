//! Acting on the meters.
//!
//! Metering without enforcement is a report nobody reads. This turns the
//! counters into a decision made *before* an invocation runs — the only point
//! at which refusing costs nothing.
//!
//! # The ladder, and why it is a ladder
//!
//! An app that goes over budget is not necessarily malicious; the common case
//! is a bug or a burst. Killing it outright is the right answer eventually and
//! the wrong answer immediately, so the response escalates:
//!
//! | Stage | What happens | Recovers by |
//! |---|---|---|
//! | `Serve` | nothing | — |
//! | `Throttle` | a share of calls are refused | usage falling below the threshold |
//! | `Strangle` | only reads (components) are served; actions refused | as above |
//! | `Drain` | every call refused, instances unloaded | operator action |
//! | `Suspend` | as drain, and stays there | operator action |
//!
//! The two middle rungs are the point. Throttling sheds load while leaving the
//! app working for most callers, and strangling keeps a *readable* app while
//! stopping it writing — which for a runaway loop of writes is usually exactly
//! what an operator wants and could not previously express.
//!
//! # Why this is checked before the guest runs
//!
//! An over-budget app that is refused after its instructions are spent has
//! already cost what the quota exists to bound. The check is a map lookup and
//! two comparisons, so putting it in front of every call is affordable.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use crate::pool::Meters;

/// What an app is allowed to spend before the ladder starts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Quota {
    pub max_invocations: Option<u64>,
    pub max_instructions: Option<u64>,
    pub max_compute_ms: Option<u64>,
    pub max_storage_bytes: Option<u64>,
}

impl Default for Quota {
    fn default() -> Self {
        // Unbounded by default. A host that has not been told an app's budget
        // must not invent one — silently throttling an app nobody metered is a
        // worse failure than not enforcing a quota nobody set.
        Quota {
            max_invocations: None,
            max_instructions: None,
            max_compute_ms: None,
            max_storage_bytes: None,
        }
    }
}

/// How far up the ladder an app is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Stage {
    Serve,
    Throttle,
    Strangle,
    Drain,
    Suspend,
}

impl Stage {
    pub fn as_str(&self) -> &'static str {
        match self {
            Stage::Serve => "serve",
            Stage::Throttle => "throttle",
            Stage::Strangle => "strangle",
            Stage::Drain => "drain",
            Stage::Suspend => "suspend",
        }
    }
}

/// What to do with one call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Admission {
    Allow,
    /// Refused. The message is the caller's; the axis is the operator's.
    Refuse { stage: Stage, axis: &'static str },
}

/// Quotas, and where each app currently sits.
#[derive(Clone, Default)]
pub struct QuotaEnforcer {
    quotas: Arc<RwLock<HashMap<String, Quota>>>,
    /// Apps an operator has explicitly suspended. Separate from a computed
    /// stage because it must not be undone by usage falling — an operator's
    /// decision outranks arithmetic.
    suspended: Arc<RwLock<Vec<String>>>,
    /// Rotating counter for throttling, so the same caller is not always the
    /// one refused.
    tick: Arc<std::sync::atomic::AtomicU64>,
}

impl QuotaEnforcer {
    pub fn new() -> QuotaEnforcer {
        QuotaEnforcer::default()
    }

    pub fn set_quota(&self, app: &str, quota: Quota) {
        self.quotas
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .insert(app.to_string(), quota);
    }

    pub fn quota(&self, app: &str) -> Quota {
        self.quotas
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(app)
            .cloned()
            .unwrap_or_default()
    }

    pub fn suspend(&self, app: &str) {
        let mut suspended = self.suspended.write().unwrap_or_else(|p| p.into_inner());
        if !suspended.iter().any(|a| a == app) {
            suspended.push(app.to_string());
        }
    }

    pub fn resume(&self, app: &str) {
        self.suspended
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .retain(|a| a != app);
    }

    pub fn is_suspended(&self, app: &str) -> bool {
        self.suspended
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .iter()
            .any(|a| a == app)
    }

    /// Where an app sits, given what it has spent.
    pub fn stage(&self, app: &str, meters: &Meters) -> Stage {
        if self.is_suspended(app) {
            return Stage::Suspend;
        }
        let quota = self.quota(app);

        // The worst axis decides. An app comfortably inside three budgets and
        // far past a fourth is over budget.
        let mut worst = Stage::Serve;
        let mut consider = |used: u64, limit: Option<u64>| {
            let Some(limit) = limit else { return };
            if limit == 0 {
                worst = worst.max(Stage::Drain);
                return;
            }
            // Percentages of the budget, not absolute steps, so one ladder
            // works for an app metered in thousands and one in billions.
            let ratio = used as f64 / limit as f64;
            let stage = if ratio >= 1.5 {
                Stage::Drain
            } else if ratio >= 1.0 {
                Stage::Strangle
            } else if ratio >= 0.9 {
                Stage::Throttle
            } else {
                Stage::Serve
            };
            worst = worst.max(stage);
        };

        consider(meters.invocations, quota.max_invocations);
        consider(meters.instructions, quota.max_instructions);
        consider(meters.compute_ms, quota.max_compute_ms);
        consider(meters.storage_bytes, quota.max_storage_bytes);
        worst
    }

    /// Decide one call.
    ///
    /// `is_write` distinguishes an action from a component render — the
    /// distinction the `Strangle` rung exists to make.
    pub fn admit(&self, app: &str, meters: &Meters, is_write: bool) -> Admission {
        let stage = self.stage(app, meters);
        let axis = self.worst_axis(app, meters);
        match stage {
            Stage::Serve => Admission::Allow,
            Stage::Throttle => {
                // Refuse one call in four. Enough to shed load and slow a
                // runaway; not so much that a legitimate app looks broken.
                let n = self
                    .tick
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                if n % 4 == 3 {
                    Admission::Refuse { stage, axis }
                } else {
                    Admission::Allow
                }
            }
            Stage::Strangle => {
                if is_write {
                    Admission::Refuse { stage, axis }
                } else {
                    // Reads still work, so the app remains *readable* while it
                    // is stopped from writing. For a runaway loop of writes
                    // that is usually exactly what an operator wants.
                    Admission::Allow
                }
            }
            Stage::Drain | Stage::Suspend => Admission::Refuse { stage, axis },
        }
    }

    /// Which budget is furthest over, for the operator's log.
    fn worst_axis(&self, app: &str, meters: &Meters) -> &'static str {
        let quota = self.quota(app);
        let mut worst = ("none", 0.0f64);
        let mut consider = |name: &'static str, used: u64, limit: Option<u64>| {
            if let Some(limit) = limit {
                let ratio = if limit == 0 {
                    f64::INFINITY
                } else {
                    used as f64 / limit as f64
                };
                if ratio > worst.1 {
                    worst = (name, ratio);
                }
            }
        };
        consider("invocations", meters.invocations, quota.max_invocations);
        consider("instructions", meters.instructions, quota.max_instructions);
        consider("computeMs", meters.compute_ms, quota.max_compute_ms);
        consider("storageBytes", meters.storage_bytes, quota.max_storage_bytes);
        worst.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meters(invocations: u64) -> Meters {
        Meters {
            invocations,
            ..Meters::default()
        }
    }

    #[test]
    fn an_app_with_no_quota_is_never_throttled() {
        // A host that has not been told an app's budget must not invent one.
        let enforcer = QuotaEnforcer::new();
        assert_eq!(enforcer.stage("free", &meters(1_000_000)), Stage::Serve);
        assert_eq!(
            enforcer.admit("free", &meters(1_000_000), true),
            Admission::Allow
        );
    }

    #[test]
    fn the_ladder_escalates_with_usage() {
        let enforcer = QuotaEnforcer::new();
        enforcer.set_quota(
            "app",
            Quota {
                max_invocations: Some(100),
                ..Quota::default()
            },
        );

        assert_eq!(enforcer.stage("app", &meters(50)), Stage::Serve);
        assert_eq!(enforcer.stage("app", &meters(95)), Stage::Throttle);
        assert_eq!(enforcer.stage("app", &meters(120)), Stage::Strangle);
        assert_eq!(enforcer.stage("app", &meters(200)), Stage::Drain);
    }

    #[test]
    fn strangling_keeps_an_app_readable_while_stopping_it_writing() {
        // The rung that exists because "stop it writing but leave it readable"
        // is what an operator usually wants for a runaway loop of writes, and
        // could not previously be expressed at all.
        let enforcer = QuotaEnforcer::new();
        enforcer.set_quota(
            "app",
            Quota {
                max_invocations: Some(100),
                ..Quota::default()
            },
        );
        let over = meters(120);

        assert!(matches!(
            enforcer.admit("app", &over, true),
            Admission::Refuse { .. }
        ));
        assert_eq!(enforcer.admit("app", &over, false), Admission::Allow);
    }

    #[test]
    fn throttling_refuses_some_calls_and_serves_most() {
        let enforcer = QuotaEnforcer::new();
        enforcer.set_quota(
            "app",
            Quota {
                max_invocations: Some(100),
                ..Quota::default()
            },
        );
        let near = meters(95);

        let mut refused = 0;
        for _ in 0..100 {
            if matches!(
                enforcer.admit("app", &near, true),
                Admission::Refuse { .. }
            ) {
                refused += 1;
            }
        }
        assert_eq!(refused, 25, "one call in four");
    }

    #[test]
    fn the_worst_axis_decides() {
        // Comfortably inside three budgets and far past a fourth is over budget.
        let enforcer = QuotaEnforcer::new();
        enforcer.set_quota(
            "app",
            Quota {
                max_invocations: Some(1_000_000),
                max_storage_bytes: Some(100),
                ..Quota::default()
            },
        );
        let m = Meters {
            invocations: 5,
            storage_bytes: 500,
            ..Meters::default()
        };
        assert_eq!(enforcer.stage("app", &m), Stage::Drain);
    }

    #[test]
    fn an_operator_suspension_outranks_arithmetic() {
        // Usage falling must not un-suspend an app somebody deliberately
        // stopped.
        let enforcer = QuotaEnforcer::new();
        enforcer.suspend("app");
        assert_eq!(enforcer.stage("app", &meters(0)), Stage::Suspend);
        assert!(matches!(
            enforcer.admit("app", &meters(0), false),
            Admission::Refuse { .. }
        ));

        enforcer.resume("app");
        assert_eq!(enforcer.stage("app", &meters(0)), Stage::Serve);
    }

    #[test]
    fn a_zero_budget_means_stopped_not_unlimited() {
        // `Some(0)` is a real answer — "this app may spend nothing" — and must
        // not be confused with `None`, which means unbounded.
        let enforcer = QuotaEnforcer::new();
        enforcer.set_quota(
            "app",
            Quota {
                max_invocations: Some(0),
                ..Quota::default()
            },
        );
        assert_eq!(enforcer.stage("app", &meters(0)), Stage::Drain);
    }
}
