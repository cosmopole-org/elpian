//! Driving one server-function invocation to completion.
//!
//! This is the loop the previous server did not have. It created a VM, ran the
//! top level, called the function, and if the guest made *any* `askHost` call
//! it gave up with HTTP 501 — so a server function could not log, read the
//! clock, keep state or touch a file. Everything else in the server workstream
//! sits on top of this loop existing.
//!
//! The shape is the same pausing protocol the client host uses: the VM
//! suspends on `askHost`, hands out an envelope, and resumes when given a
//! reply. The only thing that differs is who services the envelope.

use elpian_vm::api;
use serde_json::{json, Value};

use crate::hostcall::{HostCall, HostServices};

/// How an invocation ended.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// The function returned. The value is whatever it returned, as JSON.
    Returned(Value),
    /// The guest was stopped by a trap — a limit overrun, a runtime error, or a
    /// host-ordered terminate. The string is for the *operator's* log.
    ///
    /// It is deliberately not the thing a caller is shown: an interpreter trap
    /// message describes the guest's internals, and the caller of a mini app's
    /// action has no business reading them.
    Trapped(String),
    /// The guest exceeded [`InvokeLimits::max_host_calls`] in one invocation.
    TooManyHostCalls,
}

/// Bounds on a single invocation, independent of the VM's own instruction and
/// memory budgets.
#[derive(Debug, Clone)]
pub struct InvokeLimits {
    /// How many host calls one invocation may make.
    ///
    /// The instruction budget does not bound this: a guest that loops on
    /// `kv.get` spends most of its time in *host* code, and each round trip
    /// costs the host far more than it costs the guest's budget. This is the
    /// backstop for that asymmetry.
    pub max_host_calls: u32,
}

impl Default for InvokeLimits {
    fn default() -> Self {
        InvokeLimits {
            max_host_calls: 10_000,
        }
    }
}

/// Run `function` on an already-registered, already-governed VM, servicing
/// every host call it makes.
///
/// The VM must already have its capability posture and resource limits applied
/// — this function deliberately does not set them, so there is no path where an
/// invocation runs before its governance does.
pub fn invoke(
    machine_id: &str,
    function: &str,
    args: &Value,
    services: &mut dyn HostServices,
    limits: &InvokeLimits,
    cold_start: bool,
) -> Outcome {
    let mut host_calls = 0u32;

    // Module initialisation, on a cold instance only.
    //
    // A warm instance has already run its top level, and running it again is
    // not merely wasteful — it is wrong. The executor's scope stack is unwound
    // when the top level completes, so a second global run reaches for a scope
    // that is no longer there. Skipping it *is* the warm path: the whole value
    // of a warm instance is that this work is already done.
    //
    // A module's own host calls are serviced like any other — a module that
    // logs at load time is ordinary code, not an error.
    if cold_start {
        let mut result = api::execute_vm(machine_id.to_string());
        match pump(machine_id, &mut result, services, limits, &mut host_calls) {
            Ok(()) => {}
            Err(outcome) => return outcome,
        }
        if let Some(trap) = api::trap_reason(machine_id) {
            return Outcome::Trapped(trap);
        }
    }

    let mut result = api::execute_vm_func_with_input(
        machine_id.to_string(),
        function.to_string(),
        args.to_string(),
        1,
    );
    match pump(machine_id, &mut result, services, limits, &mut host_calls) {
        Ok(()) => {}
        Err(outcome) => return outcome,
    }
    if let Some(trap) = api::trap_reason(machine_id) {
        return Outcome::Trapped(trap);
    }

    Outcome::Returned(parse_result(&result.result_value))
}

/// Service host calls until the VM stops asking.
fn pump(
    machine_id: &str,
    result: &mut api::VmExecResult,
    services: &mut dyn HostServices,
    limits: &InvokeLimits,
    host_calls: &mut u32,
) -> Result<(), Outcome> {
    while result.has_host_call {
        *host_calls += 1;
        if *host_calls > limits.max_host_calls {
            // Stop the guest rather than merely refusing the call: a guest that
            // has hit this bound is looping, and answering it forever is the
            // failure mode the bound exists to prevent.
            api::terminate_vm(machine_id);
            return Err(Outcome::TooManyHostCalls);
        }

        let reply = match HostCall::parse(&result.host_call_data) {
            Some(call) => services.service(&call),
            // An envelope the host cannot parse is a host bug, not a guest one.
            // Answer null so the guest continues deterministically rather than
            // hanging, and let the operator find it in the log.
            None => {
                services.log(&format!(
                    "unparseable host-call envelope: {}",
                    result.host_call_data
                ));
                Value::Null
            }
        };

        *result = api::continue_execution(machine_id.to_string(), reply.to_string());
    }
    Ok(())
}

/// The VM stringifies its return value; recover it as JSON.
fn parse_result(raw: &str) -> Value {
    // The VM writes `"[undefined]"` for a value with no JSON form — a function
    // that fell off its end, or a host call the capability gate short-circuited.
    // That is a null to a caller, not the literal text.
    if raw.is_empty() || raw == r#""[undefined]""# {
        return Value::Null;
    }
    // Anything else that does not parse is handed back as a JSON string rather
    // than discarded: losing a guest's value silently is worse than passing it
    // through in a form the caller can see.
    serde_json::from_str(raw).unwrap_or_else(|_| json!(raw))
}
