//! The Rust half of the shared policy conformance corpus.
//!
//! The Dart half is `test/policy_conformance_test.dart` and reads the same
//! file. A case that passes here and fails there — or the reverse — means an
//! app would hold different capabilities on a phone than on the host, which is
//! exactly the class of bug this corpus exists to catch. The `surface`
//! capability being present in the VM and absent from the Dart enum was one.

use std::collections::BTreeSet;

use elpian_host::policy::{capabilities_from_names, Grant, Manifest, Policy};
use elpian_vm::api::ResourceLimits;
use serde_json::Value;

fn corpus() -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../test/fixtures/policy_corpus.json");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    serde_json::from_str(&raw).expect("the corpus should be valid JSON")
}

fn names(value: Option<&Value>) -> Vec<&str> {
    value
        .and_then(Value::as_array)
        .map(|items| items.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default()
}

fn limits_from(value: Option<&Value>) -> Option<ResourceLimits> {
    let map = value?.as_object()?;
    let axis = |name: &str| -> Option<u64> {
        // A key that is present and null means "unbounded on this axis", which
        // is a different statement from the key being absent. Both land as
        // `None` here; the corpus distinguishes them in the *expectation*.
        map.get(name).and_then(Value::as_u64)
    };
    Some(ResourceLimits {
        max_instructions: axis("maxInstructions"),
        max_instructions_per_turn: axis("maxInstructionsPerTurn"),
        max_memory_bytes: axis("maxMemoryBytes"),
        max_storage_bytes: axis("maxStorageBytes"),
        max_call_depth: axis("maxCallDepth"),
    })
}

#[test]
fn every_corpus_case_resolves_as_specified() {
    let corpus = corpus();
    let cases = corpus["cases"].as_array().expect("cases array");
    assert!(cases.len() >= 16, "the corpus lost cases: {}", cases.len());

    for case in cases {
        let name = case["name"].as_str().unwrap_or("<unnamed>");

        let manifest = Manifest {
            id: "corpus".into(),
            version: "1.0.0".into(),
            requested_capabilities: capabilities_from_names(names(
                case["manifest"].get("requestedCapabilities"),
            )),
            requested_limits: limits_from(case["manifest"].get("requestedLimits")),
            allows_children: case["manifest"]["allowsChildren"]
                .as_bool()
                .unwrap_or(false),
        };

        let grant = Grant {
            capabilities: capabilities_from_names(names(case["grant"].get("capabilities"))),
            limits: limits_from(case["grant"].get("limits"))
                .unwrap_or_else(ResourceLimits::unlimited),
            may_host_children: case["grant"]["mayHostChildren"].as_bool().unwrap_or(false),
            allowed_apis: None,
        };

        let policy = Policy::resolve(&manifest, &grant);

        let expected_caps: BTreeSet<String> = names(case["expect"].get("capabilities"))
            .into_iter()
            .map(str::to_string)
            .collect();
        let actual_caps: BTreeSet<String> = policy
            .capabilities
            .iter()
            .map(|c| c.as_str().to_string())
            .collect();
        assert_eq!(actual_caps, expected_caps, "capabilities in case: {name}");

        let expected_denied: BTreeSet<String> = names(case["expect"].get("denied"))
            .into_iter()
            .map(str::to_string)
            .collect();
        let actual_denied: BTreeSet<String> = policy
            .denied_requests
            .iter()
            .map(|c| c.as_str().to_string())
            .collect();
        assert_eq!(actual_denied, expected_denied, "denied set in case: {name}");

        if let Some(expected) = case["expect"]
            .get("mayHostChildren")
            .and_then(Value::as_bool)
        {
            assert_eq!(
                policy.may_host_children, expected,
                "children in case: {name}"
            );
        }

        if let Some(expected) = case["expect"].get("limits").and_then(Value::as_object) {
            // Only the axes the case names are checked, so a case can speak
            // about one axis without restating the other four.
            let checks: [(&str, Option<u64>); 5] = [
                ("maxInstructions", policy.limits.max_instructions),
                (
                    "maxInstructionsPerTurn",
                    policy.limits.max_instructions_per_turn,
                ),
                ("maxMemoryBytes", policy.limits.max_memory_bytes),
                ("maxStorageBytes", policy.limits.max_storage_bytes),
                ("maxCallDepth", policy.limits.max_call_depth),
            ];
            for (axis, actual) in checks {
                if let Some(want) = expected.get(axis) {
                    let want = want.as_u64();
                    assert_eq!(actual, want, "{axis} in case: {name}");
                }
            }
        }
    }
}

#[test]
fn an_api_allowlist_narrows_further_than_the_capability() {
    // A capability says "this family of side effects"; an allowlist says "and
    // only these names within it". An app may hold `network` and still be
    // restricted to `net.fetch`.
    let manifest = Manifest {
        requested_capabilities: capabilities_from_names(["network"]),
        ..Manifest::default()
    };
    let grant = Grant {
        capabilities: capabilities_from_names(["network"]),
        allowed_apis: Some(["net.fetch".to_string()].into_iter().collect()),
        ..Grant::default()
    };
    let policy = Policy::resolve(&manifest, &grant);

    assert!(policy.allows_api("net.fetch"));
    assert!(
        !policy.allows_api("net.open"),
        "same capability, not on the list"
    );
    assert!(
        !policy.allows_api("kv.get"),
        "and a capability not held at all"
    );
}

#[test]
fn no_allowlist_means_anything_the_capabilities_permit() {
    let manifest = Manifest {
        requested_capabilities: capabilities_from_names(["network"]),
        ..Manifest::default()
    };
    let grant = Grant {
        capabilities: capabilities_from_names(["network"]),
        ..Grant::default()
    };
    let policy = Policy::resolve(&manifest, &grant);
    assert!(policy.allows_api("net.fetch"));
    assert!(policy.allows_api("net.open"));
}
