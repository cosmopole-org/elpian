//! A2UI v0.9.1: the vendored schemas, a validator built on them, and the
//! per-conversation surface state the structural rules are checked against.
//!
//! # Two layers, both required
//!
//! **Schema.** Every message is validated against the vendored
//! `server_to_client.json` with `catalog.json` mapped to the basic catalog, by a
//! real JSON Schema 2020-12 validator (`jsonschema`). That is the backstop: a
//! message the official schemas reject is never sent. On its own it produces
//! poor feedback for a model — a bad component fails a 18-way `oneOf` at the
//! list item — so before it the validator checks the envelope with a permissive
//! component schema, then each component against *its own* catalog schema
//! (picked by the `component` discriminator). The model is told which property
//! of which component is wrong.
//!
//! **Structure.** What a schema cannot say: unique ids within a message, one
//! `root`, `createSurface` before use and never twice, every referenced child
//! existing by the end of the batch, no self-references or cycles, components
//! reachable from the root, known catalogs and functions, JSON Pointer syntax,
//! and the protocol's nesting limits. These run against the conversation's
//! accumulated surfaces, so an incremental update that omits `root` is fine
//! once the root was sent.
//!
//! Errors use the protocol's standard shape:
//! `{code: "VALIDATION_FAILED", surfaceId, path, message}`.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;

use serde_json::{json, Map, Value};

/// The protocol version this host speaks, filled into messages that omit it.
pub const A2UI_VERSION: &str = "v0.9.1";

/// The basic catalog's id, exactly as the vendored catalog declares it.
pub const BASIC_CATALOG_ID: &str =
    "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json";

/// The vendored schemas, embedded so a host binary carries them.
pub const SERVER_TO_CLIENT_SCHEMA: &str =
    include_str!("../../../../a2ui/spec/json/server_to_client.json");
pub const COMMON_TYPES_SCHEMA: &str = include_str!("../../../../a2ui/spec/json/common_types.json");
pub const BASIC_CATALOG: &str = include_str!("../../../../a2ui/spec/catalogs/basic/catalog.json");
pub const BASIC_CATALOG_RULES: &str =
    include_str!("../../../../a2ui/spec/catalogs/basic/rules.txt");

/// Where `server_to_client.json` resolves its `catalog.json` placeholder.
const CATALOG_ALIAS: &str = "https://a2ui.org/specification/v0_9/catalog.json";
const COMMON_TYPES_ID: &str = "https://a2ui.org/specification/v0_9/common_types.json";
const ENVELOPE_ID: &str = "https://a2ui.org/specification/v0_9/server_to_client.json";

/// The protocol's global nesting limit (component chains, data model values).
const MAX_DEPTH: usize = 50;
/// The protocol's limit on nested function calls.
const MAX_FUNCTION_DEPTH: usize = 5;

/// The four server-to-client message kinds.
pub const MESSAGE_KINDS: [&str; 4] = [
    "createSurface",
    "updateComponents",
    "updateDataModel",
    "deleteSurface",
];

/// One A2UI validation error, in the protocol's standard shape.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct A2uiError {
    pub surface_id: String,
    /// JSON Pointer into the message's payload (e.g. `/components/0/text`).
    pub path: String,
    pub message: String,
    /// Which message of the batch it concerns.
    pub message_index: usize,
}

impl A2uiError {
    pub fn to_json(&self) -> Value {
        json!({
            "code": "VALIDATION_FAILED",
            "surfaceId": self.surface_id,
            "path": self.path,
            "message": self.message,
            "messageIndex": self.message_index,
        })
    }
}

/// One surface as the server last left it.
#[derive(Debug, Clone, PartialEq)]
pub struct Surface {
    pub catalog_id: String,
    pub send_data_model: bool,
    /// Components by id — the adjacency list, accumulated across messages.
    pub components: BTreeMap<String, Value>,
    /// The surface's data model: what the agent sent, overwritten by what the
    /// client reported (the client's copy is the current one after an edit).
    pub data_model: Value,
}

/// Every surface of one conversation, in creation order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Surfaces {
    map: BTreeMap<String, Surface>,
    order: Vec<String>,
}

impl Surfaces {
    pub fn get(&self, id: &str) -> Option<&Surface> {
        self.map.get(id)
    }
    pub fn contains(&self, id: &str) -> bool {
        self.map.contains_key(id)
    }
    /// Surface ids in creation order.
    pub fn ids(&self) -> &[String] {
        &self.order
    }
    pub fn len(&self) -> usize {
        self.order.len()
    }
    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }

    /// Record the data model a client reported for a surface it holds.
    pub fn set_client_data_model(&mut self, id: &str, model: Value) -> bool {
        match self.map.get_mut(id) {
            Some(surface) => {
                surface.data_model = model;
                true
            }
            None => false,
        }
    }

    /// Apply one message that has already been validated.
    pub fn apply(&mut self, message: &Value) {
        if let Some(body) = message.get("createSurface") {
            let id = str_field(body, "surfaceId").to_string();
            if !self.map.contains_key(&id) {
                self.order.push(id.clone());
            }
            self.map.insert(
                id,
                Surface {
                    catalog_id: str_field(body, "catalogId").to_string(),
                    send_data_model: body.get("sendDataModel") == Some(&Value::Bool(true)),
                    components: BTreeMap::new(),
                    data_model: json!({}),
                },
            );
        } else if let Some(body) = message.get("updateComponents") {
            if let Some(surface) = self.map.get_mut(str_field(body, "surfaceId")) {
                for component in body["components"].as_array().into_iter().flatten() {
                    if let Some(id) = component.get("id").and_then(Value::as_str) {
                        surface.components.insert(id.to_string(), component.clone());
                    }
                }
            }
        } else if let Some(body) = message.get("updateDataModel") {
            if let Some(surface) = self.map.get_mut(str_field(body, "surfaceId")) {
                let path = body.get("path").and_then(Value::as_str).unwrap_or("/");
                pointer_set(&mut surface.data_model, path, body.get("value").cloned());
            }
        } else if let Some(body) = message.get("deleteSurface") {
            let id = str_field(body, "surfaceId");
            self.map.remove(id);
            self.order.retain(|s| s != id);
        }
    }
}

/// The outcome of validating one batch.
#[derive(Debug, Clone, Default)]
pub struct BatchOutcome {
    /// Messages that passed, normalised (version filled in), in batch order.
    pub accepted: Vec<Value>,
    pub errors: Vec<A2uiError>,
    /// Problems that did not stop a message (components nothing shows).
    pub warnings: Vec<A2uiError>,
}

impl BatchOutcome {
    /// The tool result a model is shown.
    pub fn report(&self) -> Value {
        json!({
            "applied": self.accepted.len(),
            "rejected": self.errors.iter().map(|e| e.message_index).collect::<BTreeSet<_>>().len(),
            "errors": self.errors.iter().map(A2uiError::to_json).collect::<Vec<_>>(),
            "warnings": self.warnings.iter().map(A2uiError::to_json).collect::<Vec<_>>(),
        })
    }
}

/// Where a component holds references to other components, derived from the
/// catalog by looking for `ComponentId` / `ChildList` schema references — the
/// rule the protocol sets for validators ("Validator compliance when defining
/// catalogs").
#[derive(Debug, Clone)]
enum RefSite {
    /// `prop` holds one component id.
    Single(String),
    /// `prop` holds a `ChildList`.
    ChildList(String),
    /// `prop` is an array of objects, each with these sites.
    Each(String, Vec<RefSite>),
}

/// The compiled validator for one catalog (the basic catalog).
pub struct A2uiValidator {
    envelope: jsonschema::Validator,
    shallow_envelope: BTreeMap<&'static str, jsonschema::Validator>,
    components: BTreeMap<String, jsonschema::Validator>,
    ref_sites: BTreeMap<String, Vec<RefSite>>,
    functions: BTreeSet<String>,
    catalog: Value,
}

impl std::fmt::Debug for A2uiValidator {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("A2uiValidator")
            .field("components", &self.components.keys().collect::<Vec<_>>())
            .finish()
    }
}

/// The basic-catalog validator, compiled once per process.
pub fn validator() -> &'static A2uiValidator {
    static VALIDATOR: OnceLock<A2uiValidator> = OnceLock::new();
    VALIDATOR.get_or_init(|| A2uiValidator::basic().expect("the vendored A2UI schemas compile"))
}

/// The catalogs this host can validate against.
pub fn known_catalog(id: &str) -> bool {
    id == BASIC_CATALOG_ID
}

impl A2uiValidator {
    /// Compile the vendored schemas with the basic catalog.
    pub fn basic() -> Result<A2uiValidator, String> {
        let envelope_schema: Value =
            serde_json::from_str(SERVER_TO_CLIENT_SCHEMA).map_err(|e| e.to_string())?;
        let common: Value = serde_json::from_str(COMMON_TYPES_SCHEMA).map_err(|e| e.to_string())?;
        let catalog: Value = serde_json::from_str(BASIC_CATALOG).map_err(|e| e.to_string())?;

        // `server_to_client.json` names its catalog `catalog.json`, which
        // resolves next to it; the protocol says to map that name onto the
        // catalog in use. The copy registered there carries the alias as its
        // own `$id` so its internal references resolve inside it.
        let mut aliased = catalog.clone();
        aliased["$id"] = json!(CATALOG_ALIAS);

        let full = build_with(&envelope_schema, &common, &aliased)?;

        // The same envelope with a component schema that checks only the shape
        // every component shares, so envelope errors are reported precisely
        // and component errors are left to the per-component validators.
        let mut permissive = aliased.clone();
        permissive["$defs"]["anyComponent"] = json!({
            "type": "object",
            "properties": {
                "id": { "type": "string" },
                "component": { "type": "string" }
            },
            "required": ["id", "component"]
        });
        // One validator per message kind, so an error is reported against the
        // kind the message is rather than as a failed four-way `oneOf`.
        let shallow_registry = jsonschema::Registry::new()
            .add(ENVELOPE_ID, &envelope_schema)
            .map_err(|e| e.to_string())?
            .add(COMMON_TYPES_ID, &common)
            .map_err(|e| e.to_string())?
            .add(CATALOG_ALIAS, &permissive)
            .map_err(|e| e.to_string())?
            .prepare()
            .map_err(|e| e.to_string())?;
        let mut shallow = BTreeMap::new();
        for (kind, def) in [
            ("createSurface", "CreateSurfaceMessage"),
            ("updateComponents", "UpdateComponentsMessage"),
            ("updateDataModel", "UpdateDataModelMessage"),
            ("deleteSurface", "DeleteSurfaceMessage"),
        ] {
            let wrapper = json!({ "$ref": format!("{ENVELOPE_ID}#/$defs/{def}") });
            let compiled = jsonschema::options()
                .with_draft(jsonschema::Draft::Draft202012)
                .with_registry(&shallow_registry)
                .build(&wrapper)
                .map_err(|e| format!("{def}: {e}"))?;
            shallow.insert(kind, compiled);
        }

        let mut components = BTreeMap::new();
        let mut ref_sites = BTreeMap::new();
        let registry = registry_with(&common, &aliased)?;
        for (name, schema) in catalog["components"].as_object().into_iter().flatten() {
            let wrapper = json!({ "$ref": format!("{CATALOG_ALIAS}#/components/{name}") });
            let compiled = jsonschema::options()
                .with_draft(jsonschema::Draft::Draft202012)
                .with_registry(&registry)
                .build(&wrapper)
                .map_err(|e| format!("component {name}: {e}"))?;
            components.insert(name.clone(), compiled);
            ref_sites.insert(name.clone(), sites_in(schema));
        }
        let functions = catalog["functions"]
            .as_object()
            .map(|f| f.keys().cloned().collect())
            .unwrap_or_default();

        Ok(A2uiValidator {
            envelope: full,
            shallow_envelope: shallow,
            components,
            ref_sites,
            functions,
            catalog,
        })
    }

    /// The catalog document this validator was built from.
    pub fn catalog(&self) -> &Value {
        &self.catalog
    }

    pub fn component_names(&self) -> Vec<&str> {
        self.components.keys().map(String::as_str).collect()
    }

    pub fn function_names(&self) -> Vec<&str> {
        self.functions.iter().map(String::as_str).collect()
    }

    /// Validate one batch against the conversation's surfaces.
    ///
    /// `allowed_catalogs` is what a `createSurface` may name: the agent's
    /// catalogs, narrowed by the client's `supportedCatalogIds` when it sent
    /// them. Messages that pass are returned normalised; `surfaces` is not
    /// modified — apply `accepted` to it once they have been delivered.
    pub fn validate_batch(
        &self,
        surfaces: &Surfaces,
        messages: &[Value],
        allowed_catalogs: &[String],
    ) -> BatchOutcome {
        let mut outcome = BatchOutcome::default();
        let mut working = surfaces.clone();
        // (index, normalised message, surface id) of messages that passed the
        // per-message checks.
        let mut passed: Vec<(usize, Value, String)> = Vec::new();
        // Surfaces whose components changed in this batch, with the ids each
        // message introduced (for the reachability check).
        let mut touched: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();

        for (index, raw) in messages.iter().enumerate() {
            let mut errors = Vec::new();
            let message = self.check_message(raw, index, &working, allowed_catalogs, &mut errors);
            if !errors.is_empty() {
                outcome.errors.extend(errors);
                continue;
            }
            let Some(message) = message else { continue };
            let (_, body) = kind_of(&message).expect("checked");
            let surface_id = str_field(body, "surfaceId").to_string();
            if let Some(update) = message.get("updateComponents") {
                let ids = touched.entry(surface_id.clone()).or_default();
                for c in update["components"].as_array().into_iter().flatten() {
                    if let Some(id) = c.get("id").and_then(Value::as_str) {
                        ids.insert(id.to_string());
                    }
                }
            }
            if message.get("deleteSurface").is_some() {
                touched.remove(&surface_id);
            }
            working.apply(&message);
            passed.push((index, message, surface_id));
        }

        // End-of-batch structure, per surface whose tree changed.
        let mut failed_surfaces = BTreeSet::new();
        for (surface_id, introduced) in &touched {
            let Some(surface) = working.get(surface_id) else {
                continue;
            };
            let first_index = passed
                .iter()
                .find(|(_, m, s)| s == surface_id && m.get("updateComponents").is_some())
                .map(|(i, _, _)| *i)
                .unwrap_or(0);
            let (errors, warnings) = self.check_tree(surface_id, surface, introduced, first_index);
            outcome.warnings.extend(warnings);
            if !errors.is_empty() {
                failed_surfaces.insert(surface_id.clone());
                outcome.errors.extend(errors);
            }
        }

        for (index, message, surface_id) in passed {
            if failed_surfaces.contains(&surface_id) && message.get("updateComponents").is_some() {
                outcome.errors.push(A2uiError {
                    surface_id,
                    path: String::new(),
                    message: "not applied: this surface's component tree is invalid after the \
                              batch (see the other errors); resend corrected updateComponents"
                        .into(),
                    message_index: index,
                });
                continue;
            }
            outcome.accepted.push(message);
        }
        outcome
    }

    /// Per-message checks: schema, then the state-dependent rules. Returns the
    /// normalised message.
    fn check_message(
        &self,
        raw: &Value,
        index: usize,
        surfaces: &Surfaces,
        allowed_catalogs: &[String],
        errors: &mut Vec<A2uiError>,
    ) -> Option<Value> {
        let err = |surface: &str, path: &str, message: String| A2uiError {
            surface_id: surface.to_string(),
            path: path.to_string(),
            message,
            message_index: index,
        };

        let Some(object) = raw.as_object() else {
            errors.push(err("", "", "a message must be a JSON object".into()));
            return None;
        };
        let mut message = object.clone();
        if !message.contains_key("version") {
            message.insert("version".into(), json!(A2UI_VERSION));
        }
        let message = Value::Object(message);

        let kinds: Vec<&str> = MESSAGE_KINDS
            .iter()
            .copied()
            .filter(|k| message.get(*k).is_some())
            .collect();
        if kinds.len() != 1 {
            errors.push(err(
                "",
                "",
                format!(
                    "a message must contain exactly one of createSurface, updateComponents, \
                     updateDataModel or deleteSurface (found {})",
                    if kinds.is_empty() {
                        "none".to_string()
                    } else {
                        kinds.join(", ")
                    }
                ),
            ));
            return None;
        }
        let kind = kinds[0];
        let body = &message[kind];
        let surface_id = body
            .get("surfaceId")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();

        // 1. The envelope, with components checked only for their common shape.
        let before = errors.len();
        for e in self.shallow_envelope[kind].iter_errors(&message) {
            errors.push(err(
                &surface_id,
                &relative_path(e.instance_path().as_str(), kind),
                schema_message(&e),
            ));
        }
        if errors.len() > before {
            return None;
        }

        // 2. Each component against its own schema.
        if kind == "updateComponents" {
            for (i, component) in body["components"]
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let name = component["component"].as_str().unwrap_or("");
                let Some(compiled) = self.components.get(name) else {
                    errors.push(err(
                        &surface_id,
                        &format!("/components/{i}/component"),
                        format!(
                            "Unknown component '{name}'. The catalog has: {}",
                            self.component_names().join(", ")
                        ),
                    ));
                    continue;
                };
                let before = errors.len();
                self.check_functions(
                    component,
                    &format!("/components/{i}"),
                    0,
                    &surface_id,
                    index,
                    errors,
                );
                if errors.len() > before {
                    // An unknown function also fails the schema, less legibly.
                    continue;
                }
                for e in compiled.iter_errors(component) {
                    errors.push(err(
                        &surface_id,
                        &format!("/components/{i}{}", e.instance_path().as_str()),
                        format!("{name}: {}", schema_message(&e)),
                    ));
                }
                if errors.len() == before {
                    check_pointers(
                        component,
                        &format!("/components/{i}"),
                        &surface_id,
                        index,
                        errors,
                    );
                }
            }
            if errors.len() > before {
                return None;
            }
        }

        // 3. The official schema as a whole — the backstop.
        for e in self.envelope.iter_errors(&message) {
            errors.push(err(
                &surface_id,
                &relative_path(e.instance_path().as_str(), kind),
                schema_message(&e),
            ));
        }
        if errors.len() > before {
            return None;
        }

        // 4. State and structure.
        match kind {
            "createSurface" => {
                if surfaces.contains(&surface_id) {
                    errors.push(err(
                        &surface_id,
                        "/surfaceId",
                        format!(
                            "surface '{surface_id}' already exists; send deleteSurface first or \
                             update it with updateComponents/updateDataModel"
                        ),
                    ));
                }
                let catalog = str_field(body, "catalogId");
                if !allowed_catalogs.iter().any(|c| c == catalog) {
                    errors.push(err(
                        &surface_id,
                        "/catalogId",
                        format!(
                            "catalog '{catalog}' is not available here; use one of: {}",
                            allowed_catalogs.join(", ")
                        ),
                    ));
                }
            }
            _ => {
                if !surfaces.contains(&surface_id) {
                    errors.push(err(
                        &surface_id,
                        "/surfaceId",
                        format!("surface '{surface_id}' does not exist; send createSurface first"),
                    ));
                }
            }
        }
        if kind == "updateComponents" {
            let mut seen = BTreeSet::new();
            for (i, component) in body["components"]
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let id = component["id"].as_str().unwrap_or("");
                if !seen.insert(id) {
                    errors.push(err(
                        &surface_id,
                        &format!("/components/{i}/id"),
                        format!("Duplicate component ID '{id}' in one updateComponents message"),
                    ));
                }
            }
        }
        if kind == "updateDataModel" {
            if let Some(path) = body.get("path").and_then(Value::as_str) {
                if !valid_pointer(path, false) {
                    errors.push(err(
                        &surface_id,
                        "/path",
                        format!("Invalid path syntax '{path}': not a JSON Pointer"),
                    ));
                }
            }
            if let Some(value) = body.get("value") {
                if depth_of(value) > MAX_DEPTH {
                    errors.push(err(
                        &surface_id,
                        "/value",
                        format!("Global recursion limit exceeded: the value nests deeper than {MAX_DEPTH}"),
                    ));
                }
            }
        }
        if errors.len() > before {
            return None;
        }
        Some(message)
    }

    /// Every `{call: …}` inside a component names a catalog function, and
    /// calls nest no deeper than the protocol allows.
    fn check_functions(
        &self,
        value: &Value,
        path: &str,
        depth: usize,
        surface_id: &str,
        index: usize,
        errors: &mut Vec<A2uiError>,
    ) {
        match value {
            Value::Object(map) => {
                let mut depth = depth;
                if let Some(Value::String(name)) = map.get("call") {
                    depth += 1;
                    if depth > MAX_FUNCTION_DEPTH {
                        errors.push(A2uiError {
                            surface_id: surface_id.to_string(),
                            path: path.to_string(),
                            message: format!(
                                "functionCall depth exceeds the limit of {MAX_FUNCTION_DEPTH}"
                            ),
                            message_index: index,
                        });
                        return;
                    }
                    if !self.functions.contains(name) {
                        errors.push(A2uiError {
                            surface_id: surface_id.to_string(),
                            path: format!("{path}/call"),
                            message: format!(
                                "Unknown function '{name}'. The catalog has: {}",
                                self.function_names().join(", ")
                            ),
                            message_index: index,
                        });
                    }
                }
                for (key, child) in map {
                    self.check_functions(
                        child,
                        &format!("{path}/{}", escape_token(key)),
                        depth,
                        surface_id,
                        index,
                        errors,
                    );
                }
            }
            Value::Array(items) => {
                for (i, child) in items.iter().enumerate() {
                    self.check_functions(
                        child,
                        &format!("{path}/{i}"),
                        depth,
                        surface_id,
                        index,
                        errors,
                    );
                }
            }
            _ => {}
        }
    }

    /// The component tree of one surface after the batch: root present, every
    /// reference resolves, no cycles, nothing this batch added is unreachable,
    /// and no chain deeper than the protocol's limit.
    fn check_tree(
        &self,
        surface_id: &str,
        surface: &Surface,
        introduced: &BTreeSet<String>,
        index: usize,
    ) -> (Vec<A2uiError>, Vec<A2uiError>) {
        let mut errors = Vec::new();
        let err = |path: String, message: String| A2uiError {
            surface_id: surface_id.to_string(),
            path,
            message,
            message_index: index,
        };

        if !surface.components.contains_key("root") {
            errors.push(err(
                "/components".into(),
                format!(
                    "Missing root component: surface '{surface_id}' has no component with id \
                     'root' (exactly one component must be the root of the tree)"
                ),
            ));
            return (errors, Vec::new());
        }

        // Edges: component → referenced ids.
        let mut edges: BTreeMap<&str, Vec<String>> = BTreeMap::new();
        for (id, component) in &surface.components {
            let name = component["component"].as_str().unwrap_or("");
            let mut refs = Vec::new();
            if let Some(sites) = self.ref_sites.get(name) {
                collect_refs(component, sites, "", &mut refs);
            }
            for (path, target) in &refs {
                if target == id {
                    errors.push(err(
                        format!("/components/{id}{path}"),
                        format!("Self-reference detected: component '{id}' references itself"),
                    ));
                } else if !surface.components.contains_key(target) {
                    errors.push(err(
                        format!("/components/{id}{path}"),
                        format!(
                            "Dangling reference: component '{id}' references non-existent \
                             component '{target}'"
                        ),
                    ));
                }
            }
            edges.insert(id.as_str(), refs.into_iter().map(|(_, t)| t).collect());
        }
        if !errors.is_empty() {
            return (errors, Vec::new());
        }

        // Cycles and depth: a DFS from every node (the graph is small).
        let mut reachable: BTreeMap<&str, usize> = BTreeMap::new();
        let mut stack: Vec<(&str, usize)> = vec![("root", 1)];
        if let Some(cycle) = find_cycle(&edges) {
            errors.push(err(
                "/components".into(),
                format!("Circular component reference: {}", cycle.join(" -> ")),
            ));
            return (errors, Vec::new());
        }
        while let Some((id, depth)) = stack.pop() {
            if depth > MAX_DEPTH {
                errors.push(err(
                    format!("/components/{id}"),
                    format!(
                        "Global recursion limit exceeded: the tree nests deeper than {MAX_DEPTH}"
                    ),
                ));
                return (errors, Vec::new());
            }
            // A node already reached at least this deep has nothing new to
            // say; without this a shared subtree is walked once per parent.
            if reachable.get(id).is_some_and(|d| *d >= depth) {
                continue;
            }
            reachable.insert(id, depth);
            for child in edges.get(id).into_iter().flatten() {
                stack.push((child.as_str(), depth + 1));
            }
        }

        // Unreachable components are legal — progressive UIs send a
        // placeholder before the container that will show it — so they are a
        // warning for the model, not a rejection.
        let mut warnings = Vec::new();
        for id in introduced {
            if !reachable.contains_key(id.as_str()) {
                warnings.push(err(
                    format!("/components/{id}"),
                    format!(
                        "Component '{id}' is not reachable from root: reference it from a \
                         container (children, child, tabs, trigger/content, or a template) or \
                         leave it out (warning: it is not shown)"
                    ),
                ));
            }
        }
        (errors, warnings)
    }
}

fn build_with(
    envelope: &Value,
    common: &Value,
    catalog: &Value,
) -> Result<jsonschema::Validator, String> {
    let registry = registry_with(common, catalog)?;
    jsonschema::options()
        .with_draft(jsonschema::Draft::Draft202012)
        .with_registry(&registry)
        .build(envelope)
        .map_err(|e| format!("server_to_client.json: {e}"))
}

fn registry_with<'a>(
    common: &'a Value,
    catalog: &'a Value,
) -> Result<jsonschema::Registry<'a>, String> {
    jsonschema::Registry::new()
        .add(COMMON_TYPES_ID, common)
        .map_err(|e| e.to_string())?
        .add(CATALOG_ALIAS, catalog)
        .map_err(|e| e.to_string())?
        .prepare()
        .map_err(|e| e.to_string())
}

/// Find the reference sites in one component's catalog schema.
fn sites_in(schema: &Value) -> Vec<RefSite> {
    let mut sites = Vec::new();
    let visit_props = |props: &Map<String, Value>, sites: &mut Vec<RefSite>| {
        for (name, prop) in props {
            if let Some(site) = site_for(name, prop) {
                sites.push(site);
            }
        }
    };
    if let Some(props) = schema.get("properties").and_then(Value::as_object) {
        visit_props(props, &mut sites);
    }
    for part in schema
        .get("allOf")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let Some(props) = part.get("properties").and_then(Value::as_object) {
            visit_props(props, &mut sites);
        }
    }
    sites
}

fn site_for(name: &str, prop: &Value) -> Option<RefSite> {
    if let Some(reference) = prop.get("$ref").and_then(Value::as_str) {
        if reference.ends_with("#/$defs/ComponentId") {
            return Some(RefSite::Single(name.to_string()));
        }
        if reference.ends_with("#/$defs/ChildList") {
            return Some(RefSite::ChildList(name.to_string()));
        }
        return None;
    }
    let items = prop.get("items")?;
    let inner: Vec<RefSite> = items
        .get("properties")
        .and_then(Value::as_object)
        .map(|props| props.iter().filter_map(|(n, p)| site_for(n, p)).collect())
        .unwrap_or_default();
    (!inner.is_empty()).then(|| RefSite::Each(name.to_string(), inner))
}

/// `(path, referenced id)` for every reference in `value`.
fn collect_refs(value: &Value, sites: &[RefSite], prefix: &str, out: &mut Vec<(String, String)>) {
    for site in sites {
        match site {
            RefSite::Single(prop) => {
                if let Some(id) = value.get(prop).and_then(Value::as_str) {
                    out.push((format!("{prefix}/{prop}"), id.to_string()));
                }
            }
            RefSite::ChildList(prop) => match value.get(prop) {
                Some(Value::Array(ids)) => {
                    for (i, id) in ids.iter().enumerate() {
                        if let Some(id) = id.as_str() {
                            out.push((format!("{prefix}/{prop}/{i}"), id.to_string()));
                        }
                    }
                }
                Some(Value::Object(template)) => {
                    if let Some(id) = template.get("componentId").and_then(Value::as_str) {
                        out.push((format!("{prefix}/{prop}/componentId"), id.to_string()));
                    }
                }
                _ => {}
            },
            RefSite::Each(prop, inner) => {
                for (i, item) in value
                    .get(prop)
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .enumerate()
                {
                    collect_refs(item, inner, &format!("{prefix}/{prop}/{i}"), out);
                }
            }
        }
    }
}

fn find_cycle(edges: &BTreeMap<&str, Vec<String>>) -> Option<Vec<String>> {
    // Iterative three-colour DFS.
    let mut colour: BTreeMap<&str, u8> = BTreeMap::new();
    for &start in edges.keys() {
        if colour.get(start).copied().unwrap_or(0) != 0 {
            continue;
        }
        let mut stack: Vec<(&str, usize)> = vec![(start, 0)];
        let mut path: Vec<&str> = vec![start];
        colour.insert(start, 1);
        while let Some((node, next)) = stack.pop() {
            let children = edges.get(node).map(Vec::as_slice).unwrap_or(&[]);
            if next < children.len() {
                stack.push((node, next + 1));
                let child = children[next].as_str();
                match colour.get(child).copied().unwrap_or(0) {
                    0 => {
                        colour.insert(child, 1);
                        path.push(child);
                        stack.push((child, 0));
                    }
                    1 => {
                        let from = path.iter().position(|n| *n == child).unwrap_or(0);
                        let mut cycle: Vec<String> =
                            path[from..].iter().map(|s| s.to_string()).collect();
                        cycle.push(child.to_string());
                        return Some(cycle);
                    }
                    _ => {}
                }
            } else {
                colour.insert(node, 2);
                path.pop();
            }
        }
    }
    None
}

/// Data-binding paths and template paths are JSON Pointers (absolute) or
/// relative pointers (inside a template's scope).
fn check_pointers(
    value: &Value,
    path: &str,
    surface_id: &str,
    index: usize,
    errors: &mut Vec<A2uiError>,
) {
    match value {
        Value::Object(map) => {
            if let Some(Value::String(pointer)) = map.get("path") {
                if !valid_pointer(pointer, true) {
                    errors.push(A2uiError {
                        surface_id: surface_id.to_string(),
                        path: format!("{path}/path"),
                        message: format!("Invalid path syntax '{pointer}': not a JSON Pointer"),
                        message_index: index,
                    });
                }
            }
            for (key, child) in map {
                check_pointers(
                    child,
                    &format!("{path}/{}", escape_token(key)),
                    surface_id,
                    index,
                    errors,
                );
            }
        }
        Value::Array(items) => {
            for (i, child) in items.iter().enumerate() {
                check_pointers(child, &format!("{path}/{i}"), surface_id, index, errors);
            }
        }
        _ => {}
    }
}

/// RFC 6901 syntax: `~` only as `~0` or `~1`. Relative pointers (no leading
/// `/`) are allowed where the protocol allows them.
pub fn valid_pointer(pointer: &str, allow_relative: bool) -> bool {
    if !allow_relative && !pointer.is_empty() && !pointer.starts_with('/') {
        return false;
    }
    let bytes = pointer.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'~' {
            if !matches!(bytes.get(i + 1), Some(b'0') | Some(b'1')) {
                return false;
            }
            i += 1;
        }
        i += 1;
    }
    true
}

fn escape_token(key: &str) -> String {
    key.replace('~', "~0").replace('/', "~1")
}

fn unescape_token(token: &str) -> String {
    token.replace("~1", "/").replace("~0", "~")
}

fn depth_of(value: &Value) -> usize {
    match value {
        Value::Object(map) => 1 + map.values().map(depth_of).max().unwrap_or(0),
        Value::Array(items) => 1 + items.iter().map(depth_of).max().unwrap_or(0),
        _ => 0,
    }
}

/// Upsert (`Some`) or remove (`None`) the value at an absolute JSON Pointer,
/// creating intermediate objects as needed. `/` and `""` are the whole model.
pub fn pointer_set(root: &mut Value, pointer: &str, value: Option<Value>) {
    let tokens: Vec<String> = pointer
        .split('/')
        .skip(1)
        .filter(|t| !t.is_empty())
        .map(unescape_token)
        .collect();
    if tokens.is_empty() {
        *root = value.unwrap_or_else(|| json!({}));
        return;
    }
    let mut node = root;
    for token in &tokens[..tokens.len() - 1] {
        if !node.is_object() && !node.is_array() {
            *node = json!({});
        }
        node = match node {
            Value::Array(items) => match token.parse::<usize>() {
                Ok(i) if i < items.len() => &mut items[i],
                _ => return,
            },
            Value::Object(map) => map.entry(token.clone()).or_insert_with(|| json!({})),
            _ => return,
        };
    }
    let last = &tokens[tokens.len() - 1];
    match (node, value) {
        (Value::Array(items), Some(v)) => match last.parse::<usize>() {
            Ok(i) if i < items.len() => items[i] = v,
            Ok(i) if i == items.len() => items.push(v),
            _ if last == "-" => items.push(v),
            _ => {}
        },
        (Value::Array(items), None) => {
            if let Ok(i) = last.parse::<usize>() {
                if i < items.len() {
                    items.remove(i);
                }
            }
        }
        (Value::Object(map), Some(v)) => {
            map.insert(last.clone(), v);
        }
        (Value::Object(map), None) => {
            map.remove(last);
        }
        (other, Some(v)) => {
            let mut map = Map::new();
            map.insert(last.clone(), v);
            *other = Value::Object(map);
        }
        (_, None) => {}
    }
}

fn kind_of(message: &Value) -> Option<(&'static str, &Value)> {
    MESSAGE_KINDS
        .iter()
        .find_map(|k| message.get(*k).map(|body| (*k, body)))
}

fn str_field<'a>(body: &'a Value, key: &str) -> &'a str {
    body.get(key).and_then(Value::as_str).unwrap_or("")
}

/// A validator instance path, relative to the message's payload.
fn relative_path(instance: &str, kind: &str) -> String {
    let prefix = format!("/{kind}");
    match instance.strip_prefix(&prefix) {
        Some(rest) => rest.to_string(),
        None => instance.to_string(),
    }
}

/// A schema error, phrased for a model to act on.
fn schema_message(error: &jsonschema::ValidationError<'_>) -> String {
    let text = error.to_string();
    if matches!(error.kind().keyword(), "oneOf" | "anyOf") {
        let shown = truncate(&error.instance().to_string(), 120);
        return format!(
            "{shown} has the wrong shape here (expected a literal of the right type, \
             {{\"path\": \"/…\"}}, or a catalog function call {{\"call\": …, \"args\": …}})"
        );
    }
    truncate(&text, 300)
}

fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let cut: String = text.chars().take(max).collect();
    format!("{cut}…")
}
