//! Serving a directory of static files.
//!
//! The host exists to serve mini apps; this is here so it can also stand in for
//! a development web server, which is what `elpian run dev` needs — a host you
//! cannot develop against without running a second server is a host with an
//! awkward story.
//!
//! # Confinement
//!
//! The same rule as [`crate::appfs`], for the same reason: a request path is
//! attacker-chosen, and string checks on paths are a losing game. `..%2f`, a
//! symlink, a Windows separator, an absolute path that happens to share the
//! root's text — the one that gets missed is a read of the host's filesystem.
//!
//! So the path is rebuilt from its components, anything that is not a plain
//! named segment is refused, and the result is re-checked after
//! canonicalisation in case a symlink inside the root points out of it.

use std::path::{Component, Path, PathBuf};

use crate::httpcore::Response;

/// Resolve a request path inside `root`, or `None` if it tries to leave.
pub fn resolve(root: &Path, request_path: &str) -> Option<PathBuf> {
    let mut out = root.to_path_buf();
    for component in Path::new(request_path.trim_start_matches('/')).components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            // `..`, a leading `/`, a `C:\` prefix: every way out.
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
        }
    }

    // A directory serves its index, the way every web server does.
    if out.is_dir() {
        out.push("index.html");
    }

    // The component walk cannot be fooled by the path string, but it can be
    // fooled by the filesystem: a symlink inside the root pointing out of it
    // resolves elsewhere entirely.
    let real = out.canonicalize().ok()?;
    let real_root = root.canonicalize().ok()?;
    if !real.starts_with(&real_root) {
        return None;
    }
    Some(real)
}

/// Serve a file from `root`, or 404.
pub fn serve(root: &Path, request_path: &str) -> Response {
    let Some(path) = resolve(root, request_path) else {
        // The same answer for "outside the root" and "does not exist". A caller
        // that could tell them apart could map the host's filesystem by asking.
        return Response::error(404, "not found");
    };
    match std::fs::read(&path) {
        Ok(bytes) => Response::bytes(200, content_type(&path), bytes),
        Err(_) => Response::error(404, "not found"),
    }
}

/// A content type from the file extension.
///
/// A short table rather than a database: these are what a dev server actually
/// hands out, and an unknown extension gets `application/octet-stream` — which
/// a browser will download rather than execute, the safe default for a type the
/// host does not recognise.
fn content_type(path: &Path) -> &'static str {
    match path.extension().and_then(|e| e.to_str()) {
        Some("html") | Some("htm") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json",
        Some("wasm") => "application/wasm",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("ico") => "image/x-icon",
        Some("woff2") => "font/woff2",
        Some("woff") => "font/woff",
        Some("ttf") => "font/ttf",
        Some("txt") => "text/plain; charset=utf-8",
        Some("map") => "application/json",
        Some("bc") => "application/octet-stream",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("elpian-static-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::write(dir.join("index.html"), b"<h1>root</h1>").unwrap();
        std::fs::write(dir.join("app.js"), b"console.log(1)").unwrap();
        std::fs::write(dir.join("sub/index.html"), b"<h1>sub</h1>").unwrap();
        dir
    }

    #[test]
    fn ordinary_paths_resolve() {
        let dir = fixture("ok");
        assert!(resolve(&dir, "/app.js").is_some());
        assert!(resolve(&dir, "/index.html").is_some());
        // A directory serves its index.
        assert!(resolve(&dir, "/sub").unwrap().ends_with("index.html"));
        assert!(resolve(&dir, "/").unwrap().ends_with("index.html"));
    }

    #[test]
    fn traversal_is_refused() {
        let dir = fixture("escape");
        for attempt in [
            "/../secrets",
            "/sub/../../secrets",
            "/etc/passwd",
            "//etc/passwd",
            "/sub/../../../etc/passwd",
        ] {
            assert!(
                resolve(&dir, attempt).is_none(),
                "{attempt} should not resolve"
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_out_of_the_root_is_refused() {
        let dir = fixture("symlink");
        let outside =
            std::env::temp_dir().join(format!("elpian-static-outside-{}", std::process::id()));
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret.txt"), b"nope").unwrap();
        let _ = std::fs::remove_file(dir.join("link"));
        std::os::unix::fs::symlink(&outside, dir.join("link")).unwrap();

        // Every component is "normal", so only the canonicalised check catches it.
        assert!(resolve(&dir, "/link/secret.txt").is_none());
    }

    #[test]
    fn a_missing_file_and_an_escape_answer_identically() {
        // A caller that could tell them apart could map the host's filesystem
        // by asking.
        let dir = fixture("same");
        let missing = serve(&dir, "/nothing-here.txt");
        let escape = serve(&dir, "/../../etc/passwd");
        assert_eq!(missing.status, escape.status);
        assert_eq!(missing.body, escape.body);
    }

    #[test]
    fn an_unknown_extension_is_not_served_as_something_executable() {
        let dir = fixture("types");
        std::fs::write(dir.join("thing.weird"), b"data").unwrap();
        let response = serve(&dir, "/thing.weird");
        assert_eq!(response.content_type, "application/octet-stream");
        assert_eq!(
            content_type(Path::new("a.js")),
            "text/javascript; charset=utf-8"
        );
        assert_eq!(
            content_type(Path::new("a.html")),
            "text/html; charset=utf-8"
        );
    }
}
