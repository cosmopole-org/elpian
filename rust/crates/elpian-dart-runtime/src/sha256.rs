//! SHA-256 and HMAC-SHA256, re-exported from `elpian-crypto`.
//!
//! The implementation moved out of this crate so the pieces that need a digest
//! — the bundle verifier here, plus the host's registry content addressing and
//! the package format — share one copy without any of them depending on the
//! Dart extras. This module is kept as the path existing callers already use.

pub use elpian_crypto::{constant_time_eq, hex, hmac_sha256, sha256};
