//! Agent skills: `agents/skills/<name>/SKILL.md`, Agent-Skills style.
//!
//! A skill is YAML frontmatter (`name`, `description`) and a markdown body.
//! Progressive disclosure: the system prompt lists each skill's name and
//! description, and the model reads the body with the `load_skill` tool when it
//! needs it. A skill directory may also hold `examples/*.json` — A2UI message
//! arrays shown to the model with the body.

use std::collections::BTreeMap;

use serde_json::Value;

use crate::manifest::skill_path;

/// One loaded skill.
#[derive(Debug, Clone, PartialEq)]
pub struct Skill {
    pub name: String,
    pub description: String,
    pub body: String,
    /// `(file name, parsed JSON)`, sorted by file name.
    pub examples: Vec<(String, Value)>,
}

impl Skill {
    /// What `load_skill` returns.
    pub fn render(&self) -> String {
        let mut out = format!("# Skill: {}\n\n{}\n", self.name, self.body.trim());
        for (file, example) in &self.examples {
            out.push_str(&format!(
                "\n## Example A2UI messages ({file})\n\n```json\n{}\n```\n",
                serde_json::to_string(example).unwrap_or_default()
            ));
        }
        out
    }
}

/// Split `---\n<frontmatter>\n---\n<body>`.
pub fn split_frontmatter(text: &str) -> (BTreeMap<String, String>, String) {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut fields = BTreeMap::new();
    let Some(rest) = text
        .strip_prefix("---\n")
        .or_else(|| text.strip_prefix("---\r\n"))
    else {
        return (fields, text.to_string());
    };
    let (front, body) = match find_closing(rest) {
        Some((front, body)) => (front, body),
        None => return (fields, text.to_string()),
    };

    // A small YAML subset: `key: value`, quoted values, and folded/literal
    // block scalars (`key: >` / `key: |`) or indented continuation lines.
    let mut current: Option<String> = None;
    for line in front.lines() {
        let indented = line.starts_with(' ') || line.starts_with('\t');
        if indented {
            if let Some(key) = &current {
                let entry = fields.entry(key.clone()).or_default();
                if !entry.is_empty() {
                    entry.push(' ');
                }
                entry.push_str(line.trim());
            }
            continue;
        }
        let Some((key, value)) = line.split_once(':') else {
            current = None;
            continue;
        };
        let key = key.trim().to_string();
        let value = value.trim();
        let value = if matches!(value, ">" | "|" | ">-" | "|-") {
            String::new()
        } else {
            unquote(value)
        };
        fields.insert(key.clone(), value);
        current = Some(key);
    }
    (fields, body.to_string())
}

fn find_closing(rest: &str) -> Option<(&str, &str)> {
    let mut offset = 0;
    for line in rest.split_inclusive('\n') {
        if line.trim_end() == "---" {
            return Some((&rest[..offset], &rest[offset + line.len()..]));
        }
        offset += line.len();
    }
    None
}

fn unquote(value: &str) -> String {
    let v = value.trim();
    if v.len() >= 2
        && ((v.starts_with('"') && v.ends_with('"')) || (v.starts_with('\'') && v.ends_with('\'')))
    {
        return v[1..v.len() - 1].to_string();
    }
    v.to_string()
}

/// Load one skill from the app's bundle files.
pub fn load(name: &str, files: &BTreeMap<String, Vec<u8>>) -> Result<Skill, String> {
    let path = skill_path(name);
    let raw = files
        .get(&path)
        .ok_or_else(|| format!("{path} is not in the app bundle"))?;
    let text = String::from_utf8_lossy(raw);
    let (fields, body) = split_frontmatter(&text);
    let declared = fields.get("name").cloned().unwrap_or_default();
    if !declared.is_empty() && declared != name {
        return Err(format!(
            "{path}: frontmatter name {declared:?} does not match its directory {name:?}"
        ));
    }
    let description = fields.get("description").cloned().unwrap_or_default();
    if description.is_empty() {
        return Err(format!("{path}: frontmatter needs a description"));
    }

    let prefix = format!("agents/skills/{name}/examples/");
    let mut examples = Vec::new();
    for (file, bytes) in files.range(prefix.clone()..) {
        let Some(file_name) = file.strip_prefix(&prefix) else {
            break;
        };
        if !file_name.ends_with(".json") || file_name.contains('/') {
            continue;
        }
        let value: Value =
            serde_json::from_slice(bytes).map_err(|e| format!("{file}: not valid JSON: {e}"))?;
        examples.push((file_name.to_string(), value));
    }

    Ok(Skill {
        name: name.to_string(),
        description,
        body: body.trim().to_string(),
        examples,
    })
}
