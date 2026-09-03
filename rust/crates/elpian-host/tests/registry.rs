//! The registry: content-addressed blobs, versions, atomic index writes.

use std::collections::BTreeMap;

use elpian_host::registry::{compare_versions, now_millis, RegistryStore, VersionRecord};
use elpian_host::RegistryError;
use serde_json::json;

fn temp_dir(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("elpian-registry-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn version(v: &str, functions: &[(&str, &str)]) -> VersionRecord {
    VersionRecord {
        version: v.to_string(),
        client: None,
        functions: functions
            .iter()
            .map(|(name, blob)| (name.to_string(), ("action".to_string(), blob.to_string())))
            .collect::<BTreeMap<_, _>>(),
        capabilities: vec!["state".into()],
        secrets: vec![],
        network: json!("closed"),
        limits: json!({}),
        installed_at: now_millis(),
    }
}

#[test]
fn a_blob_is_addressed_by_its_own_hash_and_stored_once() {
    let store = RegistryStore::open(temp_dir("blobs")).unwrap();

    let first = store.put_blob(b"some bytecode").unwrap();
    let again = store.put_blob(b"some bytecode").unwrap();
    let other = store.put_blob(b"different bytecode").unwrap();

    assert_eq!(first, again, "the same bytes address the same blob");
    assert_ne!(first, other);
    assert!(first.starts_with("sha256:"));

    assert_eq!(store.get_blob(&first).unwrap(), b"some bytecode");
    assert_eq!(store.get_blob(&other).unwrap(), b"different bytecode");
}

#[test]
fn two_versions_sharing_a_function_share_its_blob() {
    // This is what makes keeping a rollback target cheap: only what changed
    // costs anything.
    let store = RegistryStore::open(temp_dir("dedupe")).unwrap();
    let unchanged = store.put_blob(b"the function that did not change").unwrap();
    let v1 = store
        .put_blob(b"version one of the other function")
        .unwrap();
    let v2 = store
        .put_blob(b"version two of the other function")
        .unwrap();

    store
        .install(
            "app",
            version("1.0.0", &[("same", &unchanged), ("changed", &v1)]),
        )
        .unwrap();
    store
        .install(
            "app",
            version("1.1.0", &[("same", &unchanged), ("changed", &v2)]),
        )
        .unwrap();

    let record = store.app("app").unwrap();
    assert_eq!(record.versions.len(), 2);
    assert_eq!(
        record.versions["1.0.0"].functions["same"].1, record.versions["1.1.0"].functions["same"].1,
        "the unchanged function is the same blob in both versions"
    );
}

#[test]
fn a_tampered_blob_is_caught_on_read() {
    // Content addressing is only worth having if it is checked. Serving
    // bytecode that is not what was installed is the worst failure this
    // component has.
    let dir = temp_dir("tamper");
    let store = RegistryStore::open(&dir).unwrap();
    let address = store.put_blob(b"honest bytecode").unwrap();

    // Overwrite the blob on disk with something else, keeping its name.
    let hex = address.strip_prefix("sha256:").unwrap();
    let (prefix, rest) = hex.split_at(2);
    let path = dir.join("blobs").join(prefix).join(rest);
    std::fs::write(&path, b"tampered bytecode").unwrap();

    assert_eq!(
        store.get_blob(&address),
        Err(RegistryError::Corrupt { address })
    );
}

#[test]
fn installing_does_not_deploy() {
    // An operator can stage a version and cut over separately.
    let store = RegistryStore::open(temp_dir("stage")).unwrap();
    let blob = store.put_blob(b"code").unwrap();
    store
        .install("app", version("1.0.0", &[("f", &blob)]))
        .unwrap();

    assert!(
        store.active_version("app").is_none(),
        "installed but not yet serving"
    );
    store.deploy("app", "1.0.0", false).unwrap();
    assert_eq!(store.active_version("app").unwrap().version, "1.0.0");
}

#[test]
fn deploying_backwards_is_refused_unless_forced() {
    let store = RegistryStore::open(temp_dir("downgrade")).unwrap();
    let blob = store.put_blob(b"code").unwrap();
    for v in ["1.0.0", "1.9.0", "1.10.0"] {
        store.install("app", version(v, &[("f", &blob)])).unwrap();
    }

    store.deploy("app", "1.10.0", false).unwrap();

    // `1.9.0` is older than `1.10.0` — a string comparison gets this backwards,
    // and an accidental redeploy of an old artifact is expensive precisely
    // because the registry is the last place that can notice.
    assert_eq!(
        store.deploy("app", "1.9.0", false),
        Err(RegistryError::Downgrade {
            app: "app".into(),
            from: "1.10.0".into(),
            to: "1.9.0".into()
        })
    );
    assert_eq!(store.active_version("app").unwrap().version, "1.10.0");

    // A rollback is a deliberate act, so it is available — with `force`.
    store.deploy("app", "1.9.0", true).unwrap();
    assert_eq!(store.active_version("app").unwrap().version, "1.9.0");
}

#[test]
fn version_comparison_is_numeric_not_lexical() {
    use std::cmp::Ordering;
    assert_eq!(compare_versions("1.10.0", "1.9.0"), Ordering::Greater);
    assert_eq!(compare_versions("2.0.0", "10.0.0"), Ordering::Less);
    assert_eq!(compare_versions("1.0.0", "1.0.0"), Ordering::Equal);
    assert_eq!(compare_versions("1.0", "1.0.0"), Ordering::Equal);
    assert_eq!(compare_versions("1.0.1", "1.0"), Ordering::Greater);
}

#[test]
fn the_active_version_cannot_be_removed() {
    let store = RegistryStore::open(temp_dir("remove")).unwrap();
    let blob = store.put_blob(b"code").unwrap();
    store
        .install("app", version("1.0.0", &[("f", &blob)]))
        .unwrap();
    store
        .install("app", version("1.1.0", &[("f", &blob)]))
        .unwrap();
    store.deploy("app", "1.1.0", false).unwrap();

    assert!(
        store.remove_version("app", "1.1.0").is_err(),
        "removing the active version would leave the app pointing at nothing"
    );
    // A non-active one is fine.
    store.remove_version("app", "1.0.0").unwrap();
    assert_eq!(store.app("app").unwrap().versions.len(), 1);
}

#[test]
fn the_index_survives_a_reopen() {
    let dir = temp_dir("reopen");
    let blob = {
        let store = RegistryStore::open(&dir).unwrap();
        let blob = store.put_blob(b"code").unwrap();
        store
            .install("app", version("2.0.0", &[("f", &blob)]))
            .unwrap();
        store.deploy("app", "2.0.0", false).unwrap();
        blob
    };

    // A fresh process reading the same directory sees the same registry.
    let reopened = RegistryStore::open(&dir).unwrap();
    assert_eq!(reopened.app_ids(), vec!["app".to_string()]);
    let active = reopened.active_version("app").unwrap();
    assert_eq!(active.version, "2.0.0");
    assert_eq!(active.functions["f"].1, blob);
    assert_eq!(reopened.get_blob(&blob).unwrap(), b"code");
}

#[test]
fn an_interrupted_index_write_leaves_the_previous_index_intact() {
    // The index is renamed over, never edited in place, so a crash leaves
    // either the old file or the new one. Simulated here by leaving a stray
    // temp file behind, which must not be mistaken for the index.
    let dir = temp_dir("atomic");
    let store = RegistryStore::open(&dir).unwrap();
    let blob = store.put_blob(b"code").unwrap();
    store
        .install("app", version("1.0.0", &[("f", &blob)]))
        .unwrap();
    store.deploy("app", "1.0.0", false).unwrap();

    std::fs::write(dir.join("index.json.tmp999999"), b"{ this is not json").unwrap();

    let reopened = RegistryStore::open(&dir).unwrap();
    assert_eq!(
        reopened.active_version("app").unwrap().version,
        "1.0.0",
        "a leftover temp file is not the index"
    );
}

#[test]
fn unknown_apps_and_versions_are_reported_rather_than_created() {
    let store = RegistryStore::open(temp_dir("unknown")).unwrap();
    assert_eq!(
        store.deploy("ghost", "1.0.0", false),
        Err(RegistryError::UnknownApp("ghost".into()))
    );

    let blob = store.put_blob(b"code").unwrap();
    store
        .install("real", version("1.0.0", &[("f", &blob)]))
        .unwrap();
    assert_eq!(
        store.deploy("real", "9.9.9", false),
        Err(RegistryError::UnknownVersion {
            app: "real".into(),
            version: "9.9.9".into()
        })
    );
}
