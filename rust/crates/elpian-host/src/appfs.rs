//! The app-rooted filesystem a server function sees through `fs.*`.
//!
//! # Confinement
//!
//! Every path a guest supplies is resolved *inside* the app's own directory,
//! and the resolution is done by rebuilding the path from its components rather
//! than by inspecting the string. String checks on paths are a losing game —
//! `..%2f`, a symlink, a Windows separator, an absolute path that happens to
//! start with the root's text — and the one that gets missed is a read of the
//! host's filesystem.
//!
//! So: reject anything that is not a plain named component, and build the
//! result from the ones that are. A path that cannot be expressed that way does
//! not resolve at all.

use std::path::{Component, Path, PathBuf};

/// An app's private directory.
#[derive(Clone, Debug)]
pub struct AppFs {
    root: PathBuf,
}

impl AppFs {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        AppFs { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Resolve a guest-supplied relative path inside the app root, or `None` if
    /// it tries to leave.
    ///
    /// `None` covers: absolute paths, any `..`, Windows prefixes, and (on the
    /// resolved result) anything that escapes via a symlink.
    pub fn resolve(&self, relative: &str) -> Option<PathBuf> {
        let mut out = self.root.clone();
        for component in Path::new(relative).components() {
            match component {
                Component::Normal(part) => out.push(part),
                // `./` is harmless and common in guest code.
                Component::CurDir => {}
                // Everything else is a way out: `..`, a leading `/`, `C:\`.
                Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
            }
        }

        // The component walk cannot be fooled by the path *string*, but it can
        // be fooled by the filesystem: a symlink inside the app root pointing
        // out of it resolves to somewhere else entirely. Check the real path
        // when there is one. A path that does not exist yet (an about-to-be
        // written file) has no real path to check, so its parent is checked
        // instead.
        let to_check = if out.exists() {
            out.clone()
        } else {
            out.parent()?.to_path_buf()
        };
        if let Ok(real) = to_check.canonicalize() {
            let real_root = self.root.canonicalize().ok()?;
            if !real.starts_with(&real_root) {
                return None;
            }
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fs_at(dir: &Path) -> AppFs {
        AppFs::new(dir)
    }

    #[test]
    fn ordinary_paths_resolve_inside_the_root() {
        let dir = std::env::temp_dir().join("elpian-appfs-ok");
        std::fs::create_dir_all(&dir).unwrap();
        let fs = fs_at(&dir);
        assert_eq!(fs.resolve("notes.json"), Some(dir.join("notes.json")));
        assert_eq!(fs.resolve("./a/b.txt"), Some(dir.join("a").join("b.txt")));
    }

    #[test]
    fn escapes_are_refused() {
        let dir = std::env::temp_dir().join("elpian-appfs-escape");
        std::fs::create_dir_all(&dir).unwrap();
        let fs = fs_at(&dir);
        for attempt in [
            "../secrets",
            "a/../../secrets",
            "/etc/passwd",
            "a/b/../../../etc/passwd",
        ] {
            assert_eq!(fs.resolve(attempt), None, "{attempt} should not resolve");
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_out_of_the_root_is_refused() {
        let dir = std::env::temp_dir().join("elpian-appfs-symlink");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let outside = std::env::temp_dir().join("elpian-appfs-outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret.txt"), b"nope").unwrap();

        // The path is made entirely of normal components, so only the
        // canonicalised check can catch it.
        std::os::unix::fs::symlink(&outside, dir.join("link")).unwrap();
        let fs = fs_at(&dir);
        assert_eq!(fs.resolve("link/secret.txt"), None);
    }
}
