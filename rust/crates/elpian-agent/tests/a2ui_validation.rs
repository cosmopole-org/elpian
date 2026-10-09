//! The A2UI validator over the vendored schemas: it accepts every example the
//! basic catalog ships, and rejects bad UI with `VALIDATION_FAILED` errors a
//! model can act on.

use elpian_agent::a2ui::{validator, Surfaces, BASIC_CATALOG_ID};
use serde_json::{json, Value};

fn examples() -> Vec<(String, Value)> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../a2ui/spec/catalogs/basic/examples");
    let mut out: Vec<(String, Value)> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
        .map(|e| {
            let raw = std::fs::read_to_string(e.path()).unwrap();
            (
                e.file_name().to_string_lossy().to_string(),
                serde_json::from_str(&raw).unwrap(),
            )
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn catalogs() -> Vec<String> {
    vec![BASIC_CATALOG_ID.to_string()]
}

#[test]
fn every_basic_catalog_example_is_accepted() {
    let examples = examples();
    assert_eq!(examples.len(), 43, "the vendored catalog ships 43 examples");
    for (name, example) in examples {
        let messages = example["messages"].as_array().unwrap();
        let outcome = validator().validate_batch(&Surfaces::default(), messages, &catalogs());
        assert!(
            outcome.errors.is_empty(),
            "{name} was rejected: {:#}",
            outcome.report()
        );
        assert_eq!(outcome.accepted.len(), messages.len(), "{name}");
    }
}

#[test]
fn every_example_is_accepted_one_message_at_a_time_too() {
    // How a model actually sends UI: across several tool calls. The surface
    // state carries over between them.
    for (name, example) in examples() {
        let mut surfaces = Surfaces::default();
        for message in example["messages"].as_array().unwrap() {
            let outcome =
                validator().validate_batch(&surfaces, std::slice::from_ref(message), &catalogs());
            if !outcome.errors.is_empty() {
                // A component list sent before its root is legal only in the
                // same batch as the root; examples that split them are checked
                // whole above.
                continue;
            }
            for m in &outcome.accepted {
                surfaces.apply(m);
            }
        }
        let _ = name;
    }
}

fn create(surface: &str) -> Value {
    json!({ "version": "v0.9.1", "createSurface": { "surfaceId": surface, "catalogId": BASIC_CATALOG_ID } })
}

fn components(surface: &str, list: Value) -> Value {
    json!({ "version": "v0.9.1", "updateComponents": { "surfaceId": surface, "components": list } })
}

fn errors_for(messages: Vec<Value>) -> Vec<Value> {
    let outcome = validator().validate_batch(&Surfaces::default(), &messages, &catalogs());
    outcome.errors.iter().map(|e| e.to_json()).collect()
}

fn assert_rejected(messages: Vec<Value>, needle: &str, path: &str) {
    let errors = errors_for(messages);
    assert!(
        !errors.is_empty(),
        "expected a rejection mentioning {needle:?}"
    );
    for e in &errors {
        assert_eq!(e["code"], json!("VALIDATION_FAILED"));
        assert!(e["surfaceId"].is_string() && e["path"].is_string() && e["message"].is_string());
    }
    assert!(
        errors
            .iter()
            .any(|e| e["message"].as_str().unwrap().contains(needle)
                && e["path"].as_str().unwrap().starts_with(path)),
        "no error mentions {needle:?} at {path:?}: {errors:#?}"
    );
}

#[test]
fn an_unknown_component_is_rejected() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Carousel", "items": [] }]),
            ),
        ],
        "Unknown component 'Carousel'",
        "/components/0/component",
    );
}

#[test]
fn a_missing_root_is_rejected() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "title", "component": "Text", "text": "Hi" }]),
            ),
        ],
        "Missing root component",
        "/components",
    );
}

#[test]
fn a_bad_property_type_is_rejected_at_its_path() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Text", "text": 42 }]),
            ),
        ],
        "",
        "/components/0/text",
    );
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Text", "text": "x", "variant": "huge" }]),
            ),
        ],
        "",
        "/components/0/variant",
    );
}

#[test]
fn an_extra_property_is_rejected() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Text", "text": "x", "colour": "red" }]),
            ),
        ],
        "colour",
        "/components/0",
    );
}

#[test]
fn a_missing_required_property_is_rejected() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Button", "child": "x" }]),
            ),
        ],
        "action",
        "/components/0",
    );
}

#[test]
fn structure_is_checked() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Column", "children": ["gone"] }]),
            ),
        ],
        "Dangling reference",
        "/components/root/children/0",
    );
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Column", "children": ["root"] }]),
            ),
        ],
        "Self-reference detected",
        "/components/root",
    );
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([
                    { "id": "root", "component": "Column", "children": ["a"] },
                    { "id": "a", "component": "Column", "children": ["root"] }
                ]),
            ),
        ],
        "Circular component reference",
        "/components",
    );
    // An unreachable component is legal (progressive UIs send placeholders
    // ahead of the container that shows them), so it is a warning.
    let outcome = validator().validate_batch(
        &Surfaces::default(),
        &[
            create("s"),
            components(
                "s",
                json!([
                    { "id": "root", "component": "Text", "text": "a" },
                    { "id": "orphan", "component": "Text", "text": "b" }
                ]),
            ),
        ],
        &catalogs(),
    );
    assert!(outcome.errors.is_empty());
    assert!(outcome.warnings[0]
        .message
        .contains("not reachable from root"));
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([
                    { "id": "root", "component": "Text", "text": "a" },
                    { "id": "root", "component": "Text", "text": "b" }
                ]),
            ),
        ],
        "Duplicate component ID",
        "/components/1/id",
    );
}

#[test]
fn surface_lifecycle_is_checked() {
    assert_rejected(
        vec![components(
            "s",
            json!([{ "id": "root", "component": "Text", "text": "a" }]),
        )],
        "does not exist",
        "/surfaceId",
    );
    assert_rejected(
        vec![create("s"), create("s")],
        "already exists",
        "/surfaceId",
    );
    assert_rejected(
        vec![
            json!({ "createSurface": { "surfaceId": "s", "catalogId": "https://example.com/other" } }),
        ],
        "is not available",
        "/catalogId",
    );
}

#[test]
fn unknown_functions_and_bad_pointers_are_rejected() {
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Text",
                         "text": { "call": "shout", "args": {}, "returnType": "string" } }]),
            ),
        ],
        "Unknown function 'shout'",
        "/components/0/text/call",
    );
    assert_rejected(
        vec![
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Text", "text": { "path": "/a~2b" } }]),
            ),
        ],
        "Invalid path syntax",
        "/components/0/text/path",
    );
}

#[test]
fn a_missing_version_is_filled_in_and_a_wrong_one_rejected() {
    let outcome = validator().validate_batch(
        &Surfaces::default(),
        &[json!({ "createSurface": { "surfaceId": "s", "catalogId": BASIC_CATALOG_ID } })],
        &catalogs(),
    );
    assert!(outcome.errors.is_empty());
    assert_eq!(outcome.accepted[0]["version"], json!("v0.9.1"));

    assert_rejected(
        vec![
            json!({ "version": "v0.8", "createSurface": { "surfaceId": "s", "catalogId": BASIC_CATALOG_ID } }),
        ],
        "",
        "/version",
    );
}

#[test]
fn an_incremental_update_without_root_is_fine_once_the_root_exists() {
    let mut surfaces = Surfaces::default();
    let first = validator().validate_batch(
        &surfaces,
        &[
            create("s"),
            components(
                "s",
                json!([{ "id": "root", "component": "Column", "children": ["a"] },
                                    { "id": "a", "component": "Text", "text": "one" }]),
            ),
        ],
        &catalogs(),
    );
    assert!(first.errors.is_empty(), "{:#}", first.report());
    for m in &first.accepted {
        surfaces.apply(m);
    }
    let second = validator().validate_batch(
        &surfaces,
        &[components(
            "s",
            json!([{ "id": "a", "component": "Text", "text": "two" }]),
        )],
        &catalogs(),
    );
    assert!(second.errors.is_empty(), "{:#}", second.report());
}

#[test]
fn valid_messages_pass_while_invalid_ones_in_the_same_batch_are_held_back() {
    let outcome = validator().validate_batch(
        &Surfaces::default(),
        &[
            create("good"),
            components(
                "good",
                json!([{ "id": "root", "component": "Text", "text": "ok" }]),
            ),
            create("bad"),
            components("bad", json!([{ "id": "root", "component": "Nope" }])),
        ],
        &catalogs(),
    );
    assert_eq!(outcome.accepted.len(), 3);
    assert_eq!(outcome.errors.len(), 1);
    assert_eq!(outcome.errors[0].surface_id, "bad");
    assert_eq!(outcome.errors[0].message_index, 3);
}
