//! The catalog of **core-type members** — the members callable on a built-in
//! value (`List`, `String`, `num`, `Map`) — named with the VM's single, universal
//! stdlib vocabulary.
//!
//! This module answers one question for the executor: *does `receiver.name`
//! name a core-type member, and if so how is it delivered?* The `name` it is
//! asked about is already a **universal** Elpian name (`push`, `upper`, `has`,
//! `reversed`, …): a source front-end (`dart2elpian` / `js2elpian`) has mapped
//! its own spelling (`add`, `toUpperCase`, `containsKey`, …) onto the universal
//! name at *compile time*. The VM therefore carries no Dart- or JS-specific
//! method names and does no name translation at runtime.
//!
//! Delivery is direct: a resolved member is realised by the *same*
//! [`crate::sdk::stdlib::invoke`] the bare-function surface uses, called with the
//! receiver as the first argument. There is no separate per-type implementation
//! and nothing is proxied — the member name *is* the builtin name.
//!
//! Organised object-orientedly (one submodule per core type) so adding a member
//! is a one-line change in exactly one place.

/// A core built-in type, identified from a VM value's type tag.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CoreType {
    List,
    String,
    Num,
    Map,
}

impl CoreType {
    /// The core type of a value tag, if it is a built-in type with members.
    /// Tags: `9` = List, `7` = String, `1..=5` = numeric (int/double variants),
    /// `8` = plain object / Map.
    pub fn of_tag(tag: i64) -> Option<CoreType> {
        match tag {
            9 => Some(CoreType::List),
            7 => Some(CoreType::String),
            1..=5 => Some(CoreType::Num),
            8 => Some(CoreType::Map),
            _ => None,
        }
    }

    /// The prefix of this type's guest prelude helpers (`__List_map`, …).
    pub fn prelude_prefix(self) -> &'static str {
        match self {
            CoreType::List => "List",
            CoreType::String => "String",
            CoreType::Num => "Num",
            CoreType::Map => "Map",
        }
    }
}

/// How a resolved member is delivered to the executor.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Dispatch {
    /// A getter (read, no call): evaluate now via `stdlib::invoke(name, &[recv])`.
    Getter,
    /// A method: hand back a bound native (VM type-tag 253) that, when called,
    /// runs `stdlib::invoke(name, &[receiver, ..args])`.
    Method,
    /// A higher-order method realised as the guest prelude fn `__<Type>_<name>`,
    /// bound to the receiver so its closure argument runs as guest bytecode.
    Prelude,
}

/// A resolved member: how it dispatches, the universal stdlib name that
/// implements it (`"push"`, `"upper"`, …), and — for a [`Dispatch::Prelude`]
/// member — the guest prelude function that realises it (`"__List_map"`).
pub struct Member {
    pub dispatch: Dispatch,
    /// The universal builtin name; used directly by `stdlib::invoke`.
    pub name: String,
    /// The prelude function name (`__<Type>_<name>`), meaningful only when
    /// `dispatch == Prelude`.
    pub prelude_fn: String,
}

/// Resolve `name` (a universal Elpian name) as a member of `ty`, or `None`.
pub fn resolve(ty: CoreType, name: &str) -> Option<Member> {
    let dispatch = match ty {
        CoreType::List => list::dispatch(name),
        CoreType::String => string::dispatch(name),
        CoreType::Num => num::dispatch(name),
        CoreType::Map => map::dispatch(name),
    }?;
    Some(Member {
        dispatch,
        name: name.to_string(),
        prelude_fn: format!("__{}_{}", ty.prelude_prefix(), name),
    })
}

/// Whether `ty` has a member named `name` — the existence check the executor
/// asks before deciding how to read `receiver.name`.
pub fn has(ty: CoreType, name: &str) -> bool {
    resolve(ty, name).is_some()
}

// --- per-type member catalogs (object-oriented grouping) --------------------

mod list {
    use super::Dispatch;
    /// Members of `List`, named universally. Getters read eagerly; the
    /// higher-order closure methods run as guest prelude functions; the rest are
    /// bound native methods delegating straight to the like-named builtin.
    pub fn dispatch(name: &str) -> Option<Dispatch> {
        Some(match name {
            "length" | "isEmpty" | "isNotEmpty" | "first" | "last" | "reversed" => Dispatch::Getter,
            // Higher-order members (callback-taking) run as guest prelude
            // functions so their callbacks execute as guest bytecode. `sort` is
            // here because it takes an optional comparator.
            "map" | "where" | "forEach" | "fold" | "any" | "every" | "reduce" | "reduceRight"
            | "find" | "findIndex" | "findLast" | "findLastIndex" | "flatMap" | "sort"
            | "takeWhile" | "skipWhile" | "removeWhere" => Dispatch::Prelude,
            "push" | "contains" | "indexOf" | "lastIndexOf" | "pop" | "shift" | "unshift"
            | "slice" | "splice" | "concat" | "flatten" | "at" | "pushAll" | "remove"
            | "removeAt" | "insert" | "clear" | "reverse" | "setAt" | "toString" | "join"
            | "take" | "skip" | "toSet" | "shuffle" => Dispatch::Method,
            _ => return None,
        })
    }
}

mod string {
    use super::Dispatch;
    /// Members of `String` — size getters plus bound native methods over the
    /// receiver string.
    pub fn dispatch(name: &str) -> Option<Dispatch> {
        Some(match name {
            "length" | "isEmpty" | "isNotEmpty" | "codeUnits" => Dispatch::Getter,
            "substring" | "contains" | "indexOf" | "lastIndexOf" | "upper" | "lower" | "trim"
            | "trimStart" | "trimEnd" | "split" | "startsWith" | "endsWith" | "replace"
            | "replaceFirst" | "codeUnitAt" | "padStart" | "padEnd" | "charAt" | "repeat"
            | "ord" | "at" | "slice" | "concat" | "compareTo" | "toString" => Dispatch::Method,
            _ => return None,
        })
    }
}

mod num {
    use super::Dispatch;
    /// Members of `num`/`int`/`double`.
    pub fn dispatch(name: &str) -> Option<Dispatch> {
        Some(match name {
            "isNaN" | "isNegative" | "isFinite" | "isEven" | "isOdd" | "sign" => Dispatch::Getter,
            "int" | "toDouble" | "abs" | "floor" | "ceil" | "round" | "trunc" | "toString"
            | "toStringAsFixed" | "toRadix" | "clamp" | "remainder" | "compareTo" => {
                Dispatch::Method
            }
            _ => return None,
        })
    }
}

mod map {
    use super::Dispatch;
    /// Members of a plain `Map` (objects without a `__class` tag).
    pub fn dispatch(name: &str) -> Option<Dispatch> {
        Some(match name {
            "length" | "keys" | "values" | "isEmpty" | "isNotEmpty" => Dispatch::Getter,
            // Callback-taking members run as per-front-end prelude functions
            // (`__Map_forEach`, `__Map_removeWhere`).
            "forEach" | "removeWhere" => Dispatch::Prelude,
            "has" | "hasValue" | "get" | "remove" | "putIfAbsent" | "pushAll" | "merge"
            | "entries" | "toString" => Dispatch::Method,
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_by_type_and_kind() {
        assert_eq!(resolve(CoreType::List, "push").unwrap().dispatch, Dispatch::Method);
        assert_eq!(resolve(CoreType::List, "first").unwrap().dispatch, Dispatch::Getter);
        assert_eq!(resolve(CoreType::List, "map").unwrap().dispatch, Dispatch::Prelude);
        assert_eq!(resolve(CoreType::String, "upper").unwrap().dispatch, Dispatch::Method);
        // Regression: charAt/repeat/ord are stdlib string builtins that were
        // missing from this catalog — a member read then produced a
        // non-callable and the call panicked the whole VM (web: abort()).
        assert_eq!(resolve(CoreType::String, "charAt").unwrap().dispatch, Dispatch::Method);
        assert_eq!(resolve(CoreType::String, "repeat").unwrap().dispatch, Dispatch::Method);
        assert_eq!(resolve(CoreType::String, "ord").unwrap().dispatch, Dispatch::Method);
        assert_eq!(resolve(CoreType::Num, "isNaN").unwrap().dispatch, Dispatch::Getter);
        assert_eq!(resolve(CoreType::Map, "keys").unwrap().dispatch, Dispatch::Getter);
        // The resolved name is the universal builtin name, used directly by
        // `stdlib::invoke` — no `Type.method` qualifier.
        assert_eq!(resolve(CoreType::List, "push").unwrap().name, "push");
        assert_eq!(resolve(CoreType::List, "map").unwrap().prelude_fn, "__List_map");
    }

    #[test]
    fn unknown_members_are_none() {
        assert!(resolve(CoreType::List, "nope").is_none());
        assert!(!has(CoreType::String, "push")); // push is a List member, not String
        assert!(CoreType::of_tag(99).is_none());
        assert_eq!(CoreType::of_tag(9), Some(CoreType::List));
    }
}
