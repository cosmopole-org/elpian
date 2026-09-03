//! The host's handle on a running instance.
//!
//! Budgets, capability toggles, lifecycle and fault reporting — everything the
//! embedder calls *between* turns, as opposed to the interpreter's own work.
//! Kept apart from the run loop because it is read by a different audience:
//! `api::govern` and everything above it, rather than anyone tracing execution.
//!
//! These are inherent methods on [`Executor`]; Rust allows a type's inherent
//! impls to be spread across modules of the defining crate, so no call site
//! changes.

use super::Executor;
use crate::sdk::capabilities::CapabilitySet;
use crate::sdk::limits::ResourceLimits;

impl Executor {
    // ---- Host-facing instance management (limits, capabilities, lifecycle) --

    /// Replace the active resource-limit policy. Usage already accrued is kept.
    pub fn set_limits(&mut self, limits: ResourceLimits) {
        self.governor.set_limits(limits);
    }
    /// Current resource limits.
    pub fn limits(&self) -> ResourceLimits {
        self.governor.limits()
    }
    /// Live resource usage tally.
    pub fn usage(&self) -> crate::sdk::limits::ResourceUsage {
        self.governor.usage()
    }
    /// Mutable access to the capability set (host toggles network / storage / …).
    pub fn capabilities_mut(&mut self) -> &mut CapabilitySet {
        &mut self.capabilities
    }
    /// Snapshot of the capability set.
    pub fn capabilities(&self) -> CapabilitySet {
        self.capabilities.clone()
    }
    /// Replace the capability set wholesale.
    pub fn set_capabilities(&mut self, caps: CapabilitySet) {
        self.capabilities = caps;
    }
    /// Host: request the instance pause at the next step boundary.
    pub fn request_pause(&mut self) {
        self.control.request_pause();
    }
    /// Host: resume a paused instance.
    pub fn resume_control(&mut self) {
        self.control.resume();
    }
    /// Host: request the instance terminate. If it is idle (between turns) the
    /// termination is confirmed immediately; if it is mid-flight (e.g. servicing
    /// a host call) the request is observed and confirmed at the next step
    /// boundary by the run loop.
    pub fn request_terminate(&mut self) {
        self.control.request_terminate();
        self.confirm_terminate_if_idle();
    }
    /// Acknowledge a pending terminate when the instance is between turns.
    ///
    /// A mid-turn instance is left alone: its own step loop observes the flag
    /// and confirms it, and clearing the registers under a running turn would
    /// pull the continuation out from beneath it. Split out from
    /// [`Executor::request_terminate`] so the `VM` handle — which sets the flag
    /// without going through the executor, so that it can reach a *running*
    /// guest — can still finish the job for an idle one.
    pub fn confirm_terminate_if_idle(&mut self) {
        if self.control.is_terminating() && !self.processing {
            self.control.confirm_terminated();
            self.registers.clear();
        }
    }
    /// Current run state.
    pub fn run_state(&self) -> crate::sdk::lifecycle::RunState {
        self.control.state()
    }
    /// Whether the instance suspended on a host pause this turn.
    pub fn was_paused(&self) -> bool {
        self.paused_out
    }
    /// The fatal trap reason, if the instance was stopped by a limit or error.
    pub fn trap_reason(&self) -> Option<String> {
        self.trap.clone()
    }
    /// Record a guest fault that unwound out of the step loop, turning it into
    /// an ordinary trap.
    ///
    /// Guest type errors are raised with `panic!` rather than as traps (see
    /// `operate_sum` and friends), so they unwind straight past the bookkeeping
    /// that would normally end a turn. That left the instance wedged: the
    /// `processing` flag stayed set, and every later `execute_vm_func*` bounced
    /// with `vm_busy` forever. The embedder catches the unwind at the turn
    /// boundary and calls this, which puts the instance in exactly the state a
    /// limit overrun would have: trapped, terminated, no longer processing, and
    /// reporting its reason through [`Executor::trap_reason`].
    ///
    /// The first fault wins — a fault raised while unwinding a previous one
    /// must not mask the original reason.
    pub fn record_fault(&mut self, reason: String) {
        if self.trap.is_none() {
            self.trap = Some(reason);
        }
        self.processing = false;
        self.paused_out = false;
        self.control.confirm_terminated();
        self.registers.clear();
    }
    /// Charge the storage governor on behalf of the host filesystem; returns the
    /// limit error string if the storage cap would be exceeded.
    pub fn charge_storage(&mut self, delta: i64) -> Result<(), String> {
        self.governor
            .charge_storage(delta)
            .map_err(|e| e.to_string())
    }
    /// Reconcile the absolute storage figure with the host filesystem total.
    pub fn set_storage_bytes(&mut self, bytes: u64) -> Result<(), String> {
        self.governor
            .set_storage_bytes(bytes)
            .map_err(|e| e.to_string())
    }
}
