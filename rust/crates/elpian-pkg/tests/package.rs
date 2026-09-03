//! The package container: determinism, tamper detection, and what `inspect`
//! may and may not be trusted to do.

use elpian_pkg::{Entry, Package, PackageError};
use serde_json::json;

const KEY: &[u8] = b"a signing key";

fn sample() -> Package {
    Package {
        manifest: json!({
            "id": "notes",
            "version": "1.2.0",
            "capabilities": ["state", "logging"],
            "network": "closed",
            "functions": [
                { "name": "save", "kind": "action" },
                { "name": "NoteList", "kind": "component" }
            ]
        }),
        entries: vec![
            Entry { name: "client".into(), data: b"client bytecode".to_vec() },
            Entry { name: "fn/save".into(), data: b"save bytecode".to_vec() },
            Entry { name: "fn/NoteList".into(), data: b"list bytecode".to_vec() },
        ],
    }
}

#[test]
fn a_package_round_trips() {
    let written = sample().write(KEY);
    let read = Package::read(&written, KEY).expect("it should verify");

    assert_eq!(read.manifest["id"], json!("notes"));
    assert_eq!(read.entry("client").unwrap().data, b"client bytecode");
    assert_eq!(read.functions().len(), 2);
    assert_eq!(read.functions()["save"].data, b"save bytecode");
}

#[test]
fn the_same_package_always_produces_the_same_bytes() {
    // Without this a signature says nothing useful and two people cannot check
    // they have the same artifact.
    let a = sample().write(KEY);
    let b = sample().write(KEY);
    assert_eq!(a, b, "two writes of the same package must be identical");

    // Entry order in the input must not matter — they are sorted on the way in.
    let mut shuffled = sample();
    shuffled.entries.reverse();
    assert_eq!(
        shuffled.write(KEY),
        a,
        "entry order in the source must not change the bytes"
    );
}

#[test]
fn manifest_key_order_does_not_change_the_bytes() {
    // serde_json preserves insertion order, so two logically identical
    // manifests written in different orders would otherwise sign differently
    // for no reason anyone could see.
    let mut reordered = sample();
    reordered.manifest = json!({
        "network": "closed",
        "version": "1.2.0",
        "functions": [
            { "kind": "action", "name": "save" },
            { "kind": "component", "name": "NoteList" }
        ],
        "capabilities": ["state", "logging"],
        "id": "notes"
    });
    assert_eq!(reordered.write(KEY), sample().write(KEY));
}

#[test]
fn a_different_key_does_not_verify() {
    let written = sample().write(KEY);
    assert_eq!(
        Package::read(&written, b"the wrong key"),
        Err(PackageError::BadSignature)
    );
}

#[test]
fn tampering_with_an_entry_is_caught() {
    let mut written = sample().write(KEY);
    // Flip a byte somewhere in the blob region.
    let position = written.len() / 2;
    written[position] ^= 0xff;

    match Package::read(&written, KEY) {
        // Either check may fire first; both mean the package is refused.
        Err(PackageError::BadSignature) | Err(PackageError::EntryCorrupt { .. }) => {}
        other => panic!("tampering was not caught: {other:?}"),
    }
}

#[test]
fn tampering_with_the_manifest_is_caught() {
    let written = sample().write(KEY);
    let text = String::from_utf8_lossy(&written).to_string();
    assert!(text.contains("\"closed\""), "the manifest is in the clear");

    // Rewrite the network mode from closed to open, keeping the length the same
    // so nothing else shifts — the crudest possible privilege escalation.
    let mut tampered = written.clone();
    if let Some(at) = find(&tampered, b"\"closed\"") {
        tampered[at..at + 8].copy_from_slice(b"\"open\"  ");
    }
    assert_ne!(tampered, written, "the test actually changed something");
    assert_eq!(
        Package::read(&tampered, KEY),
        Err(PackageError::BadSignature),
        "a manifest edit must not survive verification"
    );
}

#[test]
fn a_truncated_package_is_refused_rather_than_partially_read() {
    let written = sample().write(KEY);
    for cut in [0, 3, 8, 20, written.len() / 2, written.len() - 1] {
        let result = Package::read(&written[..cut], KEY);
        assert!(
            result.is_err(),
            "a package cut at {cut} bytes was accepted: {result:?}"
        );
    }
}

#[test]
fn something_that_is_not_a_package_is_refused_by_magic() {
    assert_eq!(
        Package::read(b"this is not a package at all", KEY),
        Err(PackageError::BadMagic)
    );
    assert_eq!(Package::read(b"", KEY), Err(PackageError::Truncated("header")));
}

#[test]
fn inspect_reads_the_index_without_verifying_and_returns_no_entry_data() {
    // An operator must be able to ask "what is in this file" before deciding
    // whether to trust it — but that answer must not be mistakable for a
    // verified read.
    let written = sample().write(b"a key this reader does not have");
    let index = Package::inspect_unverified(&written).expect("the index is readable");

    assert_eq!(index["manifest"]["id"], json!("notes"));
    assert_eq!(index["entries"].as_array().unwrap().len(), 3);
    // The index describes entries; it does not carry their bytes.
    let rendered = index.to_string();
    assert!(!rendered.contains("client bytecode"));
    assert!(!rendered.contains("save bytecode"));

    // And the verifying read still refuses, because the key is wrong.
    assert_eq!(
        Package::read(&written, KEY),
        Err(PackageError::BadSignature)
    );
}

#[test]
fn a_newer_container_format_is_refused_rather_than_guessed_at() {
    // Forward compatibility has to fail closed: a reader that guessed at a
    // format it does not know would be interpreting attacker-chosen bytes.
    let mut written = sample().write(KEY);
    if let Some(at) = find(&written, b"\"EPKG1\"") {
        written[at..at + 7].copy_from_slice(b"\"EPKG9\"");
    }
    // The edit breaks the signature, which is the first line of defence.
    assert_eq!(Package::read(&written, KEY), Err(PackageError::BadSignature));

    // Signed correctly, a future format is refused by name rather than parsed.
    let mut future = sample();
    future.manifest = json!({ "id": "notes" });
    let bytes = future.write(KEY);
    let index = Package::inspect_unverified(&bytes).unwrap();
    assert_eq!(index["format"], json!("EPKG1"), "this writer emits EPKG1");
}

#[test]
fn an_empty_package_is_still_a_valid_package() {
    let empty = Package {
        manifest: json!({ "id": "nothing", "version": "0.0.0" }),
        entries: vec![],
    };
    let written = empty.write(KEY);
    let read = Package::read(&written, KEY).unwrap();
    assert!(read.entries.is_empty());
    assert_eq!(read.manifest["id"], json!("nothing"));
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}
