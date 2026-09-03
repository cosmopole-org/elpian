//! The supervisor must be able to stop a guest that is *currently running*.
//!
//! This is the property that makes a wall-clock deadline mean anything. An
//! instruction budget bounds how much a guest computes; it does nothing about a
//! guest that holds an instance for a long time, and nothing at all about one
//! parked in a host call that never returns. Both are ordinary failure modes
//! for submitted server code.

use elpian_vm::api;
use elpian_vm::api::supervisor::{sweep, Supervisor, SupervisorConfig};
use serde_json::json;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

fn busy_program(iterations: i64) -> String {
    json!({
        "type": "program",
        "body": [
            { "type": "definition", "data": {
                "leftSide": { "type": "identifier", "data": { "name": "i" } },
                "rightSide": { "type": "i64", "data": { "value": 0 } } } },
            { "type": "loopStmt", "data": {
                "condition": { "type": "arithmetic", "data": {
                    "operation": "<",
                    "operand1": { "type": "identifier", "data": { "name": "i" } },
                    "operand2": { "type": "i64", "data": { "value": iterations } } } },
                "body": [
                    { "type": "assignment", "data": {
                        "leftSide": { "type": "identifier", "data": { "name": "i" } },
                        "rightSide": { "type": "arithmetic", "data": {
                            "operation": "+",
                            "operand1": { "type": "identifier", "data": { "name": "i" } },
                            "operand2": { "type": "i64", "data": { "value": 1 } } } } } }
                ] } }
        ]
    })
    .to_string()
}

/// Big enough that it would run for many seconds if nothing stopped it.
const RUNAWAY: i64 = 4_000_000_000;

fn spawn(id: &str, iterations: i64) {
    assert!(api::create_vm_from_ast(
        id.to_string(),
        busy_program(iterations)
    ));
}

#[test]
fn a_running_turn_is_terminated_when_it_overruns_its_deadline() {
    spawn("sup-runaway", RUNAWAY);

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).unwrap();
        api::execute_vm("sup-runaway".to_string())
    });
    rx.recv().unwrap();

    let config = SupervisorConfig {
        interval: Duration::from_millis(20),
        turn_deadline: Some(Duration::from_millis(100)),
        enforce_tree_budgets: false,
        idle_after: None,
    };

    let started = Instant::now();
    let supervisor = Supervisor::start(config, |_| {});
    runner.join().expect("the terminated turn unwound cleanly");
    let elapsed = started.elapsed();
    supervisor.stop();

    assert!(
        elapsed < Duration::from_secs(5),
        "the deadline did not stop the guest; it ran for {elapsed:?}"
    );
    assert!(matches!(
        api::run_state("sup-runaway"),
        Some(api::RunState::Terminated)
    ));
    api::destroy_vm("sup-runaway".into());
}

/// The deadline must not fire on an instance that is merely *registered*. Only
/// a turn actually in flight is on the clock.
#[test]
fn an_idle_instance_is_never_deadline_terminated() {
    spawn("sup-idle", 10);
    api::execute_vm("sup-idle".to_string()); // one quick, completed turn

    let config = SupervisorConfig {
        interval: Duration::from_millis(10),
        turn_deadline: Some(Duration::from_millis(1)),
        enforce_tree_budgets: false,
        idle_after: None,
    };
    // Several sweeps, well past a 1ms deadline, with the instance sitting idle.
    for _ in 0..5 {
        let report = sweep(&config);
        assert!(
            !report
                .deadline_terminated
                .iter()
                .any(|(id, _)| id == "sup-idle"),
            "an idle instance was terminated: {:?}",
            report.deadline_terminated
        );
    }
    assert!(matches!(
        api::run_state("sup-idle"),
        Some(api::RunState::Running)
    ));
    api::destroy_vm("sup-idle".into());
}

/// A completed turn must clear its own busy marker, or the instance looks
/// permanently overrunning from the next sweep onwards.
#[test]
fn a_finished_turn_leaves_the_instance_off_the_clock() {
    spawn("sup-clean", 1_000);
    api::execute_vm("sup-clean".to_string());

    let config = SupervisorConfig {
        interval: Duration::from_millis(10),
        turn_deadline: Some(Duration::from_millis(1)),
        enforce_tree_budgets: false,
        idle_after: Some(Duration::from_millis(0)),
    };
    let report = sweep(&config);
    assert!(
        !report
            .deadline_terminated
            .iter()
            .any(|(id, _)| id == "sup-clean"),
        "a finished instance was put on the deadline clock: {:?}",
        report.deadline_terminated
    );
    assert!(
        report.idle_candidates.iter().any(|id| id == "sup-clean"),
        "a finished instance should be reported idle, got {:?}",
        report.idle_candidates
    );
    api::destroy_vm("sup-clean".into());
}

/// The sweep must never block behind the instance it is policing. Under the old
/// registry it would have queued on the global lock the runaway turn was
/// holding — the supervisor would deadlock against its own subject.
#[test]
fn the_sweep_does_not_block_behind_a_running_turn() {
    spawn("sup-hog", RUNAWAY);

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).unwrap();
        api::execute_vm("sup-hog".to_string())
    });
    rx.recv().unwrap();

    // A sweep with no deadline: it must observe the busy instance and return
    // promptly without stopping it and without waiting for it.
    let observing = SupervisorConfig {
        interval: Duration::from_millis(10),
        turn_deadline: None,
        enforce_tree_budgets: true,
        idle_after: None,
    };
    let started = Instant::now();
    let report = sweep(&observing);
    let swept_in = started.elapsed();

    assert!(
        swept_in < Duration::from_millis(500),
        "the sweep blocked for {swept_in:?} behind a running turn"
    );
    assert!(!report
        .deadline_terminated
        .iter()
        .any(|(id, _)| id == "sup-hog"));

    api::terminate_vm("sup-hog");
    runner.join().unwrap();
    api::destroy_vm("sup-hog".into());
}
