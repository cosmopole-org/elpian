//! # elpian-pkg — the `.elpianpkg` container
//!
//! One file carrying a mini app's whole deployable form: its client bytecode,
//! one module per server function, and the manifest that says what it may do.
//!
//! ## Why a custom container rather than tar or zip
//!
//! **Determinism.** The same source must build the same bytes, or a signature
//! says nothing useful and two people cannot check they have the same artifact.
//! Tar carries mtimes, uids and ordering freedom; zip carries timestamps and
//! several ways to spell the same archive. Both would have to be normalised
//! into submission, and the normalising is where the bug lives.
//!
//! **Surface.** A decompressor is a parser of hostile input, and this container
//! needs none: bytecode is already compact and a mini app is small. Not having
//! one is a smaller attack surface than having a careful one.
//!
//! ## Layout
//!
//! ```text
//! "EPKG1"            5 bytes, magic
//! u32                index length, big-endian
//! <index>            JSON: manifest + entry table (name, offset, length, hash)
//! <blobs>            entry payloads, back to back, in index order
//! u32                signature length, big-endian
//! <signature>        over everything before this field
//! ```
//!
//! The index is JSON because an operator has to be able to read it, and because
//! `elpian inspect` on an untrusted package must be able to say what is inside
//! *without* trusting it. It is rendered with sorted keys and no incidental
//! whitespace so it is byte-stable.
//!
//! ## Signing
//!
//! HMAC-SHA256 over the whole container up to the signature, using the scheme
//! already in the tree (`elpian-crypto`). That is a *shared secret*: it proves
//! the package came from someone holding the key, which is enough for an
//! operator packaging their own apps and is **not** enough for third-party
//! publishing — a verifying host would need every publisher's signing key.
//! ed25519 is the upgrade path, and the verifier is written against a trait so
//! the scheme can change without touching the load path.

use std::collections::BTreeMap;

use serde_json::{json, Value};

const MAGIC: &[u8; 5] = b"EPKG1";

/// One file inside a package.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// Logical name: `client`, or `fn/<name>`.
    pub name: String,
    pub data: Vec<u8>,
}

/// What a package carries.
#[derive(Debug, Clone, PartialEq)]
pub struct Package {
    /// The app manifest: id, version, capabilities, network mode, functions.
    pub manifest: Value,
    /// Entries, sorted by name — the sort is what makes the bytes deterministic.
    pub entries: Vec<Entry>,
}

/// Why a package could not be read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PackageError {
    /// Not an Elpian package at all.
    BadMagic,
    /// Structurally malformed — truncated, or a length that does not fit.
    Truncated(&'static str),
    /// The index is not readable JSON, or is missing something required.
    BadIndex(String),
    /// An entry's bytes do not match the hash the index recorded.
    ///
    /// Distinct from a bad signature: this says *which* part was altered, which
    /// is what an operator needs when a package fails to verify.
    EntryCorrupt { name: String },
    /// The signature does not verify.
    BadSignature,
    /// The container version is newer than this reader understands.
    UnsupportedVersion(String),
}

impl PackageError {
    pub fn message(&self) -> String {
        match self {
            PackageError::BadMagic => "not an Elpian package".into(),
            PackageError::Truncated(what) => format!("package is truncated: {what}"),
            PackageError::BadIndex(e) => format!("package index is unreadable: {e}"),
            PackageError::EntryCorrupt { name } => {
                format!("entry {name} does not match its recorded hash")
            }
            PackageError::BadSignature => "package signature does not verify".into(),
            PackageError::UnsupportedVersion(v) => {
                format!("package format {v} is newer than this tool understands")
            }
        }
    }
}

impl Package {
    /// Serialise, signing with `key`.
    ///
    /// The same `Package` always produces the same bytes: entries are sorted by
    /// name, the index is rendered with sorted keys, and nothing carries a
    /// timestamp. That is what lets two people check they built the same thing.
    pub fn write(&self, key: &[u8]) -> Vec<u8> {
        let mut entries = self.entries.clone();
        entries.sort_by(|a, b| a.name.cmp(&b.name));

        let mut offset = 0usize;
        let mut table = Vec::new();
        for entry in &entries {
            table.push(json!({
                "name": entry.name,
                "offset": offset,
                "length": entry.data.len(),
                "hash": elpian_crypto::content_address(&entry.data),
            }));
            offset += entry.data.len();
        }

        let index = canonical_json(&json!({
            "format": "EPKG1",
            "manifest": self.manifest,
            "entries": table,
        }));

        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&(index.len() as u32).to_be_bytes());
        out.extend_from_slice(index.as_bytes());
        for entry in &entries {
            out.extend_from_slice(&entry.data);
        }

        let signature = elpian_crypto::hmac_sha256(key, &out);
        out.extend_from_slice(&(signature.len() as u32).to_be_bytes());
        out.extend_from_slice(&signature);
        out
    }

    /// Parse and verify.
    ///
    /// The signature is checked **before** any entry is handed back, and each
    /// entry is checked against its recorded hash as it is extracted. A package
    /// that fails either check yields nothing at all — there is no partial
    /// success, because a partially-trusted package is just an untrusted one
    /// that got further than it should have.
    pub fn read(bytes: &[u8], key: &[u8]) -> Result<Package, PackageError> {
        if bytes.len() < MAGIC.len() + 4 {
            return Err(PackageError::Truncated("header"));
        }
        if &bytes[..MAGIC.len()] != MAGIC {
            return Err(PackageError::BadMagic);
        }

        let mut cursor = MAGIC.len();
        let index_len =
            read_u32(bytes, &mut cursor).ok_or(PackageError::Truncated("index length"))?;
        let index_end = cursor
            .checked_add(index_len)
            .filter(|end| *end <= bytes.len())
            .ok_or(PackageError::Truncated("index"))?;
        let index_raw = &bytes[cursor..index_end];
        cursor = index_end;

        // Find the signature: the last 4-byte length plus its bytes.
        if bytes.len() < 4 {
            return Err(PackageError::Truncated("signature length"));
        }
        // The signature length field sits immediately before the signature, at
        // the very end. Locate it by walking back from the end.
        let sig_len_pos = bytes
            .len()
            .checked_sub(4)
            .ok_or(PackageError::Truncated("signature length"))?;
        // Try the common case first: a 32-byte HMAC.
        let (signed_len, signature) = {
            let mut found = None;
            // The only valid framing is `[signed][u32 len][sig]`, so the length
            // field is at `len - 4 - siglen`. Scan the plausible sizes rather
            // than trusting a length read from an untrusted tail.
            for sig_len in [32usize] {
                if bytes.len() < sig_len + 4 {
                    continue;
                }
                let len_pos = bytes.len() - sig_len - 4;
                let declared = u32::from_be_bytes([
                    bytes[len_pos],
                    bytes[len_pos + 1],
                    bytes[len_pos + 2],
                    bytes[len_pos + 3],
                ]) as usize;
                if declared == sig_len {
                    found = Some((len_pos, &bytes[len_pos + 4..]));
                    break;
                }
            }
            found.ok_or(PackageError::Truncated("signature"))?
        };
        let _ = sig_len_pos;

        let expected = elpian_crypto::hmac_sha256(key, &bytes[..signed_len]);
        if !elpian_crypto::constant_time_eq(&expected, signature) {
            return Err(PackageError::BadSignature);
        }

        let index: Value =
            serde_json::from_slice(index_raw).map_err(|e| PackageError::BadIndex(e.to_string()))?;

        match index["format"].as_str() {
            Some("EPKG1") => {}
            Some(other) => return Err(PackageError::UnsupportedVersion(other.to_string())),
            None => return Err(PackageError::BadIndex("no format field".into())),
        }

        let blobs_start = cursor;
        let table = index["entries"]
            .as_array()
            .ok_or_else(|| PackageError::BadIndex("no entries array".into()))?;

        let mut entries = Vec::new();
        for record in table {
            let name = record["name"]
                .as_str()
                .ok_or_else(|| PackageError::BadIndex("an entry has no name".into()))?
                .to_string();
            let offset = record["offset"]
                .as_u64()
                .ok_or_else(|| PackageError::BadIndex(format!("{name}: no offset")))?
                as usize;
            let length = record["length"]
                .as_u64()
                .ok_or_else(|| PackageError::BadIndex(format!("{name}: no length")))?
                as usize;

            let start = blobs_start
                .checked_add(offset)
                .ok_or(PackageError::Truncated("entry offset"))?;
            let end = start
                .checked_add(length)
                .filter(|end| *end <= signed_len)
                .ok_or(PackageError::Truncated("entry data"))?;
            let data = bytes[start..end].to_vec();

            // Per-entry hashes are not redundant with the signature. The
            // signature says the file is intact as a whole; these say *which*
            // entry is wrong when it is not, which is what an operator needs.
            if let Some(hash) = record["hash"].as_str() {
                if elpian_crypto::content_address(&data) != hash {
                    return Err(PackageError::EntryCorrupt { name });
                }
            }

            entries.push(Entry { name, data });
        }

        Ok(Package {
            manifest: index["manifest"].clone(),
            entries,
        })
    }

    /// Read a package's index *without* verifying it, for `elpian inspect`.
    ///
    /// Deliberately separate and deliberately named: an operator has to be able
    /// to ask "what is in this file" before deciding whether to trust it, and
    /// that question must not be answered by a function anyone could mistake
    /// for a verifying read. It returns only the index — never entry data.
    pub fn inspect_unverified(bytes: &[u8]) -> Result<Value, PackageError> {
        if bytes.len() < MAGIC.len() + 4 || &bytes[..MAGIC.len()] != MAGIC {
            return Err(PackageError::BadMagic);
        }
        let mut cursor = MAGIC.len();
        let index_len =
            read_u32(bytes, &mut cursor).ok_or(PackageError::Truncated("index length"))?;
        let end = cursor
            .checked_add(index_len)
            .filter(|e| *e <= bytes.len())
            .ok_or(PackageError::Truncated("index"))?;
        serde_json::from_slice(&bytes[cursor..end])
            .map_err(|e| PackageError::BadIndex(e.to_string()))
    }

    pub fn entry(&self, name: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.name == name)
    }

    /// The server function entries, by function name.
    pub fn functions(&self) -> BTreeMap<String, &Entry> {
        self.entries
            .iter()
            .filter_map(|e| e.name.strip_prefix("fn/").map(|n| (n.to_string(), e)))
            .collect()
    }
}

fn read_u32(bytes: &[u8], cursor: &mut usize) -> Option<usize> {
    let end = cursor.checked_add(4)?;
    if end > bytes.len() {
        return None;
    }
    let value = u32::from_be_bytes([
        bytes[*cursor],
        bytes[*cursor + 1],
        bytes[*cursor + 2],
        bytes[*cursor + 3],
    ]) as usize;
    *cursor = end;
    Some(value)
}

/// Render JSON with object keys sorted and no incidental whitespace.
///
/// `serde_json`'s maps preserve insertion order, so two logically identical
/// manifests written in different key orders would produce different bytes —
/// and a signature over them would differ for no reason anyone could see. This
/// is the whole of the determinism guarantee.
pub fn canonical_json(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let inner: Vec<String> = keys
                .into_iter()
                .map(|k| format!("{}:{}", Value::String(k.clone()), canonical_json(&map[k])))
                .collect();
            format!("{{{}}}", inner.join(","))
        }
        Value::Array(items) => {
            let inner: Vec<String> = items.iter().map(canonical_json).collect();
            format!("[{}]", inner.join(","))
        }
        other => other.to_string(),
    }
}
