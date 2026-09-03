//! `elpian-pkg` — build, inspect, verify and install Elpian packages.
//!
//! This is the packaging half of the `elpian` CLI, kept as its own binary so
//! the package format has no dependency on the rest of the toolchain and can be
//! used by a build system that has nothing else.
//!
//! ```text
//! elpian-pkg package <project-dir> <out.elpianpkg> [--key K]
//! elpian-pkg inspect <package>                       # no key needed
//! elpian-pkg verify  <package> --key K
//! elpian-pkg install <package> --registry DIR --key K [--deploy]
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

use elpian_pkg::{Entry, Package};
use serde_json::{json, Value};

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
     elpian-pkg package <project-dir> <out.elpianpkg> [--key K]\n  \
     elpian-pkg inspect <package>\n  \
     elpian-pkg verify  <package> --key K\n  \
     elpian-pkg install <package> --registry DIR --key K [--deploy]\n\n\
     --key may also be given as ELPIAN_SIGNING_KEY in the environment."
        .into()
}

/// Read `--key`, falling back to the environment.
///
/// An unsigned package is not a supported state: the container always carries a
/// signature, and a build with no key configured gets a well-known development
/// key with a warning. Making "no signature" representable would mean every
/// verifier needed a branch for it, and that branch is the one that gets
/// reached by accident in production.
fn signing_key(flags: &Flags) -> Vec<u8> {
    if let Some(key) = flags.get("key") {
        return key.into_bytes();
    }
    if let Ok(key) = std::env::var("ELPIAN_SIGNING_KEY") {
        return key.into_bytes();
    }
    eprintln!(
        "elpian-pkg: warning: no --key and no ELPIAN_SIGNING_KEY; using the \
         development key. Packages signed with it are not distributable."
    );
    b"elpian-development-key".to_vec()
}

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

fn cmd_package(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let (Some(project), Some(out)) = (flags.positional.first(), flags.positional.get(1)) else {
        return Err(format!("package needs a project dir and an output path\n\n{}", usage()));
    };
    let project = Path::new(project);

    let manifest_path = project.join("elpian.app.json");
    let manifest: Value = serde_json::from_str(
        &std::fs::read_to_string(&manifest_path)
            .map_err(|e| format!("{}: {e}", manifest_path.display()))?,
    )
    .map_err(|e| format!("elpian.app.json is not valid JSON: {e}"))?;

    let declared = manifest["functions"]
        .as_array()
        .ok_or("elpian.app.json has no \"functions\" array")?;

    let build = project.join("build");
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
        for file in std::fs::read_dir(&fn_dir).map_err(|e| e.to_string())?.flatten() {
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

    let package = Package {
        manifest,
        entries,
    };
    let bytes = package.write(&signing_key(&flags));
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
    let path = flags.positional.first().ok_or("inspect needs a package path")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    let index = Package::inspect_unverified(&bytes).map_err(|e| e.message())?;
    println!("{}", serde_json::to_string_pretty(&index).unwrap_or_default());
    // Said plainly, because the whole point of this command is that it runs on
    // a package you have not decided to trust yet.
    eprintln!("\nnote: this index was NOT verified. Run `verify --key K` before installing.");
    Ok(())
}

fn cmd_verify(args: &[String]) -> Result<(), String> {
    let flags = Flags::parse(args);
    let path = flags.positional.first().ok_or("verify needs a package path")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    let package = Package::read(&bytes, &signing_key(&flags)).map_err(|e| e.message())?;
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
    let path = flags.positional.first().ok_or("install needs a package path")?;
    let registry = flags
        .get("registry")
        .ok_or("install needs --registry <dir>")?;
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;

    // Verified *before* anything is written. An install that unpacked first and
    // checked afterwards would leave a rejected package's bytes in the registry.
    let package = Package::read(&bytes, &signing_key(&flags)).map_err(|e| e.message())?;

    let id = package.manifest["id"]
        .as_str()
        .ok_or("the manifest has no id")?
        .to_string();
    let version = package.manifest["version"].as_str().unwrap_or("0.0.0").to_string();

    let root = PathBuf::from(&registry).join(&id);
    std::fs::create_dir_all(root.join("fn")).map_err(|e| format!("{}: {e}", root.display()))?;

    for entry in &package.entries {
        let target = match entry.name.strip_prefix("fn/") {
            Some(name) => root.join("fn").join(format!("{name}.bc")),
            None if entry.name == "client" => root.join("client.bc"),
            None => continue,
        };
        std::fs::write(&target, &entry.data).map_err(|e| format!("{}: {e}", target.display()))?;
    }

    // `app.json` is the manifest as packaged. Writing it verbatim rather than
    // rebuilding it means the file the server reads is the file that was signed.
    let app_json = root.join("app.json");
    std::fs::write(
        &app_json,
        serde_json::to_string_pretty(&package.manifest).unwrap_or_default(),
    )
    .map_err(|e| format!("{}: {e}", app_json.display()))?;

    println!(
        "installed {id} {version} into {}\n  {} entries",
        root.display(),
        package.entries.len()
    );
    if flags.has("deploy") {
        println!("  (elpiand serves whatever is in the registry directory; restart or reload it)");
    }
    let _ = json!({});
    Ok(())
}
