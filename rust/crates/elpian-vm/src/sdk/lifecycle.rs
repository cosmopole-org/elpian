//! Instance lifecycle control: pause, resume, terminate.
//!
//! The Elpian executor is already a *pausing* interpreter — it suspends on every
//! `askHost`. This module adds the orthogonal, host-driven controls the embedder
//! needs to steer an instance independently of its host-call rhythm:
//!
//! * **Pause** — the executor stops at the next interpreter step boundary and
//!   returns control to the host, preserving its full continuation (pointer,
//!   register stack, scope memory). A paused instance consumes no CPU.
//! * **Resume** — the executor picks up exactly where it left off.
//! * **Terminate** — the executor unwinds at the next step boundary and the
//!   instance is finished; further drive calls are inert.
//!
//! The control flag is shared (`Rc<RefCell<…>>`) between the public VM handle and
//! the executor, so the host can flip it between turns (and, when servicing a
//! host call, mid-flight) and have the executor observe it at the next step.

/// The run state of an instance, as seen by the executor's step loop.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunState {
    /// Free to execute.
    Running,
    /// The host has requested a pause; the executor will suspend at the next
    /// step boundary and report itself paused.
    PauseRequested,
    /// Suspended mid-program with its continuation intact; awaiting `resume`.
    Paused,
    /// The host has requested termination; the executor will unwind at the next
    /// step boundary.
    TerminateRequested,
    /// Fully stopped. No further execution will occur.
    Terminated,
}

impl RunState {
    pub fn as_str(&self) -> &'static str {
        match self {
            RunState::Running => "running",
            RunState::PauseRequested => "pause_requested",
            RunState::Paused => "paused",
            RunState::TerminateRequested => "terminate_requested",
            RunState::Terminated => "terminated",
        }
    }
}

/// Shared, host-flippable execution control.
///
/// # Why this is atomic and shared rather than a plain field
///
/// The whole point of the flag is that a host can set it **while the executor
/// is inside a turn** — that is what makes a runaway guest stoppable at all.
/// This used to be a `Copy` field living inside the `Executor`, which meant
/// reaching it required the executor's `RefCell` (held for the duration of the
/// turn) and, above that, the instance's registry lock. So a host asking a
/// spinning guest to stop blocked until the guest stopped on its own — the
/// request could only ever land *between* turns, precisely when it was not
/// needed. The module documentation claimed the flag was shared; now it is.
///
/// Cloning shares the flag. The executor holds one clone and observes it at
/// every step boundary; the `VM` handle holds another and the host flips it
/// from any thread, with no lock in the path.
#[derive(Clone)]
pub struct ExecControl {
    state: std::sync::Arc<std::sync::atomic::AtomicU8>,
}

impl std::fmt::Debug for ExecControl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("ExecControl").field(&self.state()).finish()
    }
}

impl RunState {
    fn as_u8(self) -> u8 {
        match self {
            RunState::Running => 0,
            RunState::PauseRequested => 1,
            RunState::Paused => 2,
            RunState::TerminateRequested => 3,
            RunState::Terminated => 4,
        }
    }
    fn from_u8(v: u8) -> RunState {
        match v {
            1 => RunState::PauseRequested,
            2 => RunState::Paused,
            3 => RunState::TerminateRequested,
            4 => RunState::Terminated,
            _ => RunState::Running,
        }
    }
}

impl Default for ExecControl {
    fn default() -> Self {
        ExecControl {
            state: std::sync::Arc::new(std::sync::atomic::AtomicU8::new(
                RunState::Running.as_u8(),
            )),
        }
    }
}

impl ExecControl {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn state(&self) -> RunState {
        RunState::from_u8(self.state.load(std::sync::atomic::Ordering::Acquire))
    }

    /// Apply `f` to the current state until it lands, so a concurrent host
    /// request and executor acknowledgement cannot lose one another. `f`
    /// returning `None` means "no transition from here" and leaves the flag be.
    fn transition(&self, f: impl Fn(RunState) -> Option<RunState>) {
        use std::sync::atomic::Ordering;
        let mut current = self.state.load(Ordering::Acquire);
        loop {
            let Some(next) = f(RunState::from_u8(current)) else {
                return;
            };
            match self.state.compare_exchange_weak(
                current,
                next.as_u8(),
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => return,
                Err(observed) => current = observed,
            }
        }
    }

    /// Host: request a pause. No-op once terminated.
    pub fn request_pause(&self) {
        self.transition(|s| matches!(s, RunState::Running).then_some(RunState::PauseRequested));
    }

    /// Host: resume a paused (or pause-requested) instance.
    pub fn resume(&self) {
        self.transition(|s| {
            matches!(s, RunState::Paused | RunState::PauseRequested).then_some(RunState::Running)
        });
    }

    /// Host: request termination. Always honoured unless already terminated.
    pub fn request_terminate(&self) {
        self.transition(|s| {
            (!matches!(s, RunState::Terminated)).then_some(RunState::TerminateRequested)
        });
    }

    /// Executor: has the host asked us to stop stepping (pause or terminate)?
    pub fn should_suspend(&self) -> bool {
        matches!(
            self.state(),
            RunState::PauseRequested | RunState::TerminateRequested
        )
    }

    pub fn is_terminating(&self) -> bool {
        matches!(
            self.state(),
            RunState::TerminateRequested | RunState::Terminated
        )
    }

    pub fn is_paused(&self) -> bool {
        matches!(self.state(), RunState::Paused)
    }

    pub fn is_terminated(&self) -> bool {
        matches!(self.state(), RunState::Terminated)
    }

    /// Executor: acknowledge a pause request by parking the instance.
    pub fn confirm_paused(&self) {
        self.transition(|s| matches!(s, RunState::PauseRequested).then_some(RunState::Paused));
    }

    /// Executor: acknowledge termination.
    pub fn confirm_terminated(&self) {
        self.transition(|s| (!matches!(s, RunState::Terminated)).then_some(RunState::Terminated));
    }

    /// Executor: mark forward progress (clears a stale paused flag when the host
    /// has already resumed). Returns whether execution may proceed.
    pub fn may_run(&self) -> bool {
        matches!(self.state(), RunState::Running)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pause_then_resume_round_trips() {
        let c = ExecControl::new();
        assert!(c.may_run());
        c.request_pause();
        assert!(c.should_suspend());
        c.confirm_paused();
        assert_eq!(c.state(), RunState::Paused);
        assert!(!c.may_run());
        c.resume();
        assert!(c.may_run());
    }

    #[test]
    fn terminate_is_sticky() {
        let c = ExecControl::new();
        c.request_terminate();
        assert!(c.should_suspend());
        assert!(c.is_terminating());
        c.confirm_terminated();
        assert!(c.is_terminated());
        // resume / pause cannot revive a terminated instance.
        c.resume();
        c.request_pause();
        assert_eq!(c.state(), RunState::Terminated);
    }

    #[test]
    fn pause_request_before_confirm_can_be_resumed() {
        let c = ExecControl::new();
        c.request_pause();
        c.resume();
        assert!(c.may_run());
    }
}
