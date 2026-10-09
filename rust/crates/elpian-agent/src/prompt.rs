//! The system prompt.
//!
//! Built once per agent and byte-stable: no timestamps, no ids, skills and
//! tools in sorted order, the catalog serialised with sorted keys. The prefix
//! is what prompt caching keys on, so anything that varied per request here
//! would make every request pay for the whole prompt again.

use serde_json::Value;

use crate::a2ui::{self, A2UI_VERSION};
use crate::skills::Skill;

/// The A2UI rules a model must follow, distilled from the protocol document.
const A2UI_RULES: &str = r#"You build user interfaces with A2UI (version v0.9.1) by calling the `a2ui_send` tool with
`{"messages": [ ... ]}`. Each message is a JSON object with "version": "v0.9.1" and EXACTLY ONE of:

- `createSurface`: {"surfaceId", "catalogId", "theme"?, "sendDataModel"?} — creates a surface. Send it once,
  before any other message for that surface. Never create a surface id twice; to start over, send
  `deleteSurface` first. Set "sendDataModel": true on surfaces with inputs, so the user's edits come back to you.
- `updateComponents`: {"surfaceId", "components": [ ... ]} — the UI as a FLAT list (an adjacency list), not a
  nested tree. Every component is {"id", "component": "<catalog component name>", ...its properties}.
  Containers reference children by id ("children": ["a", "b"], "child": "a", Tabs "tabs": [{"title","child"}],
  Modal "trigger"/"content"). Exactly one component must have "id": "root"; it is the top of the tree.
  Every referenced id must exist by the end of the message batch. Later updateComponents for the same surface
  add or replace components by id (you may omit root then, since it already exists).
- `updateDataModel`: {"surfaceId", "path"?, "value"?} — sets the value at a JSON Pointer path ("/" or omitted
  is the whole model); omitting "value" deletes it. Keep data in the data model and bind to it.
- `deleteSurface`: {"surfaceId"} — removes a surface.

Data binding: any Dynamic* property takes a literal, {"path": "/absolute/pointer"} into the surface's data
model, or a catalog function call {"call": "<name>", "args": {...}, "returnType": "..."}. Inside a template
(`"children": {"componentId": "item_template", "path": "/items"}`) paths without a leading "/" are relative
to the current item. Input components (TextField, CheckBox, ChoicePicker, Slider, DateTimeInput) are
two-way bound to their "value" path. Only call functions the catalog defines.

Actions: a Button's "action" is either {"event": {"name": "...", "context": {...}}} — sent back to you as the
next user turn, as JSON {"a2uiAction": {"name", "surfaceId", "sourceComponentId", "timestamp", "context"},
"dataModel": {...}} — or {"functionCall": {...}} run on the device (e.g. openUrl). Use literal values in
context unless a value must come from the data model.

Validation: every message is checked against the A2UI schemas and the catalog before it is shown. If the
tool result lists errors ({"code": "VALIDATION_FAILED", "surfaceId", "path", "message"}), the listed
messages were NOT shown — fix them and send them again. Messages without errors were shown already; do not
resend those.

Write prose sparingly: the user sees your text next to the UI. Prefer showing information in a surface."#;

/// What the prompt needs to know about one tool beyond its schema.
#[derive(Debug, Clone)]
pub struct ToolNote {
    pub name: String,
    pub note: String,
}

/// Assemble the system prompt.
pub fn system_prompt(
    agent_name: &str,
    instructions: &str,
    catalogs: &[String],
    skills: &[Skill],
    tool_notes: &[ToolNote],
) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "You are \"{agent_name}\", an agent inside an Elpian mini app. You act as part of the app's \
         backend: you answer the user, call the app's own functions as tools, and build the user's \
         interface with A2UI.\n\n"
    ));

    let instructions = instructions.trim();
    if !instructions.is_empty() {
        out.push_str("<instructions>\n");
        out.push_str(instructions);
        out.push_str("\n</instructions>\n\n");
    }

    out.push_str("# A2UI\n\n");
    out.push_str(A2UI_RULES);
    out.push_str("\n\n");

    for catalog in catalogs {
        if catalog != a2ui::BASIC_CATALOG_ID {
            continue;
        }
        out.push_str(&format!(
            "## Catalog\n\nUse \"catalogId\": \"{catalog}\" in createSurface. Its rules:\n\n{}\n\n",
            a2ui::BASIC_CATALOG_RULES.trim()
        ));
        let validator = a2ui::validator();
        out.push_str(&format!(
            "Components: {}.\nFunctions: {}.\n\nThe catalog (JSON Schema; components under \
             \"components\", functions under \"functions\", shared types in common_types.json):\n\n",
            validator.component_names().join(", "),
            validator.function_names().join(", ")
        ));
        out.push_str(&compact(validator.catalog()));
        out.push_str("\n\ncommon_types.json:\n\n");
        let common: Value = serde_json::from_str(a2ui::COMMON_TYPES_SCHEMA).unwrap_or(Value::Null);
        out.push_str(&compact(&common));
        out.push_str("\n\n");
    }

    out.push_str(&format!(
        "## Protocol version\n\nAlways send \"version\": \"{A2UI_VERSION}\".\n\n"
    ));

    if !skills.is_empty() {
        out.push_str(
            "# Skills\n\nSkills are instructions for specific jobs. Before doing a job a skill \
             covers, call `load_skill` with its name and follow what it says.\n\n",
        );
        let mut sorted: Vec<&Skill> = skills.iter().collect();
        sorted.sort_by(|a, b| a.name.cmp(&b.name));
        for skill in sorted {
            out.push_str(&format!("- {}: {}\n", skill.name, skill.description));
        }
        out.push('\n');
    }

    if !tool_notes.is_empty() {
        out.push_str("# Tools\n\n");
        let mut sorted: Vec<&ToolNote> = tool_notes.iter().collect();
        sorted.sort_by(|a, b| a.name.cmp(&b.name));
        for note in sorted {
            out.push_str(&format!("- {}: {}\n", note.name, note.note));
        }
        out.push('\n');
    }
    out.trim_end().to_string()
}

/// Serialise with sorted keys and no whitespace — byte-stable across runs.
pub fn compact(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let inner: Vec<String> = keys
                .into_iter()
                .map(|k| format!("{}:{}", Value::String(k.clone()), compact(&map[k])))
                .collect();
            format!("{{{}}}", inner.join(","))
        }
        Value::Array(items) => format!(
            "[{}]",
            items.iter().map(compact).collect::<Vec<_>>().join(",")
        ),
        other => other.to_string(),
    }
}
