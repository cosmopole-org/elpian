//! Generating the Dart host-API catalog from the VM's own list.
//!
//! `api::all_host_apis()` is the single source of truth for which names the VM
//! treats as native `askHost` targets, and `Capability::for_api` is the single
//! source of truth for which gate each one sits behind. The Dart side needs
//! both: the catalog tells `HostHandler` how to dispatch, and the capability
//! tells it what to check before it does.
//!
//! Keeping a hand-written copy on the Dart side had already gone wrong — the
//! two lists disagreed about `canvas.createImageData`, which the Dart catalog
//! advertised and the VM did not, so a guest calling it was never treated as a
//! native host call at all.
//!
//! The rendering lives here rather than in the generator binary so the
//! staleness test can call exactly what the binary writes:
//!
//! ```text
//! cd rust && cargo run --bin gen-host-api-catalog -- \\
//!     ../flutter/lib/src/vm/host_api_catalog.dart
//! ```

use std::collections::BTreeMap;

use super::all_host_apis;
use crate::sdk::capabilities::Capability;

/// The Dart set name each capability's APIs are collected into.
///
/// `HostHandler` dispatches by group, so the grouping is derived from the
/// capability rather than invented separately — one classification drives both
/// the gate and the dispatch.
fn dart_set_for(cap: Capability) -> &'static str {
    match cap {
        Capability::Dom => "domApiNames",
        Capability::Canvas => "canvasApiNames",
        Capability::Timers => "timerApiNames",
        Capability::Render | Capability::Environment | Capability::Logging | Capability::Other => {
            "coreApiNames"
        }
        Capability::Network => "netApiNames",
        Capability::Storage => "fsApiNames",
        Capability::Gpu => "gpuApiNames",
        Capability::Clock => "timeApiNames",
        Capability::Randomness => "randomApiNames",
        Capability::Tasks => "taskApiNames",
        Capability::HostMessaging => "hostMessagingApiNames",
        Capability::Surface => "surfaceApiNames",
        Capability::ServerCall => "serverApiNames",
        Capability::State => "stateApiNames",
        Capability::VmManage | Capability::ModuleImport => "vmApiNames",
    }
}

/// The order the sets appear in the generated file, and the comment above each.
const SET_ORDER: &[(&str, &str)] = &[
    (
        "coreApiNames",
        "Rendering, environment and diagnostics: the unprefixed names the\n  /// Flutter engine has always spoken.",
    ),
    ("timerApiNames", "Deferred work on the host clock."),
    ("domApiNames", "The host document tree."),
    ("canvasApiNames", "The 2D drawing surface."),
    ("netApiNames", "Outbound and inbound networking."),
    ("fsApiNames", "The fabricated filesystem."),
    ("gpuApiNames", "GPU command submission and resources."),
    ("timeApiNames", "Wall-clock and monotonic time."),
    ("randomApiNames", "Non-deterministic randomness."),
    (
        "taskApiNames",
        "Guest compute offloaded onto the host's worker pool.",
    ),
    (
        "hostMessagingApiNames",
        "The embedder-defined message pipe.",
    ),
    (
        "surfaceApiNames",
        "The host's drawing surface — the op seams a guest submits UI\n  /// through, whichever host is underneath.",
    ),
    (
        "serverApiNames",
        "A mini app calling its own server functions. Separate from the\n  /// network: an app in a closed posture holds no network at all and\n  /// still reaches its own backend through these.",
    ),
    (
        "stateApiNames",
        "Durable per-app key/value state, and the secrets a server\n  /// function may read.",
    ),
    (
        "vmApiNames",
        "Module import and management of other VM instances.",
    ),
];

fn render() -> String {
    let mut by_set: BTreeMap<&'static str, Vec<String>> = BTreeMap::new();
    let mut capability_of: Vec<(String, &'static str)> = Vec::new();

    for name in all_host_apis() {
        let cap = Capability::for_api(&name);
        by_set
            .entry(dart_set_for(cap))
            .or_default()
            .push(name.clone());
        capability_of.push((name, cap.as_str()));
    }
    capability_of.sort();

    let mut out = String::new();
    out.push_str(
        "// GENERATED FILE — DO NOT EDIT BY HAND.\n\
         //\n\
         // Produced from the VM's own host-API list and capability mapping by:\n\
         //\n\
         //     cd rust && cargo run --bin gen-host-api-catalog -- \\\n\
         //         ../flutter/lib/src/vm/host_api_catalog.dart\n\
         //\n\
         // The Rust sources are `api::all_host_apis()` (which names the VM treats\n\
         // as native askHost targets) and `Capability::for_api` (which gate each\n\
         // sits behind). Editing this file by hand reintroduces the drift it was\n\
         // written to prevent — `cargo test -p elpian-vm --test host_api_catalog`\n\
         // fails when it is stale.\n\n",
    );

    out.push_str(
        "/// Every host API the Elpian VM will forward to the Dart side, grouped the\n\
         /// way [HostHandler] dispatches them, plus the capability that gates each.\n\
         class VmHostApiCatalog {\n",
    );

    let mut first = true;
    for (set_name, comment) in SET_ORDER {
        let Some(names) = by_set.get(set_name) else {
            continue;
        };
        if !first {
            out.push('\n');
        }
        first = false;
        out.push_str(&format!("  /// {comment}\n"));
        out.push_str(&format!("  static const {set_name} = <String>{{\n"));
        for n in names {
            out.push_str(&format!("    '{n}',\n"));
        }
        out.push_str("  };\n");
    }

    out.push_str("\n  /// The complete advertised surface.\n");
    out.push_str("  static const allHostApiNames = <String>{\n");
    for (set_name, _) in SET_ORDER {
        if by_set.contains_key(set_name) {
            out.push_str(&format!("    ...{set_name},\n"));
        }
    }
    out.push_str("  };\n");

    out.push_str(
        "\n  /// The capability that gates each API, keyed by name. Mirrors\n\
         \x20 /// `Capability::for_api` in rust/src/sdk/capabilities.rs, so the Dart\n\
         \x20 /// host can refuse a call for the same reason the VM would.\n",
    );
    out.push_str("  static const capabilityOf = <String, String>{\n");
    for (name, cap) in &capability_of {
        out.push_str(&format!("    '{name}': '{cap}',\n"));
    }
    out.push_str("  };\n");

    out.push_str(
        "\n  /// The capability gating [apiName], or `'other'` for a name the VM does\n\
         \x20 /// not advertise — the fail-safe gate, never a pass.\n\
         \x20 static String capabilityFor(String apiName) =>\n\
         \x20     capabilityOf[apiName] ?? 'other';\n",
    );

    out.push_str("}\n");
    out
}

/// The Dart source of the host-API catalog, exactly as the
/// `gen-host-api-catalog` binary writes it.
pub fn dart_catalog() -> String {
    render()
}

/// The TypeScript twin of [dart_catalog] for the native hosts
/// (`native/web/src/vm/host-api-catalog.ts`): the same sets, the same
/// capability map, so the native `HostHandler` dispatches and gates exactly as
/// the Flutter one does.
pub fn ts_catalog() -> String {
    let mut by_set: BTreeMap<&'static str, Vec<String>> = BTreeMap::new();
    let mut capability_of: Vec<(String, &'static str)> = Vec::new();
    for name in all_host_apis() {
        let cap = Capability::for_api(&name);
        by_set
            .entry(dart_set_for(cap))
            .or_default()
            .push(name.clone());
        capability_of.push((name, cap.as_str()));
    }
    capability_of.sort();

    let mut out = String::new();
    out.push_str(
        "// GENERATED FILE — DO NOT EDIT BY HAND.\n\
         //\n\
         // Produced from the VM's own host-API list and capability mapping by:\n\
         //\n\
         //     cd rust && cargo run --bin gen-host-api-catalog -- \\\n\
         //         ../native/web/src/vm/host-api-catalog.ts\n\
         //\n\
         // The TypeScript twin of flutter/lib/src/vm/host_api_catalog.dart;\n\
         // `cargo test -p elpian-vm --test host_api_catalog` fails when it is stale.\n\n",
    );
    for (set_name, comment) in SET_ORDER {
        let Some(names) = by_set.get(set_name) else {
            continue;
        };
        let comment = comment.replace("\n  /// ", "\n * ");
        out.push_str(&format!("/** {comment} */\n"));
        out.push_str(&format!(
            "export const {set_name}: ReadonlySet<string> = new Set([\n"
        ));
        for n in names {
            out.push_str(&format!("  '{n}',\n"));
        }
        out.push_str("]);\n\n");
    }
    out.push_str("/** The complete advertised surface. */\n");
    out.push_str("export const allHostApiNames: ReadonlySet<string> = new Set([\n");
    for (set_name, _) in SET_ORDER {
        if by_set.contains_key(set_name) {
            out.push_str(&format!("  ...{set_name},\n"));
        }
    }
    out.push_str("]);\n\n");
    out.push_str(
        "/** The capability that gates each API (`Capability::for_api`). */\n\
         export const capabilityOf: Readonly<Record<string, string>> = {\n",
    );
    for (name, cap) in &capability_of {
        out.push_str(&format!("  '{name}': '{cap}',\n"));
    }
    out.push_str("};\n\n");
    out.push_str(
        "/** The capability gating [apiName], or `'other'` for a name the VM does not\n\
         \x20* advertise — the fail-safe gate, never a pass. */\n\
         export function capabilityFor(apiName: string): string {\n\
         \x20 return Object.prototype.hasOwnProperty.call(capabilityOf, apiName) ? capabilityOf[apiName] : 'other';\n\
         }\n",
    );
    out
}

/// Host API names grouped by the set that declares them.
type ApiSets = BTreeMap<&'static str, Vec<String>>;
/// `(api name, capability)` pairs, sorted by name.
type CapabilityMap = Vec<(String, &'static str)>;

/// The sets and the sorted capability map every catalog renders from.
fn grouped() -> (ApiSets, CapabilityMap) {
    let mut by_set: BTreeMap<&'static str, Vec<String>> = BTreeMap::new();
    let mut capability_of: Vec<(String, &'static str)> = Vec::new();
    for name in all_host_apis() {
        let cap = Capability::for_api(&name);
        by_set
            .entry(dart_set_for(cap))
            .or_default()
            .push(name.clone());
        capability_of.push((name, cap.as_str()));
    }
    capability_of.sort();
    (by_set, capability_of)
}

/// A Kotlin or Swift string literal for an API or capability name.
fn quoted(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '$' => out.push_str("\\$"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

/// The Kotlin twin of [ts_catalog] for the Android core
/// (`native/android/elpian-core/src/main/kotlin/dev/elpian/core/vm/HostApiCatalog.kt`):
/// the same sets, the same capability map and the same `capabilityFor`, as
/// top-level declarations in package `dev.elpian.core.vm` so the port reads
/// like the TypeScript module it mirrors.
pub fn kotlin_catalog() -> String {
    let (by_set, capability_of) = grouped();
    let mut out = String::new();
    out.push_str(
        "// GENERATED FILE — DO NOT EDIT BY HAND.\n\
         //\n\
         // Produced from the VM's own host-API list and capability mapping by:\n\
         //\n\
         //     cd rust && cargo run --bin gen-host-api-catalog -- \\\n\
         //         ../native/android/elpian-core/src/main/kotlin/dev/elpian/core/vm/HostApiCatalog.kt\n\
         //\n\
         // The Kotlin twin of native/web/src/vm/host-api-catalog.ts;\n\
         // `cargo test -p elpian-vm --test host_api_catalog` fails when it is stale.\n\n\
         package dev.elpian.core.vm\n\n",
    );
    for (set_name, comment) in SET_ORDER {
        let Some(names) = by_set.get(set_name) else {
            continue;
        };
        let comment = comment.replace("\n  /// ", "\n * ");
        out.push_str(&format!("/** {comment} */\n"));
        out.push_str(&format!("val {set_name}: Set<String> = linkedSetOf(\n"));
        for n in names {
            out.push_str(&format!("  {},\n", quoted(n)));
        }
        out.push_str(")\n\n");
    }
    out.push_str("/** The complete advertised surface. */\n");
    out.push_str("val allHostApiNames: Set<String> = LinkedHashSet<String>().apply {\n");
    for (set_name, _) in SET_ORDER {
        if by_set.contains_key(set_name) {
            out.push_str(&format!("  addAll({set_name})\n"));
        }
    }
    out.push_str("}\n\n");
    out.push_str(
        "/** The capability that gates each API (`Capability::for_api`). */\n\
         val capabilityOf: Map<String, String> = linkedMapOf(\n",
    );
    for (name, cap) in &capability_of {
        out.push_str(&format!("  {} to {},\n", quoted(name), quoted(cap)));
    }
    out.push_str(")\n\n");
    out.push_str(
        "/** The capability gating [apiName], or `\"other\"` for a name the VM does not\n\
         \x20* advertise — the fail-safe gate, never a pass. */\n\
         fun capabilityFor(apiName: String): String = capabilityOf[apiName] ?: \"other\"\n",
    );
    out
}

/// The Swift twin of [ts_catalog] for the iOS core
/// (`native/ios/Sources/ElpianCore/VM/HostApiCatalog.swift`): the same sets,
/// the same capability map and the same `capabilityFor`, namespaced in a
/// caseless `HostApiCatalog` enum.
pub fn swift_catalog() -> String {
    let (by_set, capability_of) = grouped();
    let mut out = String::new();
    out.push_str(
        "// GENERATED FILE — DO NOT EDIT BY HAND.\n\
         //\n\
         // Produced from the VM's own host-API list and capability mapping by:\n\
         //\n\
         //     cd rust && cargo run --bin gen-host-api-catalog -- \\\n\
         //         ../native/ios/Sources/ElpianCore/VM/HostApiCatalog.swift\n\
         //\n\
         // The Swift twin of native/web/src/vm/host-api-catalog.ts;\n\
         // `cargo test -p elpian-vm --test host_api_catalog` fails when it is stale.\n\n\
         /// Every host API the Elpian VM forwards to the host, grouped the way the\n\
         /// host handler dispatches them, plus the capability that gates each.\n\
         public enum HostApiCatalog {\n",
    );
    let mut first = true;
    for (set_name, comment) in SET_ORDER {
        let Some(names) = by_set.get(set_name) else {
            continue;
        };
        if !first {
            out.push('\n');
        }
        first = false;
        let comment = comment.replace("\n  /// ", "\n    /// ");
        out.push_str(&format!("    /// {comment}\n"));
        out.push_str(&format!(
            "    public static let {set_name}: Set<String> = [\n"
        ));
        for n in names {
            out.push_str(&format!("        {},\n", quoted(n)));
        }
        out.push_str("    ]\n");
    }
    out.push_str("\n    /// The complete advertised surface.\n");
    out.push_str("    public static let allHostApiNames: Set<String> = Set<String>()\n");
    for (set_name, _) in SET_ORDER {
        if by_set.contains_key(set_name) {
            out.push_str(&format!("        .union({set_name})\n"));
        }
    }
    out.push_str(
        "\n    /// The capability that gates each API (`Capability::for_api`).\n\
         \x20   public static let capabilityOf: [String: String] = [\n",
    );
    for (name, cap) in &capability_of {
        out.push_str(&format!("        {}: {},\n", quoted(name), quoted(cap)));
    }
    out.push_str("    ]\n");
    out.push_str(
        "\n    /// The capability gating `apiName`, or `\"other\"` for a name the VM does\n\
         \x20   /// not advertise — the fail-safe gate, never a pass.\n\
         \x20   public static func capabilityFor(_ apiName: String) -> String {\n\
         \x20       capabilityOf[apiName] ?? \"other\"\n\
         \x20   }\n\
         }\n",
    );
    out
}
