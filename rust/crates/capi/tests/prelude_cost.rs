//! What the SDK costs a mini app.
//!
//! A prelude is not free. Every byte of it is parsed and compiled into
//! bytecode when the VM is created, and every top-level statement in it runs
//! before the guest's first line — inside the same instruction budget the
//! governor meters the mini app against. A super app that gives a small app a
//! small budget is giving it a budget the prelude spends first.
//!
//! There used to be five entry points, and this file argued for keeping them:
//! a guest that only drove engine nodes should not pay for a reconciler and a
//! widget kit it never called. The SDK is now one file, `gui.js`, and that
//! argument is settled the other way — every guest pays the whole thing.
//!
//! Which makes measuring it more important, not less. What this pins is that
//! the single door's cost is known, and that `net.js` and `caspar.js` add only
//! their own weight on top of it rather than a second copy of the SDK.

use elpian_godot::compose_godot_program_js;

/// Compile one entry point and report (source bytes, bytecode length).
fn cost(import: &str) -> (usize, usize) {
    let composed = compose_godot_program_js(&format!("{import}\nvar __probe = 1;"));
    let bc = js2elpian::compile_js_to_bytecode(&composed)
        .unwrap_or_else(|| panic!("{import} should compile"));
    (composed.len(), bc.len())
}

#[test]
fn the_whole_sdk_is_what_every_guest_pays_and_it_is_this_much() {
    let (gui_src, gui_bc) = cost("import 'gui.js';");
    println!("gui.js  {gui_src:>7} bytes -> {gui_bc:>7} bytecode");

    // A ceiling, not a target. It is deliberately loose — this is here to catch
    // the SDK doubling, not to argue about a few kilobytes. If a change trips
    // it, the question to answer is whether every mini app should carry what
    // was just added, and the number goes up only once that answer is yes.
    assert!(
        gui_src < 500_000,
        "the SDK composes {gui_src} bytes — every mini app now pays this before \
         its first line runs. Raise the bound deliberately, or don't add it."
    );
    assert!(
        gui_bc < 600_000,
        "the SDK compiles to {gui_bc} bytes of bytecode — see above"
    );
}

#[test]
fn net_and_caspar_add_their_own_weight_and_not_a_second_sdk() {
    // Both reach the engine through `GD`, which lives in gui.js, so both
    // compose it beneath them. Composing it *twice* would still compile — the
    // front-end resolves names late and the later definition would simply win —
    // and would silently double what a networking guest pays.
    let (gui, _) = cost("import 'gui.js';");
    for import in ["import 'net.js';", "import 'caspar.js';"] {
        let (with, _) = cost(import);
        assert!(
            with > gui,
            "{import} composes {with} bytes, no more than gui.js alone ({gui}) \
             — it is not getting the engine transport it calls through"
        );
        assert!(
            with < gui * 2,
            "{import} composes {with} bytes against gui.js's {gui} — that is \
             close to two copies of the SDK, not one plus a client"
        );
    }
}

#[test]
fn every_entry_point_composes_the_whole_sdk_exactly_once() {
    // The three doors that remain, and what each must contain. `gui.js` is the
    // SDK; `net.js` and `caspar.js` are clients layered on it.
    let cases: &[(&str, &[&str])] = &[
        ("import 'gui.js';", &[]),
        ("import 'net.js';", &["var Net = {}"]),
        ("import 'caspar.js';", &["var Caspar = {}"]),
    ];

    // One marker from each of the four preludes merged into gui.js, so a
    // section going missing in a future edit is caught here rather than at a
    // guest's first render.
    let sdk = [
        "class GD {",
        "function __flEl(",
        "var VUI = {}",
        "function __vrDriverCreate(",
        "function defineWidget(",
    ];

    for (import, extra) in cases {
        let composed = compose_godot_program_js(&format!("{import}\nvar a = 1;"));
        for m in sdk {
            assert_eq!(
                composed.matches(m).count(),
                1,
                "{import} composes {m:?} {} times — it must appear exactly once",
                composed.matches(m).count()
            );
        }
        for m in *extra {
            assert!(composed.contains(m), "{import} should compose {m:?}");
        }
    }
}
