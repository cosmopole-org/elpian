//! Every guest prelude must compile.
//!
//! `guest-sdk/` is the authoring surface a mini app is written against —
//! 450 KB of JavaScript and Dart embedded into these crates with
//! `include_str!`. It is not host code and cannot be checked by the Dart or
//! JavaScript analyzers (it calls VM intrinsics like `askHost` that no SDK
//! defines), so the only thing that can tell us it is valid is the front-end
//! that compiles it.
//!
//! Until this file existed, only some of it was ever compiled. The SDK was
//! five preludes then, and coverage was accidental: `godot.js`, `ui.js` and
//! `net.js` were exercised because tests happened to import them, `react.js`
//! only because a fixture pulled it in, and `caspar.js` and `flutter.js` — 55
//! KB — by nothing at all. Four of those five are now merged into `gui.js`,
//! which every test here compiles, so the accident is gone; what remains is
//! this file making it deliberate.
//!
//! These tests compile each prelude on its own. They check the *front-end*
//! accepts it, not that it behaves correctly at runtime — the behavioural
//! tests are the multi_vm / js_guest suites.

use elpian_godot::{
    compose_godot_program, compose_godot_program_js, GODOT_CASPAR_JS, GODOT_GUI_JS, GODOT_NET_JS,
};

/// Every JavaScript prelude, with the imports it depends on.
///
/// The composer resolves `import 'x.js'` by prepending that prelude, so a
/// prelude that builds on another is compiled together with it — which is how
/// a real mini app would receive it.
fn js_preludes() -> Vec<(&'static str, &'static str, &'static str)> {
    vec![
        // (name, the import line a guest would write, the source itself)
        ("gui.js", "import 'gui.js';", GODOT_GUI_JS),
        ("net.js", "import 'net.js';", GODOT_NET_JS),
        ("caspar.js", "import 'caspar.js';", GODOT_CASPAR_JS),
    ]
}

#[test]
fn every_javascript_prelude_is_present_and_non_empty() {
    // A moved or renamed file would make `include_str!` fail the build, but an
    // *emptied* one would not — and an empty prelude compiles fine while
    // leaving every guest that imports it broken.
    for (name, _, src) in js_preludes() {
        assert!(
            src.len() > 1000,
            "{name} is {} bytes — that is not a prelude",
            src.len()
        );
    }
}

#[test]
fn every_javascript_prelude_compiles() {
    let mut failures = Vec::new();

    for (name, import, src) in js_preludes() {
        // Compose exactly as a guest importing it would: the composer pulls in
        // the prelude and its dependencies, then the (here trivial) program.
        let program = format!("{import}\nvar __probe = 1;");
        let composed = compose_godot_program_js(&program);

        // Guard against a vacuous pass. The composer only prepends a prelude
        // when it sees the matching import, so a typo in the import name — or
        // the composer quietly dropping one — would leave this compiling a
        // trivial program and reporting success. Check the source is actually
        // in there before believing the result.
        let marker: String = src
            .lines()
            .find(|l| {
                l.trim_start().starts_with("function ") || l.trim_start().starts_with("const ")
            })
            .unwrap_or("")
            .trim()
            .chars()
            .take(40)
            .collect();
        assert!(
            !marker.is_empty() && composed.contains(&marker),
            "{name} was not composed into the program — the test would have \
             passed without ever compiling it"
        );

        match js2elpian::try_parse_js(&composed) {
            Ok(_) => {}
            Err(e) => failures.push(format!("{name}: {e}")),
        }
    }

    assert!(
        failures.is_empty(),
        "these guest preludes do not compile:\n  {}",
        failures.join("\n  ")
    );
}

#[test]
fn the_javascript_preludes_reach_bytecode_not_just_the_ast() {
    // Parsing is not the whole front-end: a construct can lower to an AST the
    // bytecode compiler then rejects. The preludes that carry the most surface
    // are checked all the way through.
    for name in ["gui.js", "net.js", "caspar.js"] {
        let import = format!("import '{name}';");
        let composed = compose_godot_program_js(&format!("{import}\nvar __probe = 1;"));
        assert!(
            js2elpian::compile_js_to_bytecode(&composed).is_some(),
            "{name} parses but does not compile to bytecode"
        );
    }
}

#[test]
fn the_dart_prelude_compiles() {
    let composed = compose_godot_program("void main() { var probe = 1; }");
    match dart2elpian::transpile(&composed) {
        Ok(js) => {
            // The Dart front-end lowers to the JS subset, so a clean transpile
            // is only half the answer — the result must survive js2elpian too.
            assert!(
                js2elpian::try_parse_js(&js).is_ok(),
                "godot.dart transpiles but its output does not compile"
            );
        }
        Err(e) => panic!("godot.dart does not transpile: {e}"),
    }
}

#[test]
fn a_client_prelude_pulls_in_the_sdk_it_calls_through() {
    // The one dependency rule left: `net.js` and `caspar.js` reach the engine
    // through `GD`, which lives in gui.js. If that stopped being composed they
    // would compile alone and fail at the first request.
    for import in ["net.js", "caspar.js"] {
        let composed = compose_godot_program_js(&format!("import '{import}';\nvar a = 1;"));
        assert!(
            composed.contains("class GD {"),
            "importing {import} should also compose the SDK it calls through"
        );
        assert!(
            js2elpian::try_parse_js(&composed).is_ok(),
            "{import} + the SDK should compile together"
        );
    }
}

/// Every `askHost` name the preludes actually call must be a name the VM
/// documents and can gate.
///
/// This is the check that was missing. 20 of the 21 host APIs the preludes
/// call — the whole `vm.*` control surface a guest steers its children with,
/// and the `godot.*`/`flutter.*`/`rn.*` op seams it draws through — appeared
/// in no list, had no capability, and were absent from the generated Dart
/// catalog. They worked anyway, because the list they were missing from turned
/// out to gate nothing: it was threaded into the executor as `_allowed_api`
/// and never read. A guest calling an undocumented name reached the host just
/// the same.
///
/// That made the omission invisible *and* consequential: a super app could not
/// deny a mini app the drawing surface or the ability to spawn children,
/// because neither had a capability to deny.
#[test]
fn every_host_api_the_preludes_call_is_documented_and_gateable() {
    use std::collections::BTreeSet;

    let advertised: BTreeSet<String> = elpian_vm::api::all_host_apis().into_iter().collect();

    // Scan the preludes for `askHost("name"` / `askHost('name'`.
    let mut called: BTreeSet<String> = BTreeSet::new();
    for src in [
        GODOT_GUI_JS,
        GODOT_NET_JS,
        GODOT_CASPAR_JS,
        elpian_godot::GODOT_PRELUDE,
    ] {
        let mut rest = src;
        while let Some(i) = rest.find("askHost(") {
            rest = &rest[i + "askHost(".len()..];
            let bytes = rest.as_bytes();
            if bytes.is_empty() {
                break;
            }
            let quote = bytes[0] as char;
            if quote != '"' && quote != '\'' {
                continue;
            }
            if let Some(end) = rest[1..].find(quote) {
                let name = &rest[1..1 + end];
                // Only literal, dotted-or-bare api names; anything built at
                // runtime is out of scope for a static check.
                if !name.is_empty()
                    && name
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_')
                {
                    called.insert(name.to_string());
                }
            }
        }
    }

    assert!(
        called.len() > 15,
        "the scan found only {} names — it is probably not matching: {called:?}",
        called.len()
    );

    let undocumented: Vec<&String> = called.difference(&advertised).collect();
    assert!(
        undocumented.is_empty(),
        "these host APIs are called by a guest prelude but appear in no\n\
         `all_host_apis()` entry, so they have no capability and are missing\n\
         from the generated Dart catalog: {undocumented:?}"
    );

    // And none of them may sit in the catch-all gate: a super app has to be
    // able to deny the drawing surface without denying everything.
    let ungated: Vec<&String> = called
        .iter()
        .filter(|n| {
            *n != "stringify"
                && elpian_vm::api::Capability::for_api(n) == elpian_vm::api::Capability::Other
        })
        .collect();
    assert!(
        ungated.is_empty(),
        "these prelude host APIs fall through to the catch-all capability, so \
         they cannot be denied individually: {ungated:?}"
    );
}
