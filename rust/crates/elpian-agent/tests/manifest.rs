//! Manifest validation and skill loading.

use std::collections::BTreeMap;

use elpian_agent::manifest::{parse, Instructions};
use elpian_agent::skills;
use serde_json::{json, Value};

fn files() -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert("agents/a.md".into(), b"hi".to_vec());
    files.insert(
        "agents/skills/browse/SKILL.md".into(),
        b"---\nname: browse\ndescription: >\n  Browse the\n  catalogue.\n---\n# Body\nText.\n"
            .to_vec(),
    );
    files
}

fn check(manifest: Value) -> Result<elpian_agent::AgentsConfig, String> {
    let files = files();
    parse(&manifest, &["listProducts".to_string()], &|p| {
        files.contains_key(p)
    })
}

fn base() -> Value {
    json!({
        "secrets": ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
        "agents": [{ "name": "assistant", "instructions": "agents/a.md", "skills": ["browse"], "tools": ["listProducts"] }]
    })
}

fn with(field: &str, value: Value) -> Value {
    let mut m = base();
    m["agents"][0][field] = value;
    m
}

#[test]
fn defaults_are_filled_in() {
    let config = check(base()).unwrap();
    let agent = &config.agents["assistant"];
    assert_eq!(agent.provider, "anthropic");
    assert_eq!(agent.effort, "medium");
    assert_eq!(agent.max_turns, 16);
    assert_eq!(agent.max_output_tokens, 64000);
    assert_eq!(agent.instructions, Instructions::File("agents/a.md".into()));
    assert_eq!(config.model_for(agent).as_deref(), Some("claude-opus-5-5"));
    assert_eq!(
        config.provider("anthropic").base_url.as_deref(),
        Some("https://api.anthropic.com")
    );
    assert!(check(json!({})).unwrap().is_empty());
}

#[test]
fn inline_instructions() {
    let config = check(with("instructions", json!("Be brief."))).unwrap();
    assert_eq!(
        config.agents["assistant"].instructions,
        Instructions::Inline("Be brief.".into())
    );
}

#[test]
fn errors_name_what_is_wrong() {
    let cases: Vec<(Value, &str)> = vec![
        (with("tools", json!(["nope"])), "unknown tool \"nope\""),
        (
            with("skills", json!(["missing"])),
            "unknown skill \"missing\"",
        ),
        (with("skills", json!(["../x"])), "must match"),
        (
            with("instructions", json!("agents/none.md")),
            "not in the app bundle",
        ),
        (
            with("instructions", json!("../etc/passwd.md")),
            "under agents/",
        ),
        (with("name", json!("1bad")), "name must match"),
        (with("provider", json!("gemini")), "unknown provider"),
        (with("effort", json!("extreme")), "effort must be one of"),
        (with("maxTurns", json!(0)), "maxTurns"),
        (with("maxOutputTokens", json!(500000)), "maxOutputTokens"),
        (
            with("catalogs", json!(["https://example.com/c"])),
            "not available",
        ),
        (with("provider", json!("openai")), "needs a \"model\""),
    ];
    for (manifest, needle) in cases {
        let err = check(manifest.clone()).unwrap_err();
        assert!(
            err.contains(needle),
            "{needle:?} not in {err:?} for {manifest}"
        );
    }

    let mut undeclared = base();
    undeclared["secrets"] = json!([]);
    assert!(check(undeclared).unwrap_err().contains("does not declare"));

    let mut twice = base();
    twice["agents"] = json!([base()["agents"][0], base()["agents"][0]]);
    assert!(check(twice).unwrap_err().contains("declared twice"));

    let mut insecure = base();
    insecure["providers"] = json!({ "anthropic": { "baseUrl": "http://evil.example" } });
    assert!(check(insecure).unwrap_err().contains("https"));

    // Scripted agents need no key.
    let mut scripted = with("provider", json!("scripted"));
    scripted["secrets"] = json!([]);
    assert!(check(scripted).is_ok());
}

#[test]
fn skills_load_with_folded_descriptions_and_examples() {
    let mut files = files();
    files.insert(
        "agents/skills/browse/examples/one.json".into(),
        b"[{\"a\":1}]".to_vec(),
    );
    let skill = skills::load("browse", &files).unwrap();
    assert_eq!(skill.description, "Browse the catalogue.");
    assert_eq!(skill.body, "# Body\nText.");
    assert_eq!(skill.examples.len(), 1);
    assert!(skill.render().contains("[{\"a\":1}]"));

    files.insert(
        "agents/skills/browse/SKILL.md".into(),
        b"---\nname: other\ndescription: x\n---\n".to_vec(),
    );
    assert!(skills::load("browse", &files)
        .unwrap_err()
        .contains("does not match"));
}
