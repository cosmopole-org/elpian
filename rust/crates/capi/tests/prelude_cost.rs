//! What each entry point costs a mini app.
//!
//! A prelude is not free. Every byte of it is parsed and compiled into
//! bytecode when the VM is created, and every top-level statement in it runs
//! before the guest's first line — inside the same instruction budget the
//! governor meters the mini app against. A super app that gives a small app a
//! small budget is giving it a budget the prelude spends first.
//!
//! That is the argument for keeping more than one entry point. `gui.js` is
//! what a UI mini app should import; a guest that only drives engine nodes, or
//! only talks to the network, should not have to pay for a reconciler and a
//! widget kit it never calls. This measures the gap so the claim is a number
//! rather than an intuition, and fails if the cheap door stops being cheap.

use elpian_godot::compose_godot_program_js;

/// Compile one entry point and report (source bytes, bytecode length).
fn cost(import: &str) -> (usize, usize) {
    let composed = compose_godot_program_js(&format!("{import}\nvar __probe = 1;"));
    let bc = js2elpian::compile_js_to_bytecode(&composed)
        .unwrap_or_else(|| panic!("{import} should compile"));
    (composed.len(), bc.len())
}

#[test]
fn the_engine_only_entry_point_stays_far_cheaper_than_the_gui_one() {
    let (engine_src, engine_bc) = cost("import 'godot.js';");
    let (gui_src, gui_bc) = cost("import 'gui.js';");

    println!("godot.js  {engine_src:>7} bytes -> {engine_bc:>7} bytecode");
    println!("gui.js    {gui_src:>7} bytes -> {gui_bc:>7} bytecode");

    // The whole UI stack is several times the engine bridge alone. If that
    // ratio ever collapses, the reason for two entry points has gone with it
    // and gui.js should simply become the only one.
    assert!(
        gui_src > engine_src * 3,
        "gui.js composes {gui_src} bytes against godot.js's {engine_src} — no \
         longer enough of a difference to justify two entry points"
    );
    assert!(
        gui_bc > engine_bc * 2,
        "gui.js compiles to {gui_bc} against godot.js's {engine_bc} — the \
         engine-only door has stopped being the cheap one"
    );
}

#[test]
fn every_entry_point_composes_only_what_it_needs() {
    // Each import pulls its dependencies and nothing else. A prelude quietly
    // acquiring another one costs every guest that imports it, forever, and
    // the only place it would show is here.
    let cases: &[(&str, &[&str], &[&str])] = &[
        // (import, must contain, must not contain)
        (
            "import 'godot.js';",
            &["class GD {"],
            &["var VUI = {}", "__vrDriverCreate"],
        ),
        (
            "import 'net.js';",
            &["class GD {"],
            &["var VUI = {}", "__vrDriverCreate"],
        ),
        (
            "import 'caspar.js';",
            &["class GD {"],
            &["var VUI = {}", "__vrDriverCreate"],
        ),
        (
            "import 'flutter.js';",
            &["class GD {", "function __flEl("],
            &["var VUI = {}"],
        ),
        (
            "import 'ui.js';",
            &["class GD {", "var VUI = {}"],
            &["__vrDriverCreate"],
        ),
        (
            "import 'react.js';",
            &["var VUI = {}", "function __vrDriverCreate("],
            &["function defineWidget("],
        ),
        (
            "import 'gui.js';",
            &[
                "class GD {",
                "function __flEl(",
                "var VUI = {}",
                "function __vrDriverCreate(",
                "function defineWidget(",
            ],
            &[],
        ),
    ];

    for (import, wanted, unwanted) in cases {
        let composed = compose_godot_program_js(&format!("{import}\nvar a = 1;"));
        for m in *wanted {
            assert!(composed.contains(m), "{import} should compose {m:?}");
        }
        for m in *unwanted {
            assert!(
                !composed.contains(m),
                "{import} composes {m:?}, which it does not need"
            );
        }
    }
}
