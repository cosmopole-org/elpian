//! The Dart host-API catalog must stay in step with the VM's own list.
//!
//! `lib/src/vm/host_api_catalog.dart` used to be maintained by hand alongside
//! `api::all_host_apis()`. The two drifted: 34 APIs the VM advertised — every
//! `fs.*`, `net.*`, `gpu.*`, `time.*`, `random.*`, `task.*` and `host.*` name,
//! plus `log` and `vm.import` — had no presence on the Dart side at all, so a
//! guest calling `time.now()` fell through `HostHandler`'s `default` branch and
//! silently received `0`.
//!
//! It is now generated. This test fails the build when the checked-in file
//! drifts from what the generator would write.

use elpian_vm::api::catalog::dart_catalog;
use elpian_vm::api::{all_host_apis, Capability};

/// Where the generated catalog lives.
///
/// Resolved from `CARGO_MANIFEST_DIR` rather than the process working
/// directory, so the test does not break the next time the crate moves within
/// the workspace — which is exactly what happened when `elpian-vm` moved under
/// `crates/`.
fn catalog_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../lib/src/vm/host_api_catalog.dart")
}

#[test]
fn the_checked_in_catalog_is_current() {
    let path = catalog_path();
    let on_disk = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    let expected = dart_catalog();

    if on_disk != expected {
        // Show the first divergence rather than dumping both files.
        let first_diff = on_disk
            .lines()
            .zip(expected.lines())
            .enumerate()
            .find(|(_, (a, b))| a != b)
            .map(|(n, (a, b))| format!("line {}:\n  on disk:  {a}\n  expected: {b}", n + 1))
            .unwrap_or_else(|| {
                format!(
                    "same prefix, different length ({} vs {} lines)",
                    on_disk.lines().count(),
                    expected.lines().count()
                )
            });
        panic!(
            "{} is stale.\n\n{first_diff}\n\nRegenerate it:\n    \
             cd rust && cargo run --bin gen-host-api-catalog -- \
             ../lib/src/vm/host_api_catalog.dart\n",
            path.display()
        );
    }
}

#[test]
fn every_advertised_api_lands_on_a_specific_gate() {
    // `Other` is the fail-safe for names the VM does not know, not a bucket for
    // real APIs. Before the split it held 98 of them — the whole surface the
    // Flutter engine actually uses — which made the gate useless: a host could
    // not deny the document tree without also denying rendering and timers.
    //
    // `stringify` is the one deliberate exception: a pure formatting helper
    // with no side effect to gate.
    const UNGATED_BY_DESIGN: &[&str] = &["stringify"];

    let parked: Vec<String> = all_host_apis()
        .into_iter()
        .filter(|name| Capability::for_api(name) == Capability::Other)
        .filter(|name| !UNGATED_BY_DESIGN.contains(&name.as_str()))
        .collect();

    assert!(
        parked.is_empty(),
        "these advertised APIs fall through to the catch-all gate, so a host \
         cannot deny them individually: {parked:?}\n\nGive each a family in \
         `Capability::for_api`, or add it to UNGATED_BY_DESIGN with a reason."
    );
}

#[test]
fn the_catalog_names_every_advertised_api() {
    let dart = dart_catalog();
    for name in all_host_apis() {
        assert!(
            dart.contains(&format!("'{name}'")),
            "{name} is advertised by the VM but missing from the generated catalog"
        );
    }
}
