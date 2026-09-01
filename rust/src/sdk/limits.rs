//! Unified resource governance for an Elpian VM instance.
//!
//! The host embedding Elpa needs to keep a guest program inside hard, auditable
//! bounds: how much *work* it may do (instruction budget), how much *live heap*
//! it may hold (value memory), how much *persistent storage* it may occupy
//! (fabricated filesystem), and how deep it may recurse (call depth). This
//! module is the single place those budgets live.
//!
//! Design:
//! * [`ResourceLimits`] is the *policy* — each field is `Option<u64>`, where
//!   `None` means "unbounded". It is cheap to clone and can be replaced by the
//!   host at any time between turns.
//! * [`ResourceUsage`] is the *live tally* of what the instance is consuming.
//! * [`Governor`] couples the two and exposes the checked-charge operations the
//!   executor calls on the hot path. Charges are saturating and every overrun
//!   produces a typed [`LimitError`] the executor turns into a clean trap rather
//!   than a panic.
//!
//! Memory accounting is *approximate by construction*: we charge the shallow
//! footprint of each value the program allocates and credit it back when a
//! scope holding it is torn down. The goal is a faithful, monotonic-ish proxy
//! the host can cap — not a byte-exact allocator — so a runaway loop that keeps
//! allocating is stopped long before it can exhaust the real process heap.

use std::fmt;

/// The bounds the host places on one VM instance. Every field is optional;
/// `None` is "no limit". Construct with [`ResourceLimits::unlimited`] and tighten
/// the fields you care about, or use one of the presets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceLimits {
    /// Maximum number of interpreter steps the instance may execute, summed
    /// across every turn. Caps total CPU work (halts infinite loops).
    pub max_instructions: Option<u64>,
    /// Maximum number of interpreter steps in a *single* turn (one `run`,
    /// `run_func`, or resume). Caps latency / unbounded work per host call while
    /// still allowing a long-lived instance to do a lot of work over many turns.
    pub max_instructions_per_turn: Option<u64>,
    /// Maximum live value-memory the instance may hold, in bytes (approximate).
    pub max_memory_bytes: Option<u64>,
    /// Maximum persistent storage the instance may occupy, in bytes. Enforced by
    /// the host's fabricated filesystem, charged through the same governor so a
    /// single budget covers heap + disk if the host wishes.
    pub max_storage_bytes: Option<u64>,
    /// Maximum function-call nesting depth (guards native-stack exhaustion).
    pub max_call_depth: Option<u64>,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self::unlimited()
    }
}

impl ResourceLimits {
    /// No limits at all — the historical behaviour, for trusted programs.
    pub const fn unlimited() -> Self {
        ResourceLimits {
            max_instructions: None,
            max_instructions_per_turn: None,
            max_memory_bytes: None,
            max_storage_bytes: None,
            max_call_depth: None,
        }
    }

    /// A conservative sandbox suitable for running untrusted third-party
    /// modules: bounded work, heap, storage and recursion.
    pub fn sandboxed() -> Self {
        ResourceLimits {
            max_instructions: Some(50_000_000),
            max_instructions_per_turn: Some(5_000_000),
            max_memory_bytes: Some(64 * 1024 * 1024),
            max_storage_bytes: Some(16 * 1024 * 1024),
            max_call_depth: Some(1024),
        }
    }
}

/// The live consumption counters for an instance. Cheap, `Copy`, and reported
/// verbatim to the host so it can build dashboards or react before a hard cap is
/// hit.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ResourceUsage {
    /// Total interpreter steps executed across the instance's whole life.
    pub instructions: u64,
    /// Interpreter steps executed in the current turn (reset each turn).
    pub instructions_this_turn: u64,
    /// Live value-memory currently held, in bytes (approximate).
    pub memory_bytes: u64,
    /// Peak value-memory ever held, in bytes — useful for sizing limits.
    pub peak_memory_bytes: u64,
    /// Persistent storage currently occupied, in bytes.
    pub storage_bytes: u64,
    /// Current function-call nesting depth.
    pub call_depth: u64,
    /// Deepest call nesting ever reached.
    pub peak_call_depth: u64,
}

/// Which budget an operation overran. Carried by [`LimitError`] so the host (and
/// guest, via a trap value) can tell *why* the instance was stopped.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LimitKind {
    Instructions,
    InstructionsPerTurn,
    Memory,
    Storage,
    CallDepth,
}

impl LimitKind {
    /// Stable machine-readable tag (also used in the guest-visible trap value).
    pub fn as_str(&self) -> &'static str {
        match self {
            LimitKind::Instructions => "instructions",
            LimitKind::InstructionsPerTurn => "instructions_per_turn",
            LimitKind::Memory => "memory",
            LimitKind::Storage => "storage",
            LimitKind::CallDepth => "call_depth",
        }
    }
}

/// A budget overrun. The executor converts this into a controlled termination of
/// the instance (a trap) instead of a Rust panic.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LimitError {
    pub kind: LimitKind,
    /// The cap that was exceeded.
    pub limit: u64,
    /// The value the tally would have reached.
    pub requested: u64,
}

impl fmt::Display for LimitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "elpa limit exceeded: {} budget {} would be exceeded by request {}",
            self.kind.as_str(),
            self.limit,
            self.requested
        )
    }
}

/// Couples a [`ResourceLimits`] policy with the live [`ResourceUsage`] tally and
/// performs the checked charges. One governor lives per VM instance; the host
/// can swap the policy or read usage at any time between turns.
#[derive(Clone, Debug, Default)]
pub struct Governor {
    limits: ResourceLimits,
    usage: ResourceUsage,
}

impl Governor {
    pub fn new(limits: ResourceLimits) -> Self {
        Governor { limits, usage: ResourceUsage::default() }
    }

    pub fn limits(&self) -> ResourceLimits {
        self.limits
    }

    pub fn usage(&self) -> ResourceUsage {
        self.usage
    }

    /// Replace the active policy. Already-consumed usage is retained, so
    /// tightening a limit below current usage will trap on the next charge.
    pub fn set_limits(&mut self, limits: ResourceLimits) {
        self.limits = limits;
    }

    /// Begin a new turn: clears the per-turn instruction tally. Lifetime
    /// counters and live memory/storage carry over.
    pub fn begin_turn(&mut self) {
        self.usage.instructions_this_turn = 0;
    }

    /// Charge a single interpreter step against both the lifetime and per-turn
    /// instruction budgets. Called once per executor loop iteration.
    pub fn charge_instruction(&mut self) -> Result<(), LimitError> {
        let next = self.usage.instructions.saturating_add(1);
        if let Some(max) = self.limits.max_instructions {
            if next > max {
                return Err(LimitError {
                    kind: LimitKind::Instructions,
                    limit: max,
                    requested: next,
                });
            }
        }
        let next_turn = self.usage.instructions_this_turn.saturating_add(1);
        if let Some(max) = self.limits.max_instructions_per_turn {
            if next_turn > max {
                return Err(LimitError {
                    kind: LimitKind::InstructionsPerTurn,
                    limit: max,
                    requested: next_turn,
                });
            }
        }
        self.usage.instructions = next;
        self.usage.instructions_this_turn = next_turn;
        Ok(())
    }

    /// Charge `bytes` of newly held value-memory.
    pub fn charge_memory(&mut self, bytes: u64) -> Result<(), LimitError> {
        let next = self.usage.memory_bytes.saturating_add(bytes);
        if let Some(max) = self.limits.max_memory_bytes {
            if next > max {
                return Err(LimitError { kind: LimitKind::Memory, limit: max, requested: next });
            }
        }
        self.usage.memory_bytes = next;
        if next > self.usage.peak_memory_bytes {
            self.usage.peak_memory_bytes = next;
        }
        Ok(())
    }

    /// Credit `bytes` of value-memory back (scope teardown, dropped values).
    pub fn release_memory(&mut self, bytes: u64) {
        self.usage.memory_bytes = self.usage.memory_bytes.saturating_sub(bytes);
    }

    /// Charge a net change in persistent storage. `delta` may be negative to
    /// credit freed bytes (file deletion / truncation).
    pub fn charge_storage(&mut self, delta: i64) -> Result<(), LimitError> {
        let next = if delta >= 0 {
            self.usage.storage_bytes.saturating_add(delta as u64)
        } else {
            self.usage.storage_bytes.saturating_sub((-delta) as u64)
        };
        if let Some(max) = self.limits.max_storage_bytes {
            if next > max {
                return Err(LimitError { kind: LimitKind::Storage, limit: max, requested: next });
            }
        }
        self.usage.storage_bytes = next;
        Ok(())
    }

    /// Set the absolute storage figure (used when the host filesystem reconciles
    /// its on-disk total). Still bounded by the storage cap.
    pub fn set_storage_bytes(&mut self, bytes: u64) -> Result<(), LimitError> {
        if let Some(max) = self.limits.max_storage_bytes {
            if bytes > max {
                return Err(LimitError { kind: LimitKind::Storage, limit: max, requested: bytes });
            }
        }
        self.usage.storage_bytes = bytes;
        Ok(())
    }

    /// Enter a function call: deepen the recursion tally, guarding the cap.
    pub fn enter_call(&mut self) -> Result<(), LimitError> {
        let next = self.usage.call_depth.saturating_add(1);
        if let Some(max) = self.limits.max_call_depth {
            if next > max {
                return Err(LimitError {
                    kind: LimitKind::CallDepth,
                    limit: max,
                    requested: next,
                });
            }
        }
        self.usage.call_depth = next;
        if next > self.usage.peak_call_depth {
            self.usage.peak_call_depth = next;
        }
        Ok(())
    }

    /// Leave a function call.
    pub fn leave_call(&mut self) {
        self.usage.call_depth = self.usage.call_depth.saturating_sub(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unlimited_never_traps() {
        let mut g = Governor::new(ResourceLimits::unlimited());
        for _ in 0..1_000_000 {
            g.charge_instruction().unwrap();
        }
        g.charge_memory(u64::MAX / 2).unwrap();
        assert!(g.usage().instructions >= 1_000_000);
    }

    #[test]
    fn instruction_cap_traps_at_boundary() {
        let mut g = Governor::new(ResourceLimits { max_instructions: Some(3), ..ResourceLimits::unlimited() });
        g.charge_instruction().unwrap();
        g.charge_instruction().unwrap();
        g.charge_instruction().unwrap();
        let err = g.charge_instruction().unwrap_err();
        assert_eq!(err.kind, LimitKind::Instructions);
        assert_eq!(g.usage().instructions, 3, "usage not advanced past the cap");
    }

    #[test]
    fn per_turn_cap_resets_each_turn() {
        let mut g = Governor::new(ResourceLimits {
            max_instructions_per_turn: Some(2),
            ..ResourceLimits::unlimited()
        });
        g.charge_instruction().unwrap();
        g.charge_instruction().unwrap();
        assert!(g.charge_instruction().is_err());
        g.begin_turn();
        g.charge_instruction().unwrap();
        assert_eq!(g.usage().instructions, 3, "lifetime tally carries across turns");
        assert_eq!(g.usage().instructions_this_turn, 1);
    }

    #[test]
    fn memory_charge_and_release_track_peak() {
        let mut g = Governor::new(ResourceLimits { max_memory_bytes: Some(100), ..ResourceLimits::unlimited() });
        g.charge_memory(60).unwrap();
        g.charge_memory(40).unwrap();
        assert_eq!(g.usage().memory_bytes, 100);
        assert!(g.charge_memory(1).is_err());
        g.release_memory(50);
        assert_eq!(g.usage().memory_bytes, 50);
        assert_eq!(g.usage().peak_memory_bytes, 100);
        g.charge_memory(10).unwrap();
    }

    #[test]
    fn storage_delta_can_credit() {
        let mut g = Governor::new(ResourceLimits { max_storage_bytes: Some(1000), ..ResourceLimits::unlimited() });
        g.charge_storage(800).unwrap();
        assert!(g.charge_storage(300).is_err());
        g.charge_storage(-500).unwrap();
        assert_eq!(g.usage().storage_bytes, 300);
    }

    #[test]
    fn call_depth_guards_recursion() {
        let mut g = Governor::new(ResourceLimits { max_call_depth: Some(2), ..ResourceLimits::unlimited() });
        g.enter_call().unwrap();
        g.enter_call().unwrap();
        assert!(g.enter_call().is_err());
        g.leave_call();
        g.enter_call().unwrap();
        assert_eq!(g.usage().peak_call_depth, 2);
    }
}
