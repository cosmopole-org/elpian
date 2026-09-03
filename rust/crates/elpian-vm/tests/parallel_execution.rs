//! Guest turns must be able to run at the same time.
//!
//! The registry used to be one `Mutex<HashMap<String, VM>>` whose lock was held
//! for the whole of a guest turn, so every instance in the process executed in
//! strict sequence no matter how many threads drove them, and one instance in a
//! long loop blocked every unrelated call — including the ones a host would use
//! to inspect or stop it. These tests fail against that design and pass against
//! the sharded registry.
//!
//! Timings are deliberately loose. The claim under test is "these overlap", not
//! "these are fast", so the thresholds only have to separate *concurrent* from
//! *serialised* — a factor of two apart at minimum — and not be sensitive to
//! how quick the machine is.

use elpian_vm::api;
use serde_json::json;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

/// A program whose top level counts to `iterations` — a predictable, sizeable
/// chunk of guest CPU with no host calls in it.
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

fn spawn_busy(id: &str, iterations: i64) {
    assert!(
        api::create_vm_from_ast(id.to_string(), busy_program(iterations)),
        "busy program should compile"
    );
}

/// Wall time of one top-level run.
fn time_run(id: &str) -> Duration {
    let started = Instant::now();
    api::execute_vm(id.to_string());
    started.elapsed()
}

/// Calibrate an iteration count that takes a measurable but bounded time on
/// this machine, so the test is neither flaky on a slow box nor slow on a fast
/// one.
fn calibrated_iterations() -> i64 {
    let probe = 200_000;
    spawn_busy("par-probe", probe);
    let elapsed = time_run("par-probe");
    api::destroy_vm("par-probe".into());

    // Aim for roughly 300ms of guest CPU per instance.
    let per_iter = elapsed.as_secs_f64() / probe as f64;
    let target = (0.3 / per_iter.max(f64::MIN_POSITIVE)) as i64;
    target.clamp(probe, 20_000_000)
}

#[test]
fn two_guest_turns_overlap_in_wall_time() {
    let iterations = calibrated_iterations();

    // Baseline: the same two runs back to back on one thread.
    spawn_busy("par-seq-a", iterations);
    spawn_busy("par-seq-b", iterations);
    let sequential = time_run("par-seq-a") + time_run("par-seq-b");
    api::destroy_vm("par-seq-a".into());
    api::destroy_vm("par-seq-b".into());

    // The same work, two threads.
    spawn_busy("par-par-a", iterations);
    spawn_busy("par-par-b", iterations);
    let started = Instant::now();
    let handles: Vec<_> = ["par-par-a", "par-par-b"]
        .into_iter()
        .map(|id| thread::spawn(move || api::execute_vm(id.to_string())))
        .collect();
    for h in handles {
        h.join().expect("guest turn should not panic the driving thread");
    }
    let parallel = started.elapsed();
    api::destroy_vm("par-par-a".into());
    api::destroy_vm("par-par-b".into());

    // Serialised, `parallel` would match `sequential`. Genuinely overlapped, it
    // approaches half. Assert only that it is clearly under — 80% leaves room
    // for a busy CI box without admitting a serialised result.
    assert!(
        parallel.as_secs_f64() < sequential.as_secs_f64() * 0.8,
        "two turns did not overlap: {parallel:?} parallel vs {sequential:?} sequential \
         ({iterations} iterations each)"
    );
}

/// The property that actually matters operationally: one instance grinding away
/// must not stop the host doing anything else. Under the global lock this
/// deadlocked the *whole registry* for the duration of the loop.
#[test]
fn a_long_running_guest_does_not_block_other_instances() {
    let iterations = calibrated_iterations() * 4; // long enough to still be running
    spawn_busy("par-hog", iterations);
    spawn_busy("par-quick", 1_000);

    let (tx, rx) = mpsc::channel();
    let hog = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-hog".to_string());
    });

    // Wait until the hog thread has entered the runtime, then insist an
    // unrelated instance completes a turn while it is still in there.
    rx.recv().expect("hog thread started");
    let quick = time_run("par-quick");
    assert!(
        quick < Duration::from_secs(5),
        "an unrelated instance was blocked behind a busy one for {quick:?}"
    );

    // And the registry itself stays responsive mid-turn.
    assert!(api::vm_exists("par-hog".into()));
    assert!(api::usage("par-hog").is_some(), "usage readable mid-turn");

    api::terminate_vm("par-hog");
    hog.join().expect("hog thread finished");
    api::destroy_vm("par-hog".into());
    api::destroy_vm("par-quick".into());
}

/// A terminate request must reach an instance that is *already inside* a turn,
/// not merely one parked between turns. This is what lets a host stop a runaway
/// guest at all.
#[test]
fn terminate_lands_on_an_instance_that_is_mid_turn() {
    // Big enough that it would run for many seconds if left alone.
    spawn_busy("par-runaway", calibrated_iterations() * 200);

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-runaway".to_string());
    });
    rx.recv().expect("runner started");

    // Give it a moment to be well inside the loop, then pull the plug.
    let started = Instant::now();
    while started.elapsed() < Duration::from_millis(50) {
        std::hint::spin_loop();
    }
    assert!(api::terminate_vm("par-runaway"), "terminate reached the instance");

    runner.join().expect("the terminated turn unwound cleanly");
    assert!(
        started.elapsed() < Duration::from_secs(10),
        "terminate did not stop the guest promptly"
    );
    assert!(matches!(
        api::run_state("par-runaway"),
        Some(api::RunState::Terminated)
    ));
    api::destroy_vm("par-runaway".into());
}

/// Unregistering an instance that is mid-turn must be safe: the running turn
/// holds its own handle and finishes, and the destroy does not block on it.
#[test]
fn destroying_an_instance_mid_turn_is_clean() {
    spawn_busy("par-doomed", calibrated_iterations() * 200);

    let (tx, rx) = mpsc::channel();
    let runner = thread::spawn(move || {
        tx.send(()).expect("receiver alive");
        api::execute_vm("par-doomed".to_string());
    });
    rx.recv().expect("runner started");

    let started = Instant::now();
    assert!(api::destroy_vm("par-doomed".into()), "destroy removed the entry");
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "destroy blocked waiting for the running turn"
    );
    assert!(!api::vm_exists("par-doomed".into()), "entry is gone immediately");

    // The turn is still running against its own handle; stop it so the test
    // does not hang, then confirm the thread unwinds without a panic.
    api::terminate_vm("par-doomed"); // no-op: already unregistered
    runner.join().expect("the in-flight turn completed without panicking");
}
