//! Signed code-delivery bundles: verify **before** load.
//!
//! Loading remotely-delivered code is the whole point of this project and also
//! its biggest risk: an unverified bundle is a remote-code-execution backdoor.
//! So the load path is: fetch → **verify signature** → check version is not a
//! downgrade → only then hand the source to the front-end. Verification is
//! pluggable via [`SignatureScheme`]; the default is HMAC-SHA256 over the bytes,
//! and a production deployment can drop in ed25519 without touching the flow.

use crate::sha256::{constant_time_eq, hex, hmac_sha256, sha256};

/// A delivered code bundle. `source` is Dart (or the interim JS) for the
/// front-end; `signature` authenticates `source` + metadata.
#[derive(Debug, Clone)]
pub struct CodeBundle {
    pub id: String,
    pub version: u64,
    pub entrypoint: String,
    pub source: String,
    pub signature: Vec<u8>,
}

impl CodeBundle {
    /// The exact byte string the signature covers: id, version, entrypoint, and
    /// source, length-delimited so fields cannot be shifted across boundaries.
    pub fn signing_input(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        for field in [&self.id, &self.version.to_string(), &self.entrypoint, &self.source] {
            buf.extend_from_slice(&(field.len() as u64).to_be_bytes());
            buf.extend_from_slice(field.as_bytes());
        }
        buf
    }
}

/// A pluggable signature scheme.
pub trait SignatureScheme {
    fn sign(&self, message: &[u8]) -> Vec<u8>;
    fn verify(&self, message: &[u8], signature: &[u8]) -> bool;
}

/// HMAC-SHA256 over a shared secret — the default scheme.
pub struct HmacSha256Scheme {
    key: Vec<u8>,
}

impl HmacSha256Scheme {
    pub fn new(key: impl Into<Vec<u8>>) -> Self {
        HmacSha256Scheme { key: key.into() }
    }
}

impl SignatureScheme for HmacSha256Scheme {
    fn sign(&self, message: &[u8]) -> Vec<u8> {
        hmac_sha256(&self.key, message).to_vec()
    }
    fn verify(&self, message: &[u8], signature: &[u8]) -> bool {
        let expected = hmac_sha256(&self.key, message);
        constant_time_eq(&expected, signature)
    }
}

/// Why a bundle was rejected.
#[derive(Debug, PartialEq)]
pub enum BundleError {
    /// Signature did not verify — bytes were tampered with or wrong key.
    BadSignature,
    /// The bundle's version is not newer than what is already installed
    /// (replay / downgrade protection).
    Downgrade { installed: u64, offered: u64 },
}

/// Verifies and gates bundles for a single miniapp id, tracking the installed
/// version so an attacker cannot roll a device back to a known-vulnerable build.
pub struct BundleLoader<S: SignatureScheme> {
    scheme: S,
    installed_version: Option<u64>,
}

impl<S: SignatureScheme> BundleLoader<S> {
    pub fn new(scheme: S) -> Self {
        BundleLoader { scheme, installed_version: None }
    }

    /// The currently-installed version, if any.
    pub fn installed_version(&self) -> Option<u64> {
        self.installed_version
    }

    /// Sign a bundle (build-/server-side helper) — fills in `signature`.
    pub fn sign(&self, bundle: &mut CodeBundle) {
        bundle.signature = self.scheme.sign(&bundle.signing_input());
    }

    /// Verify + version-gate a bundle. On success records the new version and
    /// returns the trusted source ready for the front-end. On failure the
    /// source is never returned, so it can never reach the VM.
    pub fn accept(&mut self, bundle: &CodeBundle) -> Result<String, BundleError> {
        if !self.scheme.verify(&bundle.signing_input(), &bundle.signature) {
            return Err(BundleError::BadSignature);
        }
        if let Some(installed) = self.installed_version {
            if bundle.version <= installed {
                return Err(BundleError::Downgrade {
                    installed,
                    offered: bundle.version,
                });
            }
        }
        self.installed_version = Some(bundle.version);
        Ok(bundle.source.clone())
    }
}

// ---------------------------------------------------------------------------
// Signed manifest: dependency resolution + content-hash pinning
// ---------------------------------------------------------------------------

/// One pinned bundle in a manifest: its id, version, and the SHA-256 of its
/// source (content addressing / integrity pin).
#[derive(Debug, Clone)]
pub struct ManifestEntry {
    pub id: String,
    pub version: u64,
    pub sha256_hex: String,
}

/// A signed manifest listing an app and its dependency bundles. Signing the
/// manifest (which pins each bundle's content hash) means individual bundles do
/// not each need a signature — the manifest vouches for their exact bytes.
#[derive(Debug, Clone, Default)]
pub struct Manifest {
    pub entries: Vec<ManifestEntry>,
    pub signature: Vec<u8>,
}

impl Manifest {
    pub fn signing_input(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        for e in &self.entries {
            for field in [&e.id, &e.version.to_string(), &e.sha256_hex] {
                buf.extend_from_slice(&(field.len() as u64).to_be_bytes());
                buf.extend_from_slice(field.as_bytes());
            }
        }
        buf
    }
}

/// Build a manifest entry for a bundle, pinning its content hash.
pub fn pin(bundle: &CodeBundle) -> ManifestEntry {
    ManifestEntry {
        id: bundle.id.clone(),
        version: bundle.version,
        sha256_hex: hex(&sha256(bundle.source.as_bytes())),
    }
}

#[derive(Debug, PartialEq)]
pub enum ManifestError {
    BadSignature,
    MissingBundle(String),
    HashMismatch(String),
}

/// Verifies a signed manifest, then resolves each entry against the supplied
/// bundles, checking every bundle's content hash against its pin before trusting
/// its source.
pub struct ManifestLoader<S: SignatureScheme> {
    scheme: S,
}

impl<S: SignatureScheme> ManifestLoader<S> {
    pub fn new(scheme: S) -> Self {
        ManifestLoader { scheme }
    }

    pub fn sign(&self, manifest: &mut Manifest) {
        manifest.signature = self.scheme.sign(&manifest.signing_input());
    }

    /// Verify the manifest and resolve its entries to trusted sources, in
    /// manifest order. Any missing bundle or content-hash mismatch fails closed.
    pub fn resolve(
        &self,
        manifest: &Manifest,
        bundles: &[CodeBundle],
    ) -> Result<Vec<String>, ManifestError> {
        if !self.scheme.verify(&manifest.signing_input(), &manifest.signature) {
            return Err(ManifestError::BadSignature);
        }
        let mut sources = Vec::new();
        for entry in &manifest.entries {
            let bundle = bundles
                .iter()
                .find(|b| b.id == entry.id)
                .ok_or_else(|| ManifestError::MissingBundle(entry.id.clone()))?;
            let actual = hex(&sha256(bundle.source.as_bytes()));
            if actual != entry.sha256_hex {
                return Err(ManifestError::HashMismatch(entry.id.clone()));
            }
            sources.push(bundle.source.clone());
        }
        Ok(sources)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundle(version: u64, source: &str) -> CodeBundle {
        CodeBundle {
            id: "app.counter".into(),
            version,
            entrypoint: "main".into(),
            source: source.into(),
            signature: Vec::new(),
        }
    }

    #[test]
    fn valid_bundle_is_accepted_once_signed() {
        let mut loader = BundleLoader::new(HmacSha256Scheme::new(*b"super-secret-key"));
        let mut b = bundle(1, "void main() {}");
        loader.sign(&mut b);
        assert_eq!(loader.accept(&b), Ok("void main() {}".to_string()));
        assert_eq!(loader.installed_version(), Some(1));
    }

    #[test]
    fn tampered_source_is_rejected() {
        let signer = BundleLoader::new(HmacSha256Scheme::new(*b"super-secret-key"));
        let mut b = bundle(1, "void main() {}");
        signer.sign(&mut b);
        // Attacker swaps the source but keeps the signature.
        b.source = "void main() { steal(); }".into();
        let mut loader = BundleLoader::new(HmacSha256Scheme::new(*b"super-secret-key"));
        assert_eq!(loader.accept(&b), Err(BundleError::BadSignature));
    }

    #[test]
    fn wrong_key_is_rejected() {
        let signer = BundleLoader::new(HmacSha256Scheme::new(*b"attacker-key"));
        let mut b = bundle(1, "void main() {}");
        signer.sign(&mut b);
        let mut loader = BundleLoader::new(HmacSha256Scheme::new(*b"super-secret-key"));
        assert_eq!(loader.accept(&b), Err(BundleError::BadSignature));
    }

    #[test]
    fn downgrade_is_rejected() {
        let key = *b"super-secret-key";
        let mut loader = BundleLoader::new(HmacSha256Scheme::new(key));
        let signer = BundleLoader::new(HmacSha256Scheme::new(key));

        let mut v2 = bundle(2, "v2");
        signer.sign(&mut v2);
        assert!(loader.accept(&v2).is_ok());

        // A validly-signed but older bundle must still be refused.
        let mut v1 = bundle(1, "v1");
        signer.sign(&mut v1);
        assert_eq!(
            loader.accept(&v1),
            Err(BundleError::Downgrade { installed: 2, offered: 1 })
        );
    }

    #[test]
    fn signed_manifest_resolves_dependencies_and_pins_content() {
        let key = *b"manifest-key";
        let signer = ManifestLoader::new(HmacSha256Scheme::new(key));

        let app = CodeBundle { id: "app".into(), version: 3, entrypoint: "main".into(), source: "void main(){}".into(), signature: vec![] };
        let dep = CodeBundle { id: "widgets".into(), version: 3, entrypoint: "".into(), source: "class W {}".into(), signature: vec![] };

        let mut manifest = Manifest { entries: vec![pin(&app), pin(&dep)], signature: vec![] };
        signer.sign(&mut manifest);

        let loader = ManifestLoader::new(HmacSha256Scheme::new(key));
        let sources = loader.resolve(&manifest, &[dep.clone(), app.clone()]).expect("resolves");
        assert_eq!(sources, vec!["void main(){}".to_string(), "class W {}".to_string()]);

        // A bundle whose content doesn't match its pin is rejected.
        let mut evil = app.clone();
        evil.source = "void main(){ steal(); }".into();
        assert_eq!(
            loader.resolve(&manifest, &[dep, evil]),
            Err(ManifestError::HashMismatch("app".into()))
        );
    }
}
