//! `elpian-pkg` — build, inspect, verify and install Elpian packages.
//!
//! This is the packaging half of the `elpian` CLI, kept as its own binary so
//! the package format has no dependency on the rest of the toolchain and can be
//! used by a build system that has nothing else.
//!
//! ```text
//! elpian-pkg package <project-dir> <out.elpianpkg> [--key K] [--build-dir DIR]
//! elpian-pkg inspect <package>                       # no key needed
//! elpian-pkg verify  <package> --key K
//! elpian-pkg install <package> --registry DIR --key K [--deploy] [--force]
//! ```
//!
//! A project directory is the layout `elpian build` produces:
//!
//! ```text
//! elpian.app.json         id, version, capabilities, network, functions
//! build/client.bc
//! build/fn/<name>.bc
//! ```

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use elpian_host::registry::{now_millis, RegistryStore, VersionRecord};
use elpian_pkg::{Entry, Package};
use serde_json::Value;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(command) = args.first().map(String::as_str) else {
        eprintln!("{}", usage());
        return ExitCode::from(2);
    };

    let result = match command {
        "package" => cmd_package(&args[1..]),
        "inspect" => cmd_inspect(&args[1..]),
        "verify" => cmd_verify(&args[1..]),
        "install" => cmd_install(&args[1..]),
        "help" | "--help" | "-h" => {
            println!("{}", usage());
            return ExitCode::SUCCESS;
        }
        other => Err(format!("unknown command {other}\n\n{}", usage())),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("elpian-pkg: {message}");
            ExitCode::FAILURE
        }
    }
}

fn usage() -> String {
    "usage:\n  \
     elpian-pkg package <project-dir> <out.elpianpkg> [--key K] [--build-dir DIR]\n  \
     elpian-pkg inspect <package>\n  \
     elpian-pkg verify  <package> --key K\n  \
     elpian-pkg install <package> --registry DIR --key K [--deploy] [--force]\n\n\
     --key may also be given as ELPIAN_SIGNING_KEY in the environment."
        .into()
}

/// The key an operator configured, if any.
fn configured_key(flags: &Flags) -> Option<Vec<u8>> {
    if let Some(key) = flags.get("key") {
        return Some(key.into_bytes());
    }
    std::env::var("ELPIAN_SIGNING_KEY")
        .ok()
        .map(String::into_bytes)
}

/// The key to *sign* with. Falls back to a well-known development key so
/// `package` works out of the box, and says so.
///
/// An unsigned package is deliberately not representable: the container always
/// carries a signature. Making "no signature" a state would mean every verifier
/// needed a branch for it, and that branch is the one reached by accident in
/// production.
fn key_for_signing(flags: &Flags) -> Vec<u8> {
    match configured_key(flags) {
        Some(key) => key,
        None => {
            eprintln!(
                "elpian-pkg: warning: no --key and no ELPIAN_SIGNING_KEY; using the \
                 development key. Packages signed with it are NOT distributable — \
                 anyone can forge one, because the key is in the source."
            );
            DEVELOPMENT_KEY.to_vec()
        }
    }
}

/// The key to *verify* against. There is deliberately no fallback.
///
/// This is the important half. `verify` and `install` used to share the signing
/// fallback, which made the signature check meaningless whenever no key was
/// configured: the development key is public, so anyone could sign a package
/// that verified — and `install` takes the app's capabilities, network posture
/// and resource limits from that same manifest, so a forged package chooses its
/// own privileges.
///
/// A verification path must never have a default key. Refusing is the only safe
/// answer, and it is a loud one.
fn key_for_verifying(flags: &Flags) -> Result<Vec<u8>, String> {
    configured_key(flags).ok_or_else(|| {
        "no signing key. Pass --key or set ELPIAN_SIGNING_KEY.\n\n\
         There is no default for verification: the development key is public, \
         so verifying against it would accept a package anyone could forge.\n\
         To check a package built with the development key, pass it explicitly:\n    \
         --key elpian-development-key"
            .to_string()
    })
}

/// The key `package` falls back to. Public by construction — it exists so a
/// first build works, not so anything trusts it.
const DEVELOPMENT_KEY: &[u8] = b"elpian-development-key";

struct Flags {
    positional: Vec<String>,
    named: Vec<(String, String)>,
    switches: Vec<String>,
}

impl Flags {
    fn parse(args: &[String]) -> Flags {
        let mut flags = Flags {
            positional: Vec::new(),
            named: Vec::new(),
            switches: Vec::new(),
        };
        let mut i = 0;
        while i < args.len() {
            let arg = &args[i];
            if let Some(name) = arg.strip_prefix("--") {
                // A flag with a following value is named; one without is a
                // switch. Deciding by lookahead keeps `--deploy` and
                // `--key value` in the same parser without a table.
                match args.get(i + 1) {
                    Some(next) if !next.starts_with("--") => {
                        flags.named.push((name.to_string(), next.clone()));
                        i += 2;
                    }
                    _ => {
                        flags.switches.push(name.to_string());
                        i += 1;
                    }
                }
            } else {
                flags.positional.push(arg.clone());
                i += 1;
            }
        }
        flags
    }

    fn get(&self, name: &str) -> Option<String> {
        self.named
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.clone())
    }

    fn has(&self, name: &str) -> bool {
        self.switches.iter().any(|s| s == name)
    }
}

// ---- package ---------------------------------------------------------------

/// Resolve `path` against `base` unless it is already absolute.
fn absolute_to(base: &Path, path: &str) -> PathBuf {
    let candidate = PathBuf::from(path);
    if candidate.is_absolute() {
        candidate
    } else {
        base.join(candidate)
    }
}

fn cmd_package(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let (Some(project), Some(out)) = (flags.positional.first(), flags.positional.get(1)) else {
        return Err(format!(
            "package needs a project dir and an output path\n\n{}",
            usage()
        ));
    };
    let project = Path::new(project);

    let manifest_path = project.join("elpian.app.json");
    let manifest: Value = serde_json::from_str(
        &std::fs::read_to_string(&manifest_path)
            .map_err(|e| format!("{}: {e}", manifest_path.display()))?,
    )
    .map_err(|e| format!("elpian.app.json is not valid JSON: {e}"))?;

    // The id becomes a directory name, a state-key prefix and a URL segment on
    // the host, so it is checked here — at the point where a package is built —
    // as well as when one is loaded. Failing at build time tells the author;
    // failing only at load time tells the operator about somebody else's bug.
    let id = manifest["id"]
        .as_str()
        .ok_or("elpian.app.json has no \"id\"")?;
    if !elpian_host::app::valid_app_id(id) {
        return Err(format!(
            "{id:?} is not a valid app id. Use lowercase letters, digits, \
             '-', '_' and '.', starting with a letter or digit."
        ));
    }

    let declared = manifest["functions"]
        .as_array()
        .ok_or("elpian.app.json has no \"functions\" array")?;

    // The build directory is a *parameter*, not an assumption. A project's
    // `outDir` is its own choice (`dist` in the default config), and hardcoding
    // `build` here meant the CLI and the packager disagreed about where the
    // output was — which fails as "no such file" pointing at a path nobody
    // configured.
    let build = flags
        .get("build-dir")
        .map(|dir| absolute_to(project, &dir))
        .unwrap_or_else(|| project.join("build"));
    let mut entries = Vec::new();

    let client = build.join("client.bc");
    if client.is_file() {
        entries.push(Entry {
            name: "client".into(),
            data: std::fs::read(&client).map_err(|e| format!("client.bc: {e}"))?,
        });
    }

    // The manifest and the tree must agree. A function declared with no module
    // on disk is an error, not a silently missing route — and a module on disk
    // that the manifest does not declare is one nobody reviewed, which is worse.
    let mut declared_names = Vec::new();
    for entry in declared {
        let name = entry["name"]
            .as_str()
            .ok_or("a function entry has no \"name\"")?;
        declared_names.push(name.to_string());
        let module = build.join("fn").join(format!("{name}.bc"));
        entries.push(Entry {
            name: format!("fn/{name}"),
            data: std::fs::read(&module).map_err(|e| format!("{}: {e}", module.display()))?,
        });
    }

    let fn_dir = build.join("fn");
    if fn_dir.is_dir() {
        for file in std::fs::read_dir(&fn_dir)
            .map_err(|e| e.to_string())?
            .flatten()
        {
            let path = file.path();
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if path.extension().and_then(|e| e.to_str()) == Some("bc")
                && !declared_names.iter().any(|n| n == stem)
            {
                return Err(format!(
                    "build/fn/{stem}.bc exists but elpian.app.json does not declare it. \
                     A function nobody declared is a function nobody reviewed; add it to \
                     the manifest or remove the module."
                ));
            }
        }
    }

    let package = Package { manifest, entries };
    let bytes = package.write(&key_for_signing(&flags));
    std::fs::write(out, &bytes).map_err(|e| format!("{out}: {e}"))?;

    println!(
        "packaged {} ({} entries, {} bytes)\n  sha256:{}",
        package.manifest["id"].as_str().unwrap_or("?"),
        package.entries.len(),
        bytes.len(),
        elpian_crypto::hex(&elpian_crypto::sha256(&bytes))
    );
    Ok(())
}

// ---- inspect / verify ------------------------------------------------------

fn cmd_inspect(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let path = flags
        .positional
        .first()
        .ok_or("inspect needs a package path")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    let index = Package::inspect_unverified(&bytes).map_err(|e| e.message())?;
    println!(
        "{}",
        serde_json::to_string_pretty(&index).unwrap_or_default()
    );
    // Said plainly, because the whole point of this command is that it runs on
    // a package you have not decided to trust yet.
    eprintln!("\nnote: this index was NOT verified. Run `verify --key K` before installing.");
    Ok(())
}

fn cmd_verify(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let path = flags
        .positional
        .first()
        .ok_or("verify needs a package path")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    let package = Package::read(&bytes, &key_for_verifying(&flags)?).map_err(|e| e.message())?;
    println!(
        "ok: {} {} — {} entries verified",
        package.manifest["id"].as_str().unwrap_or("?"),
        package.manifest["version"].as_str().unwrap_or("?"),
        package.entries.len()
    );
    Ok(())
}

// ---- install ---------------------------------------------------------------

fn cmd_install(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let path = flags
        .positional
        .first()
        .ok_or("install needs a package path")?;
    let registry = flags
        .get("registry")
        .ok_or("install needs --registry <dir>")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    // Verified *before* anything is written. An install that unpacked first and
    // checked afterwards would leave a rejected package's bytes in the registry.
    let package = Package::read(&bytes, &key_for_verifying(&flags)?).map_err(|e| e.message())?;

    let id = package.manifest["id"]
        .as_str()
        .ok_or("the manifest has no id")?
        .to_string();
    if !elpian_host::app::valid_app_id(&id) {
        return Err(format!("{id:?} is not a valid app id; refusing to install"));
    }
    let version = package.manifest["version"]
        .as_str()
        .unwrap_or("0.0.0")
        .to_string();

    // Into the content-addressed store. Blobs are shared between versions, so
    // installing a version that changed one function costs one function.
    let store = RegistryStore::open(&registry).map_err(|e| e.message())?;

    let mut client = None;
    let mut functions = std::collections::BTreeMap::new();
    let declared_kinds: std::collections::BTreeMap<String, String> = package.manifest["functions"]
        .as_array()
        .map(|entries| {
            entries
                .iter()
                .filter_map(|entry| {
                    let name = entry["name"].as_str()?.to_string();
                    let kind = entry["kind"].as_str().unwrap_or("action").to_string();
                    Some((name, kind))
                })
                .collect()
        })
        .unwrap_or_default();

    for entry in &package.entries {
        let address = store.put_blob(&entry.data).map_err(|e| e.message())?;
        match entry.name.strip_prefix("fn/") {
            Some(name) => {
                let kind = declared_kinds
                    .get(name)
                    .cloned()
                    .unwrap_or_else(|| "action".to_string());
                functions.insert(name.to_string(), (kind, address));
            }
            None if entry.name == "client" => client = Some(address),
            None => {}
        }
    }

    let record = VersionRecord {
        version: version.clone(),
        client,
        functions,
        capabilities: string_list(&package.manifest["capabilities"]),
        secrets: string_list(&package.manifest["secrets"]),
        network: package.manifest["network"].clone(),
        limits: package.manifest["limits"].clone(),
        installed_at: now_millis(),
    };
    store.install(&id, record).map_err(|e| e.message())?;

    println!(
        "installed {id} {version} into {registry}\n  {} entries, content-addressed",
        package.entries.len()
    );

    // Installing is not deploying. An operator can stage a version and cut over
    // separately — which is the whole reason the two are different verbs.
    if flags.has("deploy") {
        let force = flags.has("force");
        store
            .deploy(&id, &version, force)
            .map_err(|e| e.message())?;
        println!("  deployed: {id} is now serving {version}");
    } else {
        let serving = store
            .active_version(&id)
            .map(|v| v.version)
            .unwrap_or_else(|| "nothing".into());
        println!("  not deployed — {id} is still serving {serving}");
        println!("  deploy it with: elpian-pkg install ... --deploy");
    }
    Ok(())
}

fn string_list(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}
