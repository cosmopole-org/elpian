//! Guest turns must be able to run at the same time.
//!
//! The registry used to be one `Mutex<HashMap<String, VM>>` whose lock was held
//! for the whole of a guest turn, so every instance in the process executed in
//! strict sequence no matter how many threads drove them, and one instance in a
//! long loop blocked every unrelated call — including the ones a host would use
//! to inspect or stop it.
//!
//! # These are proofs, not measurements
//!
//! An earlier version of this file asserted a *speedup*: run two turns
//! sequentially, run them again on two threads, and require the second to be
//! meaningfully faster. That was the wrong instrument twice over.
//!
//! * Cargo runs this file's tests on parallel threads in one process, and the
//!   others here deliberately burn CPU. On a two-core runner the measurement
//!   was competing with its own siblings, so it reported ~1.1x and failed a
//!   0.8x threshold — while the behaviour under test was perfectly correct.
//! * The work was sized by timing a calibration run, which is itself distorted
//!   by that contention. The binary took 5 seconds on one run and 182 on the
//!   next.
//!
//! Overlap is a *behavioural* property and can be proved by contradiction
//! without a stopwatch: if execution were serialised, a second instance could
//! not complete a turn while the first was still inside one. That is what
//! [`a_second_instance_runs_while_the_first_is_still_inside_a_turn`] asserts,
//! deterministically and with no threshold.
//!
//! Guest work here is bounded by an **instruction limit**, not by a
//! wall-clock-calibrated iteration count. A limit is the same on every machine,
//! so these tests take the same time on a fast laptop and a loaded CI runner,
//! and a guest that must stop always stops.

use elpian_vm::api::{self, ResourceLimits};
use serde_json::json;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::{Duration, Instant};

/// A program whose top level counts to `iterations` — a predictable chunk of
/// guest CPU with no host calls in it.
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

/// A loop long enough that it will not finish on its own during a test.
const EFFECTIVELY_UNBOUNDED: i64 = 4_000_000_000;

/// Register an instance that runs until stopped.
///
/// The instruction budget is a **backstop**, not the mechanism under test: if a
/// test's own stop fails, the guest traps here instead of running until the CI
/// job times out. It is generous enough that nothing reaches it while the tests
/// behave.
fn spawn_runaway(id: &str) {
    assert!(
        api::create_vm_from_ast(id.to_string(), busy_program(EFFECTIVELY_UNBOUNDED)),
        "busy program should compile"
    );
    api::set_limits(
        id,
        ResourceLimits {
            max_instructions: Some(500_000_000),
            ..ResourceLimits::unlimited()
        },
    );
}

/// Register an instance whose turn finishes quickly on its own.
fn spawn_quick(id: &str) {
    assert!(api::create_vm_from_ast(id.to_string(), busy_program(2_000)));
}

// ---- The overlap proof -----------------------------------------------------

/// Two guest turns really do run at the same time.
///
/// Proof by contradiction, with no timing threshold: instance A is put inside a
/// long turn on its own thread; instance B then completes a whole turn; and A is
/// confirmed to have *still been running* when B finished. Under the old global
/// lock B could not have started, let alone finished, until A was done.
///
/// The final check is what makes it airtight — without it the test would pass
/// vacuously if A had not actually begun.
#[test]
fn a_second_instance_runs_while_the_first_is_still_inside_a_turn() {
    spawn_runaway("par-first");
    spawn_quick("par-second");

    let first_finished = Arc::new(AtomicBool::new(false));
    let finished_flag = Arc::clone(&first_finished);
    let (entered_tx, entered_rx) = mpsc::channel();

    let first = thread::spawn(move || {
        entered_tx.send(()).expect("receiver alive");
        api::execute_vm("par-first".to_string());
        finished_flag.store(true, Ordering::SeqCst);
    });

    entered_rx.recv().expect("the first thread started");
    // Let it get properly inside the loop, so "still running" below is a
    // statement about a turn in flight rather than one about to begin.
    thread::sleep(Duration::from_millis(50));

    let started = Instant::now();
    api::execute_vm("par-second".to_string());
    let second_took = started.elapsed();

    assert!(
        !first_finished.load(Ordering::SeqCst),
        "the first instance finished before the second ran, so this proved nothing"
    );
    assert!(
        second_took < Duration::from_secs(30),
        "the second instance was blocked behind the first for {second_took:?}"
    );

    api::terminate_vm("par-first");
    first.join().expect("the terminated turn unwound cleanly");
    api::destroy_vm("par-first".into());
    api::destroy_vm("par-second".into());
}

/// The registry itself stays answerable while a guest is mid-turn.
///
/// Under the global lock these calls queued behind the running turn, which is
/// what made a runaway guest impossible to inspect or stop.
#[test]
fn the_registry_answers_while_a_guest_is_running() {
    spawn_runaway("par-inspect");

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-inspect".to_string());
    });
    rx.recv().expect("runner started");
    thread::sleep(Duration::from_millis(50));

    let started = Instant::now();
    assert!(api::vm_exists("par-inspect".into()));
    assert!(matches!(
        api::run_state("par-inspect"),
        Some(api::RunState::Running)
    ));
    let asked_in = started.elapsed();
    assert!(
        asked_in < Duration::from_secs(5),
        "inspecting a running instance took {asked_in:?}"
    );

    api::terminate_vm("par-inspect");
    runner.join().expect("the runner finished");
    api::destroy_vm("par-inspect".into());
}

// ---- Control that must reach a running guest -------------------------------

/// A terminate request must reach an instance that is *already inside* a turn,
/// not merely one parked between turns. This is what lets a host stop a runaway
/// guest at all.
#[test]
fn terminate_lands_on_an_instance_that_is_mid_turn() {
    spawn_runaway("par-runaway");

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-runaway".to_string());
    });
    rx.recv().expect("runner started");
    thread::sleep(Duration::from_millis(50));

    let started = Instant::now();
    assert!(
        api::terminate_vm("par-runaway"),
        "terminate reached the instance"
    );
    runner.join().expect("the terminated turn unwound cleanly");

    assert!(
        started.elapsed() < Duration::from_secs(30),
        "terminate did not stop the guest promptly: {:?}",
        started.elapsed()
    );
    assert!(matches!(
        api::run_state("par-runaway"),
        Some(api::RunState::Terminated)
    ));
    api::destroy_vm("par-runaway".into());
}

/// Unregistering an instance that is mid-turn must be safe and immediate: the
/// running turn holds its own handle and finishes, and the destroy does not
/// block on it.
///
/// Note the ordering. `destroy_vm` removes the entry, which takes the control
/// flag with it — so after destroying there is no longer any way to stop the
/// in-flight turn. The terminate therefore goes *first*; the instruction budget
/// on the instance is the backstop if it did not land.
#[test]
fn destroying_an_instance_mid_turn_is_clean() {
    spawn_runaway("par-doomed");

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-doomed".to_string());
    });
    rx.recv().expect("runner started");
    thread::sleep(Duration::from_millis(50));

    // Stop the turn first, while the control flag is still reachable.
    api::terminate_vm("par-doomed");

    let started = Instant::now();
    assert!(
        api::destroy_vm("par-doomed".into()),
        "destroy removed the entry"
    );
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "destroy blocked waiting for the running turn"
    );
    assert!(
        !api::vm_exists("par-doomed".into()),
        "the entry is gone immediately"
    );

    // The turn was still running against its own handle when the entry went.
    // It must unwind without panicking and without touching freed state.
    runner
        .join()
        .expect("the in-flight turn completed without panicking");
}

// ---- The measurement, kept out of the gate ---------------------------------

/// How much throughput actually improves with concurrency.
///
/// `#[ignore]`d deliberately. This is a *benchmark*: its result depends on the
/// machine's core count and on whatever else is running, including the other
/// tests in this file. Gating CI on it made a green build depend on how busy a
/// shared runner happened to be, which is how it failed at ~1.1x on a two-core
/// box while every behavioural property above held.
///
/// Run it on purpose, on an idle machine:
///
/// ```text
/// cargo test -p elpian-vm --test parallel_execution -- --ignored --nocapture
/// ```
#[test]
#[ignore = "a benchmark: depends on core count and machine load, so it is not a gate"]
fn measure_concurrency_speedup() {
    const ITERATIONS: i64 = 3_000_000;

    let run = |id: &str| {
        assert!(api::create_vm_from_ast(
            id.to_string(),
            busy_program(ITERATIONS)
        ));
    };

    run("bench-seq-a");
    run("bench-seq-b");
    let started = Instant::now();
    api::execute_vm("bench-seq-a".to_string());
    api::execute_vm("bench-seq-b".to_string());
    let sequential = started.elapsed();

    run("bench-par-a");
    run("bench-par-b");
    let started = Instant::now();
    let handles: Vec<_> = ["bench-par-a", "bench-par-b"]
        .into_iter()
        .map(|id| thread::spawn(move || api::execute_vm(id.to_string())))
        .collect();
    for handle in handles {
        handle.join().expect("no thread panicked");
    }
    let parallel = started.elapsed();

    println!(
        "\ncores: {}\nsequential: {sequential:?}\nparallel:   {parallel:?}\nspeedup:    {:.2}x",
        std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(0),
        sequential.as_secs_f64() / parallel.as_secs_f64().max(f64::MIN_POSITIVE),
    );

    for id in ["bench-seq-a", "bench-seq-b", "bench-par-a", "bench-par-b"] {
        api::destroy_vm(id.into());
    }
}
