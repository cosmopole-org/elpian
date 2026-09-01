//! Retained scene diffing: turn two frames into a minimal patch.
//!
//! Re-sending the whole `dart:ui` scene tree every frame is wasteful; the elpis
//! protocol (and Flutter's own retained render tree) instead computes the
//! difference between the previous and current frame and ships only that. This
//! module diffs two scene-tree JSON values into a compact patch and can re-apply
//! it, so the host transmits only what changed and preserves untouched subtrees.

use serde_json::{json, Value};

/// A single patch: set the value at `path` (when `value` is `Some`) or remove
/// the element at `path` (when `value` is `None`). `path` segments are JSON
/// strings (object keys) or integers (array indices).
#[derive(Debug, Clone, PartialEq)]
pub struct Patch {
    pub path: Vec<Value>,
    pub value: Option<Value>,
}

impl Patch {
    pub fn to_json(&self) -> Value {
        match &self.value {
            Some(v) => json!({ "path": self.path, "set": v }),
            None => json!({ "path": self.path, "remove": true }),
        }
    }
}

/// Diff `old` into `new`, producing the minimal patch list. Applying the result
/// to a clone of `old` reproduces `new`.
pub fn diff(old: &Value, new: &Value) -> Vec<Patch> {
    let mut out = Vec::new();
    diff_into(old, new, &mut Vec::new(), &mut out);
    out
}

fn diff_into(old: &Value, new: &Value, path: &mut Vec<Value>, out: &mut Vec<Patch>) {
    if old == new {
        return;
    }
    match (old, new) {
        (Value::Object(a), Value::Object(b)) => {
            // Removed keys.
            for k in a.keys() {
                if !b.contains_key(k) {
                    let mut p = path.clone();
                    p.push(Value::from(k.clone()));
                    out.push(Patch { path: p, value: None });
                }
            }
            // Added / changed keys.
            for (k, bv) in b {
                path.push(Value::from(k.clone()));
                match a.get(k) {
                    Some(av) => diff_into(av, bv, path, out),
                    None => out.push(Patch { path: path.clone(), value: Some(bv.clone()) }),
                }
                path.pop();
            }
        }
        (Value::Array(a), Value::Array(b)) => {
            let common = a.len().min(b.len());
            for i in 0..common {
                path.push(Value::from(i));
                diff_into(&a[i], &b[i], path, out);
                path.pop();
            }
            // Appended elements.
            for i in common..b.len() {
                let mut p = path.clone();
                p.push(Value::from(i));
                out.push(Patch { path: p, value: Some(b[i].clone()) });
            }
            // Removed tail (highest index first so earlier indices stay valid).
            for i in (common..a.len()).rev() {
                let mut p = path.clone();
                p.push(Value::from(i));
                out.push(Patch { path: p, value: None });
            }
        }
        _ => {
            out.push(Patch { path: path.clone(), value: Some(new.clone()) });
        }
    }
}

/// Apply a patch list to `base` in place.
pub fn apply(base: &mut Value, patches: &[Patch]) {
    for patch in patches {
        apply_one(base, &patch.path, patch.value.as_ref());
    }
}

fn apply_one(base: &mut Value, path: &[Value], value: Option<&Value>) {
    if path.is_empty() {
        if let Some(v) = value {
            *base = v.clone();
        }
        return;
    }
    let (seg, rest) = path.split_first().unwrap();
    if rest.is_empty() {
        match seg {
            Value::String(k) => {
                if let Some(obj) = base.as_object_mut() {
                    match value {
                        Some(v) => {
                            obj.insert(k.clone(), v.clone());
                        }
                        None => {
                            obj.remove(k);
                        }
                    }
                }
            }
            Value::Number(n) => {
                if let (Some(arr), Some(i)) = (base.as_array_mut(), n.as_u64()) {
                    let i = i as usize;
                    match value {
                        Some(v) => {
                            if i < arr.len() {
                                arr[i] = v.clone();
                            } else if i == arr.len() {
                                arr.push(v.clone());
                            }
                        }
                        None => {
                            if i < arr.len() {
                                arr.remove(i);
                            }
                        }
                    }
                }
            }
            _ => {}
        }
        return;
    }
    // Descend.
    let child = match seg {
        Value::String(k) => base.as_object_mut().and_then(|o| o.get_mut(k)),
        Value::Number(n) => base
            .as_array_mut()
            .and_then(|a| n.as_u64().and_then(move |i| a.get_mut(i as usize))),
        _ => None,
    };
    if let Some(c) = child {
        apply_one(c, rest, value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_field_change_is_one_patch() {
        let old = json!({ "root": { "ops": [ { "op": "drawRect", "color": 1 } ] } });
        let new = json!({ "root": { "ops": [ { "op": "drawRect", "color": 2 } ] } });
        let patches = diff(&old, &new);
        assert_eq!(patches.len(), 1);
        assert_eq!(patches[0].value, Some(json!(2)));
    }

    #[test]
    fn diff_then_apply_roundtrips() {
        let old = json!({ "a": [1, 2, 3], "b": { "x": 1 }, "gone": true });
        let new = json!({ "a": [1, 9, 3, 4], "b": { "x": 1, "y": 2 } });
        let patches = diff(&old, &new);
        let mut base = old.clone();
        apply(&mut base, &patches);
        assert_eq!(base, new);
    }

    #[test]
    fn identical_scenes_produce_no_patches() {
        let s = json!({ "root": { "children": [1, 2, 3] } });
        assert!(diff(&s, &s).is_empty());
    }

    #[test]
    fn array_growth_and_shrink_roundtrip() {
        let old = json!([1, 2, 3, 4]);
        let new = json!([1, 2]);
        let mut base = old.clone();
        apply(&mut base, &diff(&old, &new));
        assert_eq!(base, new);

        let old2 = json!([1]);
        let new2 = json!([1, 2, 3]);
        let mut base2 = old2.clone();
        apply(&mut base2, &diff(&old2, &new2));
        assert_eq!(base2, new2);
    }
}
