use std::{
    cell::RefCell,
    collections::HashMap,
    rc::Rc,
};

use serde_json::{json, Value};

// #[wasm_bindgen]
// extern "C" {
//     #[wasm_bindgen(js_namespace = console)]
//     fn log(s: &str);

//     #[wasm_bindgen(js_namespace = console, js_name = log)]
//     fn log_u32(a: u32);

//     #[wasm_bindgen(js_namespace = console, js_name = log)]
//     fn log_many(a: &str, b: &str);
// }

fn log(s: &str) {
    println!("{}", s);
}

fn serialize_expr(val: serde_json::Value) -> Vec<u8> {
    // log(&val.to_string());
    let mut result: Vec<u8> = vec![];
    match val["type"].as_str().unwrap() {
        // The first-class null literal (tag 0x00). Every front-end lowers its
        // own "absent value" spelling (`null`, `undefined`, `nil`, `None`, …)
        // to this one neutral literal at compile time.
        "null" => {
            result.push(0);
        }
        "i16" => {
            result.push(1);
            result.append(
                &mut i16::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i16).to_vec(),
            );
        }
        "i32" => {
            result.push(2);
            result.append(
                &mut i32::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i32).to_vec(),
            );
        }
        "i64" => {
            result.push(3);
            result.append(
                &mut i64::to_be_bytes(val["data"]["value"].as_i64().unwrap() as i64).to_vec(),
            );
        }
        "f32" => {
            result.push(4);
            result.append(
                &mut f32::to_be_bytes(val["data"]["value"].as_f64().unwrap() as f32).to_vec(),
            );
        }
        "f64" => {
            result.push(5);
            result.append(
                &mut f64::to_be_bytes(val["data"]["value"].as_f64().unwrap() as f64).to_vec(),
            );
        }
        "bool" => {
            result.push(6);
            result.push(if val["data"]["value"].as_bool().unwrap() {
                0x01
            } else {
                0x00
            });
        }
        "string" => {
            result.push(7);
            let mut value_bytes = val["data"]["value"].as_str().unwrap().as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(value_bytes.len() as i32).to_vec());
            result.append(&mut value_bytes);
        }
        "identifier" => {
            result.push(0x0b);
            let mut value_bytes = val["data"]["name"].as_str().unwrap().as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(value_bytes.len() as i32).to_vec());
            result.append(&mut value_bytes);
        }
        "indexer" => {
            result.push(0x0c);
            result.append(&mut serialize_expr(val["data"]["target"].clone()));
            result.append(&mut serialize_expr(val["data"]["index"].clone()));
        }
        "cast" => {
            result.push(0xfd);
            result.append(&mut serialize_expr(val["data"]["value"].clone()));
            let mut tt_bytes = val["data"]["targetType"]
                .as_str()
                .unwrap()
                .as_bytes()
                .to_vec();
            result.append(&mut i32::to_be_bytes(tt_bytes.len() as i32).to_vec());
            result.append(&mut tt_bytes);
        }
        "typeTest" => {
            // Reified `is` / `as`. Layout: [0xed][cast flag][value][type name].
            // `cast` is 0 for `is` (yields a bool) and 1 for `as` (yields the
            // value, trapping on a mismatch). The type name is the base type as a
            // length-prefixed string.
            result.push(0xed);
            result.push(if val["data"]["cast"].as_bool().unwrap_or(false) { 1 } else { 0 });
            result.append(&mut serialize_expr(val["data"]["value"].clone()));
            let type_bytes = val["data"]["typeName"].as_str().unwrap_or("").as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(type_bytes.len() as i32).to_vec());
            result.append(&mut type_bytes.clone());
        }
        "object" => {
            result.push(8);
            result.append(&mut i64::to_be_bytes(-2).to_vec());
            // Two authoring forms are accepted. The classic `data.value` map is an
            // unordered `{ key: expr }` object. The `data.entries` array is the
            // *ordered* form that additionally supports **spread entries**
            // (`{ "spread": <expr> }`, which merges another object's members in
            // place). Each property — including a spread — is one serialized pair:
            // a spread emits the reserved spread-key marker (0x1a) where the key
            // literal would go, so the object builder recognises it and merges
            // rather than inserts. `props_len` counts entries, not the expanded
            // member count.
            if let Some(entries) = val["data"].get("entries").and_then(|e| e.as_array()) {
                result.append(&mut i32::to_be_bytes(entries.len() as i32).to_vec());
                for entry in entries.iter() {
                    if let Some(spread) = entry.get("spread") {
                        result.push(0x1a); // spread-key marker (no operand)
                        result.append(&mut serialize_expr(spread.clone()));
                    } else {
                        result.push(7);
                        let key = entry["key"].as_str().unwrap();
                        let mut key_bytes = key.as_bytes().to_vec();
                        result.append(&mut i32::to_be_bytes(key_bytes.len() as i32).to_vec());
                        result.append(&mut key_bytes);
                        result.append(&mut serialize_expr(entry["value"].clone()));
                    }
                }
            } else {
                result.append(&mut i32::to_be_bytes(val["data"]["value"].as_object().unwrap().iter().len() as i32).to_vec());
                for (k, v) in val["data"]["value"].as_object().unwrap().iter() {
                    result.push(7);
                    let mut key_bytes = k.as_bytes().to_vec();
                    result.append(&mut i32::to_be_bytes(key_bytes.len() as i32).to_vec());
                    result.append(&mut key_bytes);
                    result.append(&mut serialize_expr(v.clone()));
                }
            }
        }
        "array" => {
            result.push(9);
            result.append(
                &mut i32::to_be_bytes(val["data"]["value"].as_array().unwrap().iter().len() as i32)
                    .to_vec(),
            );
            for v in val["data"]["value"].as_array().unwrap().iter() {
                result.append(&mut serialize_expr(v.clone()));
            }
        }
        "callback" => {
            result.append(&mut serialize_expr(val["data"]["value"]["funcId"].clone()));
        }
        "not" => {
            result.push(0xfc);
            result.append(&mut serialize_expr(val["data"]["value"].clone()));
        }
        "logical" => {
            // Short-circuit `&&` / `||` / `??`. Layout: [0xef][flag][op1][op2],
            // where `flag` is 0 for `&&`, 1 for `||`, and 2 for the null-coalescing
            // `??` (Dart / JS): evaluate `op1` and, only if it is null, evaluate
            // `op2`. The "skip the right operand" target is recovered at decode time
            // as a unit index (the unit just past `op2`), so no byte offsets are
            // baked here.
            let flag = match val["data"]["operation"].as_str().unwrap() {
                "||" => 1u8,
                "??" => 2u8,
                _ => 0u8, // "&&"
            };
            result.push(0xef);
            result.push(flag);
            result.append(&mut serialize_expr(val["data"]["operand1"].clone()));
            result.append(&mut serialize_expr(val["data"]["operand2"].clone()));
        }
        "ternary" => {
            // `c ? a : b`. Layout: [0xee][cond][consequent][alternate]. The
            // branch boundaries are recovered as unit indices at decode time.
            result.push(0xee);
            result.append(&mut serialize_expr(val["data"]["condition"].clone()));
            result.append(&mut serialize_expr(val["data"]["consequent"].clone()));
            result.append(&mut serialize_expr(val["data"]["alternate"].clone()));
        }
        "arithmetic" => {
            match val["data"]["operation"].as_str().unwrap() {
                "==" => {
                    result.push(0xf0);
                }
                ">" => {
                    result.push(0xf1);
                }
                ">=" => {
                    result.push(0xf2);
                }
                "<" => {
                    result.push(0xf3);
                }
                "<=" => {
                    result.push(0xf4);
                }
                "!=" => {
                    result.push(0xf5);
                }
                "+" => {
                    result.push(0xf6);
                }
                "-" => {
                    result.push(0xf7);
                }
                "*" => {
                    result.push(0xf8);
                }
                "/" => {
                    result.push(0xf9);
                }
                "%" => {
                    result.push(0xfa);
                }
                "^" => {
                    result.push(0xfb);
                }
                _ => {}
            };
            result.append(&mut serialize_expr(val["data"]["operand1"].clone()));
            result.append(&mut serialize_expr(val["data"]["operand2"].clone()));
        }
        "functionCall" => {
            result.push(0x0d);
            result.append(&mut serialize_expr(val["data"]["callee"].clone()));
            result.append(
                &mut i32::to_be_bytes(val["data"]["args"].as_array().unwrap().len() as i32)
                    .to_vec(),
            );
            val["data"]["args"]
                .as_array()
                .unwrap()
                .iter()
                .for_each(|arg| {
                    result.append(&mut serialize_expr(arg.clone()));
                });
        }
        "host_call" => {
            result.push(0x0d);
            result.append(&mut serialize_expr(json!(
                {
                    "type": "identifier",
                    "data": {
                        "name": "askHost",
                    }
                }
            )));
            result.append(&mut i32::to_be_bytes(2).to_vec());
            result.append(&mut serialize_expr(json!(
                {
                    "type": "string",
                    "data": {
                        "value": val["data"]["name"].as_str().unwrap().to_string(),
                    }
                }
            )));
            let args = val["data"]["args"].as_array().unwrap().clone();
            let input = json!({
                "type": "array",
                "data": {
                    "value": args
                },
            });
            result.append(&mut serialize_expr(input.clone()));
        }
        "spread" => {
            // Spread element (`...value`): a universal "expand this collection in
            // place" marker. Valid inside an array literal, an object literal
            // (via the `entries` form), and a call's argument list. Layout:
            // [0x19][inner value expression]. At run time the inner value is
            // wrapped in a spread marker that the enclosing array/object/call
            // builder flattens. `value` is the collection to expand.
            result.push(0x19);
            result.append(&mut serialize_expr(val["data"]["value"].clone()));
        }
        "template" => {
            // Interpolated / template string: an ordered list of `parts`, each an
            // arbitrary value expression, concatenated using the VM's display
            // coercion (a string contributes itself verbatim; other values their
            // text form). Literal text segments are simply string-literal parts.
            // Layout: [0x1b][part count: i32][part expression]*.
            result.push(0x1b);
            let parts = val["data"]["parts"].as_array().unwrap();
            result.append(&mut i32::to_be_bytes(parts.len() as i32).to_vec());
            for part in parts.iter() {
                result.append(&mut serialize_expr(part.clone()));
            }
        }
        _ => {
            panic!("unknown val type");
        }
    }
    result
}

/// Serialize the metadata + inline expressions of a `destructure` statement.
/// Layout produced (statement opcode 0x1c): `[0x1c][flags][binding count: i32]`
/// then, for each binding, its fixed metadata record, then the **source**
/// value expression, then the default-value expression of every binding that
/// declares one, in binding order. The executor evaluates the source first and
/// each default next, binding by key (object) or position (array).
///
/// `flags` bit 0 selects array (1) vs object (0) form. Per-binding metadata:
///   object: `[bind flags][key len: i32][key][name len: i32][name]`
///   array:  `[bind flags][name len: i32][name]`
/// where a binding's flags are bit0 = has default, bit1 = is rest, bit2 = is
/// hole (array only; no name/key follows).
fn serialize_destructure(data: &Value) -> Vec<u8> {
    let mut result: Vec<u8> = vec![];
    result.push(0x1c);
    let is_array = data["isArray"].as_bool().unwrap_or(false);
    result.push(if is_array { 1 } else { 0 });
    let bindings = data["bindings"].as_array().unwrap();
    result.append(&mut i32::to_be_bytes(bindings.len() as i32).to_vec());
    for b in bindings.iter() {
        let is_hole = b.get("hole").and_then(|v| v.as_bool()).unwrap_or(false);
        let is_rest = b.get("rest").and_then(|v| v.as_bool()).unwrap_or(false);
        let has_default = b.get("default").is_some();
        let mut flags = 0u8;
        if has_default { flags |= 1; }
        if is_rest { flags |= 2; }
        if is_hole { flags |= 4; }
        result.push(flags);
        if is_hole {
            continue;
        }
        if !is_array {
            // Object bindings carry the source key; it defaults to the bound name.
            let name = b["name"].as_str().unwrap();
            let key = b.get("key").and_then(|k| k.as_str()).unwrap_or(name);
            let mut key_bytes = key.as_bytes().to_vec();
            result.append(&mut i32::to_be_bytes(key_bytes.len() as i32).to_vec());
            result.append(&mut key_bytes);
        }
        let name = b["name"].as_str().unwrap();
        let mut name_bytes = name.as_bytes().to_vec();
        result.append(&mut i32::to_be_bytes(name_bytes.len() as i32).to_vec());
        result.append(&mut name_bytes);
    }
    // Source expression, then each present default in binding order.
    result.append(&mut serialize_expr(data["source"].clone()));
    for b in bindings.iter() {
        if let Some(def) = b.get("default") {
            result.append(&mut serialize_expr(def.clone()));
        }
    }
    result
}

fn serialize_condition_chain(
    operation: Value,
    is_conditioned: bool,
    start_point: usize,
) -> (Vec<u8>, Vec<usize>) {
    let mut result: Vec<u8> = vec![];
    let mut baps: Vec<usize> = vec![];
    result.push(0x10);
    if is_conditioned {
        result.push(0x01);
        result.append(&mut serialize_expr(operation["data"]["condition"].clone()).to_vec());
    } else {
        result.push(0x00);
    }
    let body_start = if is_conditioned {
        start_point + result.len() + 8 + 8 + 8 + 8
    } else {
        start_point + result.len() + 8 + 8 + 8
    };
    let body = compile_ast(operation["data"].clone(), body_start);
    let body_end = body_start + body.len();
    result.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
    result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
    let mut after_body: Vec<u8> = vec![];
    if let Some(elseif_stmt) = operation["data"].get("elseifStmt") {
        let (mut compiled_body, mut branch_after_points) =
            serialize_condition_chain(elseif_stmt.clone(), true, body_end);
        after_body.append(&mut compiled_body);
        baps.append(&mut branch_after_points);
    } else if let Some(else_stmt) = operation["data"].get("elseStmt") {
        let (mut compiled_body, mut branch_after_points) =
            serialize_condition_chain(else_stmt.clone(), false, body_end);
        after_body.append(&mut compiled_body);
        baps.append(&mut branch_after_points);
    }
    if is_conditioned {
        result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
    }
    baps.push(start_point + result.len());
    result.append(&mut vec![0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    result.append(&mut body.clone());
    result.append(&mut after_body);
    (result, baps)
}

// ---- free-variable (closure capture) analysis ------------------------------
//
// A closure only needs to snapshot the enclosing locals it actually references
// — not the whole scope chain. For each `functionDefinition` the compiler walks
// the body and computes the set of identifiers it uses that are *not* bound
// within it (its own params, `let`/`const`/`var` declarations, and nested
// function names), unioned transitively with the free variables of any nested
// closures (so an upvalue needed only by an inner closure still flows through).
// This list is serialised with the function; at runtime the executor captures
// just these names from the enclosing frames (see `capture_named`) instead of
// cloning every local — far cheaper to create a closure, and a smaller frame to
// seed on every call. Names that turn out to be globals simply aren't found in
// the enclosing scopes and resolve normally, exactly as before.

/// Identifiers bound *at this function's own level*: nested-function names and
/// `let`/`const`/`var` declarations, including those inside its `if`/`loop`/
/// `switch` blocks — but never descending into a nested function's body (that is
/// a separate scope). References to these resolve locally, so they are not free.
fn collect_bound(node: &Value, bound: &mut std::collections::BTreeSet<String>) {
    match node["type"].as_str().unwrap_or("") {
        "definition" => {
            if let Some(n) = node["data"]["leftSide"]["data"]["name"].as_str() {
                bound.insert(n.to_string());
            }
        }
        "functionDefinition" => {
            if let Some(n) = node["data"]["name"].as_str() {
                bound.insert(n.to_string());
            }
            // Do not descend: the nested function's locals are its own scope.
        }
        "ifStmt" => {
            let d = &node["data"];
            if let Some(b) = d["body"].as_array() { for s in b { collect_bound(s, bound); } }
            if d.get("elseifStmt").is_some() { collect_bound(&d["elseifStmt"], bound); }
            if let Some(e) = d.get("elseStmt") {
                if let Some(b) = e["data"]["body"].as_array() { for s in b { collect_bound(s, bound); } }
            }
        }
        "loopStmt" => {
            if let Some(b) = node["data"]["body"].as_array() { for s in b { collect_bound(s, bound); } }
        }
        "tryStmt" => {
            if let Some(b) = node["data"]["body"].as_array() { for s in b { collect_bound(s, bound); } }
            if let Some(b) = node["data"]["catchBody"].as_array() { for s in b { collect_bound(s, bound); } }
        }
        "switchStmt" => {
            if let Some(cases) = node["data"]["cases"].as_array() {
                for c in cases {
                    if let Some(b) = c["body"]["body"].as_array() { for s in b { collect_bound(s, bound); } }
                }
            }
        }
        "destructure" => {
            // Every non-hole binding introduces a name at this scope level.
            if let Some(bindings) = node["data"]["bindings"].as_array() {
                for b in bindings {
                    if b.get("hole").and_then(|v| v.as_bool()).unwrap_or(false) { continue; }
                    if let Some(n) = b["name"].as_str() { bound.insert(n.to_string()); }
                }
            }
        }
        _ => {}
    }
}

/// Identifiers *referenced* in `node` (and the free variables of nested
/// closures, which must flow through this scope). A `definition`'s left side is
/// a binding, not a use; a nested `functionDefinition` contributes its own free
/// set rather than its raw identifiers.
fn collect_used(node: &Value, used: &mut std::collections::BTreeSet<String>) {
    match node["type"].as_str().unwrap_or("") {
        "identifier" => {
            if let Some(n) = node["data"]["name"].as_str() { used.insert(n.to_string()); }
        }
        "functionDefinition" => {
            let nparams = node["data"]["params"].as_array().cloned().unwrap_or_default();
            let nbody = node["data"]["body"].as_array().cloned().unwrap_or_default();
            for f in free_vars(&nparams, &nbody) { used.insert(f); }
        }
        "indexer" => {
            collect_used(&node["data"]["target"], used);
            collect_used(&node["data"]["index"], used);
        }
        "functionCall" => {
            collect_used(&node["data"]["callee"], used);
            if let Some(args) = node["data"]["args"].as_array() { for a in args { collect_used(a, used); } }
        }
        "arithmetic" | "logical" => {
            collect_used(&node["data"]["operand1"], used);
            collect_used(&node["data"]["operand2"], used);
        }
        "ternary" => {
            collect_used(&node["data"]["condition"], used);
            collect_used(&node["data"]["consequent"], used);
            collect_used(&node["data"]["alternate"], used);
        }
        "not" | "cast" | "typeTest" => collect_used(&node["data"]["value"], used),
        "definition" => collect_used(&node["data"]["rightSide"], used),
        "assignment" => {
            collect_used(&node["data"]["leftSide"], used);
            collect_used(&node["data"]["rightSide"], used);
        }
        "returnOperation" => collect_used(&node["data"]["value"], used),
        "object" => {
            if let Some(entries) = node["data"].get("entries").and_then(|e| e.as_array()) {
                for entry in entries {
                    if let Some(spread) = entry.get("spread") { collect_used(spread, used); }
                    else { collect_used(&entry["value"], used); }
                }
            }
            if let Some(obj) = node["data"]["value"].as_object() {
                for (_k, v) in obj { collect_used(v, used); }
            }
        }
        "array" => {
            if let Some(arr) = node["data"]["value"].as_array() {
                for v in arr { collect_used(v, used); }
            }
        }
        "spread" => collect_used(&node["data"]["value"], used),
        "template" => {
            if let Some(parts) = node["data"]["parts"].as_array() {
                for p in parts { collect_used(p, used); }
            }
        }
        "destructure" => {
            collect_used(&node["data"]["source"], used);
            if let Some(bindings) = node["data"]["bindings"].as_array() {
                for b in bindings {
                    if let Some(def) = b.get("default") { collect_used(def, used); }
                }
            }
        }
        "ifStmt" => {
            let d = &node["data"];
            collect_used(&d["condition"], used);
            if let Some(b) = d["body"].as_array() { for s in b { collect_used(s, used); } }
            if d.get("elseifStmt").is_some() { collect_used(&d["elseifStmt"], used); }
            if let Some(e) = d.get("elseStmt") {
                if let Some(b) = e["data"]["body"].as_array() { for s in b { collect_used(s, used); } }
            }
        }
        "loopStmt" => {
            collect_used(&node["data"]["condition"], used);
            if let Some(b) = node["data"]["body"].as_array() { for s in b { collect_used(s, used); } }
        }
        "throwOperation" => collect_used(&node["data"]["value"], used),
        "tryStmt" => {
            // The catch binding (`errName`) is a runtime scope binding; treating
            // its uses as free at worst captures an outer same-named variable
            // needlessly, which is harmless.
            if let Some(b) = node["data"]["body"].as_array() { for s in b { collect_used(s, used); } }
            if let Some(b) = node["data"]["catchBody"].as_array() { for s in b { collect_used(s, used); } }
        }
        "switchStmt" => {
            collect_used(&node["data"]["value"], used);
            if let Some(cases) = node["data"]["cases"].as_array() {
                for c in cases {
                    collect_used(&c["value"], used);
                    if let Some(b) = c["body"]["body"].as_array() { for s in b { collect_used(s, used); } }
                }
            }
        }
        _ => {}
    }
}

/// The free variables of a function: identifiers it (transitively) references,
/// minus everything bound at its own level (params, locals, nested-fn names).
fn free_vars(params: &[Value], body: &[Value]) -> Vec<String> {
    let mut bound: std::collections::BTreeSet<String> =
        params.iter().filter_map(|p| p.as_str().map(|s| s.to_string())).collect();
    for stmt in body { collect_bound(stmt, &mut bound); }
    let mut used: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for stmt in body { collect_used(stmt, &mut used); }
    used.into_iter().filter(|n| !bound.contains(n)).collect()
}

pub fn compile_ast(program: serde_json::Value, start_point: usize) -> Vec<u8> {
    let mut result: Vec<u8> = vec![];
    let mut op_counter: i64 = 1;
    let mut step_start_map: HashMap<i64, usize> = HashMap::new();
    let mut reserved_branch_map: HashMap<i64, Vec<usize>> = HashMap::new();
    for operation in program["body"].as_array().unwrap().iter() {
        step_start_map
            .entry(op_counter)
            .or_insert(start_point + result.len());
        match operation["type"].as_str().unwrap() {
            "jumpOperation" => {
                result.push(0x15);
                let true_branch = result.len();
                result.extend_from_slice(&[0u8; 8]);
                let true_step = operation["data"]["stepNumber"].as_i64().unwrap();
                reserved_branch_map
                    .entry(true_step)
                    .or_default()
                    .push(true_branch);
            }
            "conditionalBranch" => {
                result.push(0x16);
                result.append(&mut serialize_expr(operation["data"]["condition"].clone()));
                let true_branch = result.len();
                result.extend_from_slice(&[0u8; 8]);
                let false_branch = result.len();
                result.extend_from_slice(&[0u8; 8]);
                let true_step = operation["data"]["trueBranch"].as_i64().unwrap();
                let false_step = operation["data"]["falseBranch"].as_i64().unwrap();
                reserved_branch_map
                    .entry(true_step)
                    .or_default()
                    .push(true_branch);
                reserved_branch_map
                    .entry(false_step)
                    .or_default()
                    .push(false_branch);
            }
            "host_call" => {
                result.push(0x0d);
                result.append(&mut serialize_expr(json!(
                    {
                        "type": "identifier",
                        "data": {
                            "name": "askHost",
                        }
                    }
                )));
                result.append(&mut i32::to_be_bytes(2).to_vec());
                result.append(&mut serialize_expr(json!(
                    {
                        "type": "string",
                        "data": {
                            "value": operation["data"]["name"].as_str().unwrap().to_string(),
                        }
                    }
                )));
                let args = operation["data"]["args"].as_array().unwrap().clone();
                let input = json!({
                    "type": "array",
                    "data": {
                        "value": args
                    },
                });
                result.append(&mut serialize_expr(input.clone()));
            }
            "returnOperation" => {
                result.push(0x14);
                result.append(&mut serialize_expr(operation["data"]["value"].clone()).to_vec());
            }
            // Throw statement: evaluate the value expression and raise it. The
            // nearest enclosing `tryStmt`'s catch body receives it; with no
            // handler the run traps. Layout: [0x1e][value expression].
            "throwOperation" => {
                result.push(0x1e);
                result.append(&mut serialize_expr(operation["data"]["value"].clone()).to_vec());
            }
            // Try/catch statement — the VM's neutral exception mechanism. Both
            // the protected body and the handler are plain statement ranges; the
            // handler binds the thrown value under `errName`. Layout:
            // [0x1d][errName][body_start][body_end][catch_start][catch_end]
            // [body...][catch...] (all i64 byte offsets, rewritten to unit
            // indices at decode).
            "tryStmt" => {
                result.push(0x1d);
                let err_name = operation["data"]["errName"].as_str().unwrap_or("e");
                let mut name_bytes = err_name.as_bytes().to_vec();
                result.append(&mut i32::to_be_bytes(name_bytes.len() as i32).to_vec());
                result.append(&mut name_bytes);
                let body_start = start_point + result.len() + 8 * 4;
                let body = compile_ast(
                    json!({ "body": operation["data"]["body"].clone() }),
                    body_start,
                );
                let body_end = body_start + body.len();
                let catch_body = compile_ast(
                    json!({ "body": operation["data"]["catchBody"].clone() }),
                    body_end,
                );
                let catch_end = body_end + catch_body.len();
                result.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(catch_end as i64).to_vec());
                result.append(&mut body.clone());
                result.append(&mut catch_body.clone());
            }
            "destructure" => {
                // Destructuring binding: evaluate one source value and bind a list
                // of names from its members (object keys) or positions (array
                // indices), with optional per-binding defaults and a trailing rest
                // binding. A native statement opcode so every front-end shares one
                // implementation. See `serialize_destructure`.
                result.append(&mut serialize_destructure(&operation["data"]));
            }
            "continueStmt" => {
                result.push(0x17);
            }
            "breakStmt" => {
                result.push(0x18);
            }
            // A bare short-circuit / conditional expression statement (e.g.
            // `ready && start()`): evaluate it for its side effects; the produced
            // value is discarded like any other expression-statement result.
            "logical" | "ternary" => {
                result.append(&mut serialize_expr(operation.clone()));
            }
            "ifStmt" => {
                let (mut compiled_code, baps) =
                    serialize_condition_chain(operation.clone(), true, start_point + result.len());
                let branch_after =
                    i64::to_be_bytes((start_point + result.len() + compiled_code.len()) as i64)
                        .to_vec();
                for bap in baps.iter() {
                    let s = *bap - start_point - result.len();
                    let e = *bap + 8 - start_point - result.len();
                    compiled_code[s..e].copy_from_slice(branch_after.as_slice());
                }
                result.append(&mut compiled_code);
            }
            "loopStmt" => {
                let loop_start = start_point + result.len();
                result.push(0x11);
                result.append(&mut serialize_expr(operation["data"]["condition"].clone()).to_vec());
                let body_start = start_point + result.len() + 8 + 8 + 8;
                let mut body = compile_ast(operation["data"].clone(), body_start);
                body.push(0x15);
                body.append(&mut i64::to_be_bytes(loop_start as i64).to_vec());
                let body_end = body_start + body.len();
                result.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                result.append(&mut body.clone());
            }
            "switchStmt" => {
                result.push(0x12);
                result.append(&mut serialize_expr(operation["data"]["value"].clone()).to_vec());
                let mut inner: Vec<u8> = vec![];
                for case_val in operation["data"]["cases"].as_array().unwrap().iter() {
                    inner.append(&mut serialize_expr(case_val["value"].clone()));
                    let body_start = start_point + result.len() + 8 + 8 + inner.len() + 8 + 8;
                    let mut body: Vec<u8> = compile_ast(case_val["body"].clone(), body_start);
                    let body_end = body_start + body.len();
                    inner.append(&mut i64::to_be_bytes(body_start as i64).to_vec());
                    inner.append(&mut i64::to_be_bytes(body_end as i64).to_vec());
                    inner.append(&mut body);
                }
                result.append(
                    &mut i64::to_be_bytes(
                        (start_point + result.len() + inner.len() + 8 + 8) as i64,
                    )
                    .to_vec(),
                );
                result.append(
                    &mut i64::to_be_bytes(
                        operation["data"]["cases"].as_array().unwrap().len() as i64
                    )
                    .to_vec(),
                );
                result.append(&mut inner);
            }
            "functionDefinition" => {
                result.push(0x13);
                let mut str_bytes = operation["data"]["name"]
                    .as_str()
                    .unwrap()
                    .as_bytes()
                    .to_vec();
                let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                result.append(&mut len_bytes);
                result.append(&mut str_bytes);
                result.append(
                    &mut i32::to_be_bytes(
                        operation["data"]["params"].as_array().unwrap().len() as i32
                    )
                    .to_vec(),
                );
                for p_name in operation["data"]["params"].as_array().unwrap().iter() {
                    let mut str_bytes = p_name.as_str().unwrap().as_bytes().to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                }
                // Free-variable (closure capture) list: the enclosing names this
                // function references, so the runtime captures only these rather
                // than cloning the whole enclosing scope.
                let empty_params = vec![];
                let frees = free_vars(
                    operation["data"]["params"].as_array().unwrap_or(&empty_params),
                    operation["data"]["body"].as_array().unwrap_or(&empty_params),
                );
                result.append(&mut i32::to_be_bytes(frees.len() as i32).to_vec());
                for f in frees.iter() {
                    let mut str_bytes = f.as_bytes().to_vec();
                    result.append(&mut i32::to_be_bytes(str_bytes.len() as i32).to_vec());
                    result.append(&mut str_bytes);
                }
                let func_start = start_point + result.len() + 8 + 8;
                let body = compile_ast(operation["data"].clone(), func_start);
                let func_end = func_start + body.len();
                result.append(&mut i64::to_be_bytes(func_start as i64).to_vec());
                result.append(&mut i64::to_be_bytes(func_end as i64).to_vec());
                result.append(&mut body.clone());
            }
            "functionCall" => {
                result.push(0x0d);
                result.append(&mut serialize_expr(operation["data"]["callee"].clone()));
                result.append(
                    &mut i32::to_be_bytes(
                        operation["data"]["args"].as_array().unwrap().len() as i32
                    )
                    .to_vec(),
                );
                operation["data"]["args"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .for_each(|arg| {
                        result.append(&mut serialize_expr(arg.clone()));
                    });
            }
            "definition" => {
                result.push(0x0e);
                if operation["data"]["leftSide"]["type"].as_str().unwrap() == "identifier" {
                    result.push(0x0b);
                    let mut str_bytes = operation["data"]["leftSide"]["data"]["name"]
                        .as_str()
                        .unwrap()
                        .as_bytes()
                        .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                }
            }
            "assignment" => {
                result.push(0x0f);
                if operation["data"]["leftSide"]["type"].as_str().unwrap() == "identifier" {
                    result.push(0x0b);
                    let mut str_bytes = operation["data"]["leftSide"]["data"]["name"]
                        .as_str()
                        .unwrap()
                        .as_bytes()
                        .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                } else if operation["data"]["leftSide"]["type"].as_str().unwrap() == "indexer" {
                    result.push(0x0c);
                    let mut str_bytes = operation["data"]["leftSide"]["data"]["target"]["data"]
                        ["name"]
                        .as_str()
                        .unwrap()
                        .as_bytes()
                        .to_vec();
                    let mut len_bytes = i32::to_be_bytes(str_bytes.len() as i32).to_vec();
                    result.append(&mut len_bytes);
                    result.append(&mut str_bytes);
                    // The executor reads the index expression *before* the value
                    // (AssignVarExtractName → AssignVarExtractIndex → ...Value), so
                    // `a[i] = v` / `a.b = v` must serialize the index here. Without
                    // it the operands desync and the index stays unset.
                    result.append(&mut serialize_expr(
                        operation["data"]["leftSide"]["data"]["index"].clone(),
                    ));
                    result.append(&mut serialize_expr(operation["data"]["rightSide"].clone()));
                }
            }
            _ => {
                // skip
            }
        }
        op_counter += 1;
    }
    for (key, value) in reserved_branch_map {
        let step_point = *step_start_map.get(&key).unwrap();
        let sp_bytes = i64::to_be_bytes(step_point as i64).to_vec();
        for space in value.iter() {
            let address: usize = *space;
            result[address..address + 8].copy_from_slice(sp_bytes.as_slice());
        }
    }
    if result.is_empty() {
        result.push(0x00);
    }
    result
}

pub fn parse_code(program: String) -> serde_json::Value {
    let temp_prog = program.clone();
    let mut tokens: Vec<String> = vec![];
    let mut temp_token = "".to_string();
    let mut inside_string = false;
    for c in temp_prog.chars() {
        if c == '"' {
            if inside_string {
                inside_string = false;
                temp_token.push(c);
                tokens.push(temp_token);
                temp_token = "".to_string();
            } else {
                inside_string = true;
                temp_token.push(c);
            }
            continue;
        }
        let c_stred: &str = &c.to_string();
        if c == ' ' || c == '\n' || c == '\t' {
            if temp_token.len() > 0 {
                tokens.push(temp_token);
                temp_token = "".to_string();
            }
            continue;
        } else if vec![
            "=", "+", "-", "*", "/", "^", "%", "==", ">", "<", ">=", "<=", "!=", ".", "(", ")",
            "[", "]", "{", "}", ":", ",",
        ]
        .contains(&c_stred)
        {
            if temp_token.len() > 0 {
                tokens.push(temp_token);
                temp_token = "".to_string();
            }
            tokens.push(c.to_string());
            continue;
        }
        temp_token.push(c);
    }
    if temp_token.len() > 0 {
        tokens.push(temp_token);
    }
    // log(&format!("{:?}", tokens));
    let mut result = json!({});
    let mut state_num = 0;
    let mut stack: Vec<HashMap<String, Value>> = vec![];
    let mut first_stage: HashMap<String, Value> = HashMap::new();
    first_stage.insert("body".to_string(), json!([]));
    first_stage.insert("type".to_string(), json!("program".to_string()));
    stack.push(first_stage);
    let mut p: usize = 0;
    let mut current_reg: Value = json!(0);
    let mut counter = 0;
    let mut reserved_identifier = "".to_string();
    loop {
        counter += 1;
        // log(&p.to_string());
        // log(&state_num.to_string());
        // log(&format!("{:?}", stack));
        if counter > 50 {
            break;
        }
        if stack.len() == 0 && p >= tokens.len() {
            break;
        }
        if p >= tokens.len() {
            if state_num == 0 {
                result["type"] = json!("program");
                result["body"] = stack.last().unwrap().get("body").unwrap().clone();
                stack.pop();
                continue;
            } else if state_num == 101 {
                if current_reg
                    .get("type")
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_string()
                    == "functionCall"
                {
                    stack
                        .last_mut()
                        .unwrap()
                        .get_mut("body")
                        .unwrap()
                        .as_array_mut()
                        .unwrap()
                        .push(current_reg.clone());
                    state_num = 0;
                    continue;
                }
                let last_stage = stack.last().unwrap().clone();
                stack.pop();
                let last_type = last_stage["type"].as_str().unwrap().to_string();
                if last_type == "arithmetic" {
                    current_reg = json!({
                        "type": "arithmetic",
                        "data": {
                            "operation": last_stage.get("operation").unwrap().clone(),
                            "operand1": last_stage.get("operand1").unwrap().clone(),
                            "operand2": current_reg
                        }
                    });
                } else if last_type == "definition" {
                    stack.last_mut().unwrap().get_mut("body").unwrap().as_array_mut().unwrap().push(json!({
                        "type": "definition",
                        "data": {
                            "leftSide": {
                                "type": "identifier",
                                "data": {
                                    "name": last_stage.get("leftSide").unwrap().as_str().unwrap().to_string()
                                }
                            },
                            "rightSide": current_reg
                        }
                    }));
                    state_num = 0;
                } else if last_type == "assignment" {
                    stack.last_mut().unwrap().get_mut("body").unwrap().as_array_mut().unwrap().push(json!({
                        "type": "assignment",
                        "data": {
                            "leftSide": {
                                "type": "identifier",
                                "data": {
                                    "name": last_stage.get("leftSide").unwrap().as_str().unwrap().to_string()
                                }
                            },
                            "rightSide": current_reg
                        }
                    }));
                    state_num = 0;
                }
                continue;
            }
        }
        let token = tokens[p].clone();
        if state_num == 0 {
            if token == "def" {
                p += 1;
                state_num = 1;
                stack.push(HashMap::new());
                stack
                    .last_mut()
                    .unwrap()
                    .insert("type".to_string(), json!("definition"));
                continue;
            } else {
                p += 1;
                reserved_identifier = token.clone();
                state_num = 3;
            }
        } else if state_num == 1 {
            p += 1;
            stack
                .last_mut()
                .unwrap()
                .insert("leftSide".to_string(), json!(token.clone()));
            state_num = 2;
            continue;
        } else if state_num == 2 {
            if token == "=" {
                p += 1;
                state_num = 100;
                continue;
            }
        } else if state_num == 3 {
            if token == "=" {
                p += 1;
                stack.push(HashMap::new());
                stack
                    .last_mut()
                    .unwrap()
                    .insert("type".to_string(), json!("assignment"));
                stack
                    .last_mut()
                    .unwrap()
                    .insert("leftSide".to_string(), json!(reserved_identifier.clone()));
                reserved_identifier = "".to_string();
                state_num = 100;
                continue;
            } else if token == "(" {
                p += 1;
                stack.push(HashMap::new());
                stack
                    .last_mut()
                    .unwrap()
                    .insert("type".to_string(), json!("functionCall"));
                stack.last_mut().unwrap().insert(
                    "callee".to_string(),
                    json!({
                        "type": "identifier",
                        "data": {
                            "name": reserved_identifier.clone(),
                        }
                    }),
                );
                stack
                    .last_mut()
                    .unwrap()
                    .insert("args".to_string(), json!(vec![] as Vec<Value>));
                reserved_identifier = "".to_string();
                state_num = 100;
                continue;
            }
        } else if state_num == 100 {
            if token == "{" {
                stack.push(HashMap::new());
                stack
                    .last_mut()
                    .unwrap()
                    .insert("objectData".to_string(), json!({}));
                stack
                    .last_mut()
                    .unwrap()
                    .insert("type".to_string(), json!("objectExpr"));
                p += 1;
                state_num = 102;
                continue;
            }
            if token == "(" {
                stack.push(HashMap::new());
                stack
                    .last_mut()
                    .unwrap()
                    .insert("type".to_string(), json!("paren"));
                p += 1;
                continue;
            }
            let parse_res_i16 = token.parse::<i16>();
            if parse_res_i16.is_ok() {
                current_reg = json!({
                    "type": "i16",
                    "data": { "value": parse_res_i16.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            let parse_res_i32 = token.parse::<i32>();
            if parse_res_i32.is_ok() {
                current_reg = json!({
                    "type": "i32",
                    "data": { "value": parse_res_i32.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            let parse_res_i64 = token.parse::<i64>();
            if parse_res_i64.is_ok() {
                current_reg = json!({
                    "type": "i64",
                    "data": { "value": parse_res_i64.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            let parse_res_f32 = token.parse::<f32>();
            if parse_res_f32.is_ok() {
                current_reg = json!({
                    "type": "f32",
                    "data": { "value": parse_res_f32.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            let parse_res_f64 = token.parse::<f64>();
            if parse_res_f64.is_ok() {
                current_reg = json!({
                    "type": "f64",
                    "data": { "value": parse_res_f64.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            let parse_res_bool = token.parse::<bool>();
            if parse_res_bool.is_ok() {
                current_reg = json!({
                    "type": "bool",
                    "data": { "value": parse_res_bool.unwrap() }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            if token.len() >= 2 && token.starts_with('"') && token.ends_with('"') {
                current_reg = json!({
                    "type": "string",
                    "data": { "value": token[1..token.len()-1] }
                });
                p += 1;
                state_num = 101;
                continue;
            }
            current_reg = json!({
                "type": "identifier",
                "data": { "name": token }
            });
            p += 1;
            state_num = 101;
            continue;
        } else if state_num == 101 {
            if stack.last().unwrap().get("type").unwrap() == "objectExpr"
                && stack.last().unwrap().contains_key("currentKey")
            {
                let key = stack
                    .last_mut()
                    .unwrap()
                    .remove("currentKey")
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_string();
                stack
                    .last_mut()
                    .unwrap()
                    .get_mut("objectData")
                    .unwrap()
                    .as_object_mut()
                    .unwrap()
                    .insert(key, current_reg.clone());
                state_num = 103;
                continue;
            } else if stack
                .last()
                .unwrap()
                .get("type")
                .unwrap()
                .as_str()
                .unwrap()
                .to_string()
                == "arithmetic"
            {
                let last_stage = stack.last().unwrap().clone();
                stack.pop();
                current_reg = json!({
                    "type": "arithmetic",
                    "data": {
                        "operation": last_stage.get("operation").unwrap().clone(),
                        "operand1": last_stage.get("operand1").unwrap().clone(),
                        "operand2": current_reg
                    }
                });
                continue;
            } else if stack
                .last()
                .unwrap()
                .get("type")
                .unwrap()
                .as_str()
                .unwrap()
                .to_string()
                == "definition"
            {
                let last_stage = stack.last().unwrap().clone();
                stack.pop();
                stack.last_mut().unwrap().get_mut("body").unwrap().as_array_mut().unwrap().push(json!({
                        "type": "definition",
                        "data": {
                            "leftSide": {
                                "type": "identifier",
                                "data": {
                                    "name": last_stage.get("leftSide").unwrap().as_str().unwrap().to_string()
                                }
                            },
                            "rightSide": current_reg
                        }
                    }));
                state_num = 0;
                continue;
            } else if stack
                .last()
                .unwrap()
                .get("type")
                .unwrap()
                .as_str()
                .unwrap()
                .to_string()
                == "assignment"
            {
                let last_stage = stack.last().unwrap().clone();
                stack.pop();
                stack.last_mut().unwrap().get_mut("body").unwrap().as_array_mut().unwrap().push(json!({
                        "type": "assignment",
                        "data": {
                            "leftSide": {
                                "type": "identifier",
                                "data": {
                                    "name": last_stage.get("leftSide").unwrap().as_str().unwrap().to_string()
                                }
                            },
                            "rightSide": current_reg
                        }
                    }));
                state_num = 0;
                continue;
            } else {
                if token == "}" {
                    p += 1;
                    if stack
                        .last()
                        .unwrap()
                        .get("type")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                        == "objPropValue"
                    {
                        stack.pop();
                        let last_stage = stack.last_mut().unwrap();
                        let ck = last_stage
                            .get("currentKey")
                            .unwrap()
                            .as_str()
                            .unwrap()
                            .to_string();
                        last_stage
                            .get_mut("objectData")
                            .unwrap()
                            .as_object_mut()
                            .unwrap()
                            .insert(ck, current_reg.clone());
                    }
                    let last_stage = stack.last().unwrap().clone();
                    stack.pop();
                    if last_stage
                        .get("type")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                        == "objectExpr"
                    {
                        current_reg = json!({
                            "type": "object",
                            "data": {
                                "value": last_stage.get("objectData").unwrap().clone(),
                            }
                        });
                    }
                    continue;
                } else if token == ")" {
                    if stack
                        .last()
                        .unwrap()
                        .get("type")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                        == "paren"
                    {
                        p += 1;
                        stack.pop();
                        continue;
                    } else if stack
                        .last()
                        .unwrap()
                        .get("type")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                        == "functionCall"
                    {
                        p += 1;
                        let mut last_sage = stack.pop().unwrap();
                        last_sage
                            .get_mut("args")
                            .unwrap()
                            .as_array_mut()
                            .unwrap()
                            .push(current_reg.clone());
                        current_reg = json!({
                            "type": "functionCall",
                            "data": {
                                "callee": last_sage.get("callee").unwrap().clone(),
                                "args": last_sage.get("args").unwrap().clone(),
                            }
                        });
                        continue;
                    }
                } else if vec!["+", "-", "/", "*", "^", "%"]
                    .iter()
                    .any(|op| op.to_string() == token)
                {
                    stack.push(HashMap::new());
                    stack
                        .last_mut()
                        .unwrap()
                        .insert("type".to_string(), json!("arithmetic"));
                    stack
                        .last_mut()
                        .unwrap()
                        .insert("operand1".to_string(), current_reg.clone());
                    stack
                        .last_mut()
                        .unwrap()
                        .insert("operation".to_string(), json!(token.clone()));
                    p += 1;
                    state_num = 100;
                    continue;
                } else if token == "," {
                    if stack
                        .last()
                        .unwrap()
                        .get("type")
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                        == "functionCall"
                    {
                        p += 1;
                        stack
                            .last_mut()
                            .unwrap()
                            .get_mut("args")
                            .unwrap()
                            .as_array_mut()
                            .unwrap()
                            .push(current_reg.clone());
                        state_num = 100;
                        continue;
                    }
                }
            }
            if !stack.last().unwrap().get("body").is_none() {
                if current_reg
                    .get("type")
                    .unwrap()
                    .as_str()
                    .unwrap()
                    .to_string()
                    == "functionCall"
                {
                    stack
                        .last_mut()
                        .unwrap()
                        .get_mut("body")
                        .unwrap()
                        .as_array_mut()
                        .unwrap()
                        .push(current_reg.clone());
                    current_reg = json!({});
                }
                state_num = 0;
                continue;
            }
        } else if state_num == 102 {
            stack.last_mut().unwrap().insert(
                "currentKey".to_string(),
                json!(token[1..token.len() - 1].to_string()),
            );
            stack.push(HashMap::new());
            stack
                .last_mut()
                .unwrap()
                .insert("type".to_string(), json!("objPropValue".to_string()));
            p += 1;
            state_num = 104;
            continue;
        } else if state_num == 103 {
            if token == "," {
                state_num = 102;
                p += 1;
                continue;
            } else if token == "}" {
                state_num = 101;
                continue;
            }
        } else if state_num == 104 {
            if token == ":" {
                p += 1;
                state_num = 100;
            }
        }
    }
    result
}

#[derive(Clone, Debug)]
struct Path {
    id: i32,
    prefix: String,
    nexts: Vec<Rc<RefCell<Path>>>,
}

pub fn compile_code(p: String) -> Vec<u8> {
    let program = p;

    let temp_prog = program;
    let mut tokens: Vec<String> = vec![];
    let mut temp_token = "".to_string();
    let mut inside_string = false;
    for c in temp_prog.chars() {
        if c == '"' {
            if inside_string {
                inside_string = false;
                temp_token.push(c);
                tokens.push(temp_token);
                temp_token = "".to_string();
            } else {
                inside_string = true;
                temp_token.push(c);
            }
            continue;
        }
        if inside_string {
            temp_token.push(c);
            continue;
        }
        let c_stred: &str = &c.to_string();
        if c == ' ' || c == '\n' || c == '\t' {
            if temp_token.len() > 0 {
                tokens.push(temp_token);
                temp_token = "".to_string();
            }
            continue;
        } else if vec![
            "=", "+", "-", "*", "/", "^", "%", "==", ">", "<", ">=", "<=", "!=", ".", "(", ")",
            "[", "]", "{", "}", ":", ",",
        ]
        .contains(&c_stred)
        {
            if temp_token.len() > 0 {
                tokens.push(temp_token);
                temp_token = "".to_string();
            }
            tokens.push(c.to_string());
            continue;
        }
        temp_token.push(c);
    }
    if temp_token.len() > 0 {
        tokens.push(temp_token);
    }
    log(&format!("{:?}", tokens));

    let mut stack: Vec<(String, Path, i32, usize, i32)> = vec![];

    let start_path = Rc::new(RefCell::new(Path {
        id: 1,
        prefix: "start".to_string(),
        nexts: vec![],
    }));
    let end_path = Rc::new(RefCell::new(Path {
        id: 2,
        prefix: "end".to_string(),
        nexts: vec![],
    }));
    {
        start_path.borrow_mut().nexts.push(end_path.clone());
    }
    let expr_path = Rc::new(RefCell::new(Path {
        id: 3,
        prefix: "".to_string(),
        nexts: vec![],
    }));
    {
        start_path.borrow_mut().nexts.push(expr_path.clone());
    }
    let expr_2_path = Rc::new(RefCell::new(Path {
        id: 4,
        prefix: "string".to_string(),
        nexts: vec![],
    }));
    {
        expr_path.borrow_mut().nexts.push(expr_2_path.clone());
    }
    {
        expr_path.borrow_mut().nexts.push(end_path.clone());
    }
    let expr_3_path = Rc::new(RefCell::new(Path {
        id: 5,
        prefix: "+".to_string(),
        nexts: vec![],
    }));
    {
        expr_2_path.borrow_mut().nexts.push(expr_3_path.clone());
    }
    let expr_4_path = Rc::new(RefCell::new(Path {
        id: 6,
        prefix: "string".to_string(),
        nexts: vec![],
    }));
    {
        expr_3_path.borrow_mut().nexts.push(expr_4_path.clone());
    }
    {
        expr_4_path.borrow_mut().nexts.push(expr_3_path.clone());
    }
    {
        expr_4_path.borrow_mut().nexts.push(end_path.clone());
    }

    let function_call_path = Rc::new(RefCell::new(Path {
        id: 7,
        prefix: "id".to_string(),
        nexts: vec![],
    }));
    {
        start_path
            .borrow_mut()
            .nexts
            .push(function_call_path.clone());
    }
    let function_call_2_path = Rc::new(RefCell::new(Path {
        id: 8,
        prefix: "(".to_string(),
        nexts: vec![],
    }));
    {
        function_call_path
            .borrow_mut()
            .nexts
            .push(function_call_2_path.clone());
    }
    {
        function_call_2_path
            .borrow_mut()
            .nexts
            .push(expr_path.clone());
    }
    let function_call_4_path = Rc::new(RefCell::new(Path {
        id: 10,
        prefix: ")".to_string(),
        nexts: vec![],
    }));
    {
        expr_4_path
            .borrow_mut()
            .nexts
            .push(function_call_4_path.clone());
        expr_2_path
            .borrow_mut()
            .nexts
            .push(function_call_4_path.clone());
        function_call_4_path
            .borrow_mut()
            .nexts
            .push(end_path.clone());
    }

    let genesis_path = Rc::new(RefCell::new(Path {
        id: 11,
        prefix: "".to_string(),
        nexts: vec![start_path.clone()],
    }));

    stack.push(("".to_string(), genesis_path.borrow_mut().clone(), 0, 0, 0));

    let mut keyword_map: HashMap<String, bool> = HashMap::new();
    keyword_map.insert("start".to_string(), true);
    keyword_map.insert("end".to_string(), true);
    keyword_map.insert("(".to_string(), true);
    keyword_map.insert(")".to_string(), true);
    keyword_map.insert("+".to_string(), true);

    loop {
        let mut found = false;
        let paths = stack.last().unwrap().1.nexts.clone();
        let checkpoint = stack.last().unwrap().2;
        let mut counter = 0;
        let curr_token = tokens[stack.last().unwrap().4 as usize].clone();
        for pa in paths.iter() {
            if counter < checkpoint {
                counter += 1;
                continue;
            }
            let path = pa.borrow().clone();
            if path.prefix == "" {
                let mut prev_exists = false;
                for hist in stack.clone().into_iter().rev() {
                    if hist.1.id == path.id && hist.3 == stack.len() {
                        prev_exists = true;
                        break;
                    }
                }
                if prev_exists {
                    counter += 1;
                    continue;
                }
                println!("trying non-prefix {}", curr_token);
                counter += 1;
                stack.last_mut().unwrap().2 = counter;
                found = true;
                stack.push((
                    curr_token,
                    path.clone(),
                    0,
                    stack.len(),
                    stack.last().unwrap().4,
                ));
                break;
            } else if !keyword_map.contains_key(&curr_token) {
                if curr_token.starts_with("\"")
                    && curr_token.ends_with("\"")
                    && path.prefix == "string"
                {
                    println!("matched string {}", curr_token);
                    counter += 1;
                    stack.last_mut().unwrap().2 = counter;
                    found = true;
                    stack.push((
                        curr_token,
                        path.clone(),
                        0,
                        stack.len(),
                        stack.last().unwrap().4 + 1,
                    ));
                    break;
                } else if path.prefix == "id" {
                    println!("matched identifier {}", curr_token);
                    counter += 1;
                    stack.last_mut().unwrap().2 = counter;
                    found = true;
                    stack.push((
                        curr_token,
                        path.clone(),
                        0,
                        stack.len(),
                        stack.last().unwrap().4 + 1,
                    ));
                    break;
                }
            } else if path.prefix == curr_token {
                println!("matched {}", curr_token);
                counter += 1;
                stack.last_mut().unwrap().2 = counter;
                found = true;
                stack.push((
                    curr_token,
                    path.clone(),
                    0,
                    stack.len(),
                    stack.last().unwrap().4 + 1,
                ));
                break;
            }
            counter += 1;
        }
        if stack.last().unwrap().0 == "end" {
            println!("Finished !");
            break;
        }
        if !found {
            if stack.len() > 0 {
                stack.pop();
            }
        }
        if stack.len() == 0 {
            break;
        }
    }

    vec![]
}
