//! Post-parse source transform: **by-reference closure capture** for the JSON
//! Elpian AST that js2elpian produces.
//!
//! The VM captures closure upvalues *by value*, but JavaScript closures capture
//! *by reference* — `arr.forEach(x => sum += x)` must mutate the enclosing
//! `sum`. We recover that without a VM change, exactly as the Dart front-end
//! does: a local that is captured by a nested closure is **boxed** into a
//! one-element array (`var v = [init]`); reads of it become `v[0]` and writes
//! `v[0] = …`. Arrays are reference types in the VM, so the closure and the
//! enclosing scope share one box and see each other's mutations.
//!
//! In this front-end arrow / function expressions are already lifted to
//! synthetic `functionDefinition`s hoisted as siblings in the scope that uses
//! them (see the parser). So the "nested closures" of a scope are the
//! `functionDefinition` nodes sitting in its statement list, and a captured
//! local is one declared in the scope and referenced inside one of those.
//!
//! Implementation note: the walkers below descend the JSON generically —
//! through any plain container object/array down to the typed nodes — and only
//! the three binding-introducing node kinds (`definition`, `assignment`,
//! `functionDefinition`) need special handling, because those are the only
//! places an `identifier` node is a *binding* rather than a read. Everything
//! else an identifier appears in is a read.

use std::collections::HashSet;

use serde_json::{json, Value};

/// Apply the by-reference boxing transform to a whole program AST in place.
pub(crate) fn box_captured_program(program: &mut Value) {
    if let Some(body) = program.get_mut("body").and_then(|b| b.as_array_mut()) {
        box_captured_body(body);
    }
}

/// Box the captured locals of one scope's statement list, having first recursed
/// into the nested function scopes it contains (which box their own locals).
fn box_captured_body(stmts: &mut [Value]) {
    for s in stmts.iter_mut() {
        recurse_into_fns(s);
    }
    let mut declared = HashSet::new();
    for s in stmts.iter() {
        collect_declared(s, &mut declared);
    }
    let mut in_closures = HashSet::new();
    for s in stmts.iter() {
        collect_closure_refs(s, &mut in_closures);
    }
    let boxed: HashSet<String> = declared.intersection(&in_closures).cloned().collect();
    if boxed.is_empty() {
        return;
    }
    for s in stmts.iter_mut() {
        rewrite(s, &boxed);
    }
}

/// Descend to every nested `functionDefinition` body and box *its* captured
/// locals, without crossing into it for the enclosing level's own analysis.
fn recurse_into_fns(node: &mut Value) {
    if node["type"] == "functionDefinition" {
        if let Some(body) = node["data"]["body"].as_array_mut() {
            box_captured_body(body);
        }
        return;
    }
    if let Value::Object(map) = node {
        for (_k, v) in map.iter_mut() {
            recurse_into_fns_any(v);
        }
    }
}
fn recurse_into_fns_any(v: &mut Value) {
    match v {
        Value::Object(map) => {
            if map.contains_key("type") {
                recurse_into_fns(v);
            } else {
                for (_k, child) in map.iter_mut() {
                    recurse_into_fns_any(child);
                }
            }
        }
        Value::Array(arr) => {
            for child in arr.iter_mut() {
                recurse_into_fns_any(child);
            }
        }
        _ => {}
    }
}

// ---- analysis --------------------------------------------------------------

/// Names *declared* at this scope level (`definition` / `destructure` bindings),
/// recursing through control-flow blocks but not into nested function scopes.
/// Function names are excluded — a function value is never boxed.
fn collect_declared(node: &Value, out: &mut HashSet<String>) {
    match node["type"].as_str().unwrap_or("") {
        "definition" => {
            if let Some(n) = node["data"]["leftSide"]["data"]["name"].as_str() {
                out.insert(n.to_string());
            }
        }
        "destructure" => {
            if let Some(bs) = node["data"]["bindings"].as_array() {
                for b in bs {
                    if b.get("hole").and_then(|v| v.as_bool()).unwrap_or(false) {
                        continue;
                    }
                    if let Some(n) = b["name"].as_str() {
                        out.insert(n.to_string());
                    }
                }
            }
        }
        "functionDefinition" => {}
        _ => descend_ref(node, &mut |n| collect_declared(n, out)),
    }
}

/// Names referenced inside a nested `functionDefinition` at this scope level.
fn collect_closure_refs(node: &Value, out: &mut HashSet<String>) {
    if node["type"] == "functionDefinition" {
        collect_idents(node, out);
        return;
    }
    descend_ref(node, &mut |n| collect_closure_refs(n, out));
}

/// Every identifier name read in a subtree (deep, into nested closures).
fn collect_idents(node: &Value, out: &mut HashSet<String>) {
    if node["type"] == "identifier" {
        if let Some(n) = node["data"]["name"].as_str() {
            out.insert(n.to_string());
        }
        return;
    }
    descend_ref(node, &mut |n| collect_idents(n, out));
}

/// Visit each typed sub-node of `node` (through plain container objects/arrays).
fn descend_ref(node: &Value, f: &mut dyn FnMut(&Value)) {
    if let Some(data) = node.get("data") {
        descend_any_ref(data, f);
    }
}
fn descend_any_ref(v: &Value, f: &mut dyn FnMut(&Value)) {
    match v {
        Value::Object(map) => {
            if map.contains_key("type") {
                f(v);
            } else {
                for (_k, child) in map {
                    descend_any_ref(child, f);
                }
            }
        }
        Value::Array(arr) => {
            for child in arr {
                descend_any_ref(child, f);
            }
        }
        _ => {}
    }
}

// ---- rewrite ---------------------------------------------------------------

fn box_read(n: &str) -> Value {
    json!({ "type": "indexer", "data": {
        "target": { "type": "identifier", "data": { "name": n } },
        "index": { "type": "i64", "data": { "value": 0 } } } })
}

fn rewrite(node: &mut Value, boxed: &HashSet<String>) {
    match node["type"].as_str().unwrap_or("").to_string().as_str() {
        "identifier" => {
            if let Some(n) = node["data"]["name"].as_str() {
                if boxed.contains(n) {
                    *node = box_read(n);
                }
            }
        }
        "definition" => {
            rewrite(&mut node["data"]["rightSide"], boxed);
            if let Some(n) = node["data"]["leftSide"]["data"]["name"].as_str() {
                if boxed.contains(n) {
                    let inner = node["data"]["rightSide"].clone();
                    node["data"]["rightSide"] =
                        json!({ "type": "array", "data": { "value": [inner] } });
                }
            }
        }
        "assignment" => {
            rewrite(&mut node["data"]["rightSide"], boxed);
            match node["data"]["leftSide"]["type"].as_str().unwrap_or("") {
                "identifier" => {
                    // A boxed simple target becomes `v[0] = …` — still a native
                    // indexer assignment (its target is the identifier `v`).
                    if let Some(n) = node["data"]["leftSide"]["data"]["name"].as_str() {
                        if boxed.contains(n) {
                            let n = n.to_string();
                            node["data"]["leftSide"] = box_read(&n);
                        }
                    }
                }
                "indexer" => {
                    // A member / index assignment (`a.b = v` / `a[i] = v`). Rewrite
                    // its base and index as reads. If boxing turned the base into a
                    // nested expression (no longer a plain identifier), the native
                    // indexer-assignment can't address it, so route the store
                    // through the `__setIndex` builtin — mirroring how the parser
                    // lowers deep/computed targets.
                    rewrite(&mut node["data"]["leftSide"]["data"]["target"], boxed);
                    rewrite(&mut node["data"]["leftSide"]["data"]["index"], boxed);
                    if node["data"]["leftSide"]["data"]["target"]["type"] != "identifier" {
                        let base = node["data"]["leftSide"]["data"]["target"].clone();
                        let index = node["data"]["leftSide"]["data"]["index"].clone();
                        let rhs = node["data"]["rightSide"].clone();
                        *node = json!({ "type": "functionCall", "data": {
                            "callee": { "type": "identifier", "data": { "name": "__setIndex" } },
                            "args": [base, index, rhs] } });
                    }
                }
                _ => rewrite(&mut node["data"]["leftSide"], boxed),
            }
        }
        "functionDefinition" => {
            // A parameter, or a local re-declared inside the closure, shadows a
            // boxed outer name; drop those before descending into the body.
            let mut inner = boxed.clone();
            if let Some(ps) = node["data"]["params"].as_array() {
                for p in ps {
                    if let Some(s) = p.as_str() {
                        inner.remove(s);
                    }
                }
            }
            if let Some(body) = node["data"]["body"].as_array() {
                let mut inner_declared = HashSet::new();
                for s in body {
                    collect_declared(s, &mut inner_declared);
                }
                for d in &inner_declared {
                    inner.remove(d);
                }
            }
            if let Some(body) = node["data"]["body"].as_array_mut() {
                for s in body {
                    rewrite(s, &inner);
                }
            }
        }
        _ => {
            if let Some(data) = node.get_mut("data") {
                rewrite_any(data, boxed);
            }
        }
    }
}
fn rewrite_any(v: &mut Value, boxed: &HashSet<String>) {
    match v {
        Value::Object(map) => {
            if map.contains_key("type") {
                rewrite(v, boxed);
            } else {
                for (_k, child) in map.iter_mut() {
                    rewrite_any(child, boxed);
                }
            }
        }
        Value::Array(arr) => {
            for child in arr.iter_mut() {
                rewrite_any(child, boxed);
            }
        }
        _ => {}
    }
}
