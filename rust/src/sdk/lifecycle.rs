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

/// Shared, host-flippable execution control. Cheap to clone (it is meant to be
/// held behind an `Rc<RefCell<…>>`); the methods encode the legal transitions.
#[derive(Clone, Copy, Debug)]
pub struct ExecControl {
    state: RunState,
}

impl Default for ExecControl {
    fn default() -> Self {
        ExecControl { state: RunState::Running }
    }
}

impl ExecControl {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn state(&self) -> RunState {
        self.state
    }

    /// Host: request a pause. No-op once terminated.
    pub fn request_pause(&mut self) {
        if matches!(self.state, RunState::Running) {
            self.state = RunState::PauseRequested;
        }
    }

    /// Host: resume a paused (or pause-requested) instance.
    pub fn resume(&mut self) {
        if matches!(self.state, RunState::Paused | RunState::PauseRequested) {
            self.state = RunState::Running;
        }
    }

    /// Host: request termination. Always honoured unless already terminated.
    pub fn request_terminate(&mut self) {
        if !matches!(self.state, RunState::Terminated) {
            self.state = RunState::TerminateRequested;
        }
    }

    /// Executor: has the host asked us to stop stepping (pause or terminate)?
    pub fn should_suspend(&self) -> bool {
        matches!(self.state, RunState::PauseRequested | RunState::TerminateRequested)
    }

    pub fn is_terminating(&self) -> bool {
        matches!(self.state, RunState::TerminateRequested | RunState::Terminated)
    }

    pub fn is_paused(&self) -> bool {
        matches!(self.state, RunState::Paused)
    }

    pub fn is_terminated(&self) -> bool {
        matches!(self.state, RunState::Terminated)
    }

    /// Executor: acknowledge a pause request by parking the instance.
    pub fn confirm_paused(&mut self) {
        if matches!(self.state, RunState::PauseRequested) {
            self.state = RunState::Paused;
        }
    }

    /// Executor: acknowledge termination.
    pub fn confirm_terminated(&mut self) {
        self.state = RunState::Terminated;
    }

    /// Executor: mark forward progress (clears a stale paused flag when the host
    /// has already resumed). Returns whether execution may proceed.
    pub fn may_run(&self) -> bool {
        matches!(self.state, RunState::Running)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pause_then_resume_round_trips() {
        let mut c = ExecControl::new();
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
        let mut c = ExecControl::new();
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
        let mut c = ExecControl::new();
        c.request_pause();
        c.resume();
        assert!(c.may_run());
    }
}
