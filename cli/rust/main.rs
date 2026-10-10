use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Parser, Subcommand, ValueEnum};
use notify::{EventKind, RecursiveMode, Watcher};
use oxc_allocator::Allocator;
use oxc_codegen::Codegen;
use oxc_parser::Parser as OxcParser;
use oxc_semantic::SemanticBuilder;
use oxc_span::SourceType;
use oxc_transformer::{TransformOptions, Transformer};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    collections::{BTreeMap, HashSet},
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc,
};
use walkdir::WalkDir;

#[derive(Parser)]
#[command(
    name = "elpian",
    version,
    about = "Native Rust toolchain for Elpian projects"
)]
struct Cli {
    #[command(subcommand)]
    command: CommandName,
}

#[derive(Subcommand)]
enum CommandName {
    Create(CreateArgs),
    Run {
        #[command(subcommand)]
        task: RunTask,
    },
    /// Build this project into a signed `.elpianpkg`.
    Package(PackageArgs),
    /// Install a `.elpianpkg` into a host's registry.
    Install(InstallArgs),
    /// Serve a registry of installed mini apps.
    Serve(ServeArgs),
}

#[derive(Args)]
struct PackageArgs {
    /// Where to write the package. Defaults to `<id>-<version>.elpianpkg`.
    #[arg(short, long)]
    out: Option<PathBuf>,
    /// Signing key. Falls back to ELPIAN_SIGNING_KEY, then a development key.
    #[arg(short, long)]
    key: Option<String>,
    /// Package what is already in `build/` rather than building first.
    ///
    /// A flag rather than `--build=false`: a boolean flag that defaults to true
    /// cannot be turned off on the command line, which is a small trap the
    /// negative name avoids.
    #[arg(long)]
    no_build: bool,
}

#[derive(Args)]
struct InstallArgs {
    /// The package to install.
    package: PathBuf,
    /// The host's registry directory.
    #[arg(short, long)]
    registry: PathBuf,
    /// Signing key to verify against. There is no default for verification.
    #[arg(short, long)]
    key: Option<String>,
    /// Serve this version immediately, rather than only staging it.
    #[arg(long)]
    deploy: bool,
    /// Deploy even if it is older than what is being served.
    #[arg(long)]
    force: bool,
}

#[derive(Args)]
struct ServeArgs {
    /// The registry directory to serve.
    #[arg(short, long)]
    registry: PathBuf,
    #[arg(short = 'H', long, default_value = "127.0.0.1")]
    host: String,
    #[arg(short, long, default_value_t = 4180)]
    port: u16,
    /// Where apps' private filesystems and meters live.
    #[arg(long)]
    data_root: Option<PathBuf>,
}

#[derive(Args)]
struct CreateArgs {
    directory: PathBuf,
    /// Which host renders the app on the web: the Flutter engine or the
    /// native DOM host (@elpian/web). Recorded in `elpian.config.json`.
    #[arg(long, value_enum, default_value_t = Renderer::Flutter)]
    renderer: Renderer,
    #[arg(short, long, value_enum, default_value_t = Template::Client)]
    template: Template,
}

#[derive(Clone, Copy, ValueEnum)]
enum Template {
    Client,
    Server,
    Fullstack,
    /// A mini app with both halves and a **closed** network posture: its client
    /// can reach its own server functions and nothing else, and its server
    /// functions can reach nothing at all. The posture you want unless you have
    /// a reason not to.
    ClosedFullstack,
    Showcase,
    /// A fullstack mini app whose backend is partly an **agent**: declared in
    /// the manifest with instructions, skills and the app's own server
    /// function as a tool, producing A2UI that the client renders next to its
    /// static UI. Runs offline with `ELPIAN_AGENT_PROVIDER=scripted`.
    Agentic,
}

#[derive(Subcommand)]
enum RunTask {
    Install,
    Build {
        #[arg(short, long, value_enum)]
        mode: Option<Mode>,
        /// Override `renderer` from `elpian.config.json`.
        #[arg(long, value_enum)]
        renderer: Option<Renderer>,
    },
    Dev {
        #[arg(short = 'H', long, default_value = "127.0.0.1")]
        host: String,
        #[arg(short, long, default_value_t = 4173)]
        port: u16,
        #[arg(short, long, value_enum)]
        mode: Option<Mode>,
        #[arg(long)]
        build_engine: bool,
        /// Override `renderer` from `elpian.config.json`.
        #[arg(long, value_enum)]
        renderer: Option<Renderer>,
    },
}

/// The web host a project's client runs in. Both run the same `__elpian/`
/// manifest and the same client AST / bytecode on the Elpian VM; they differ
/// in what draws the UI.
#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, ValueEnum, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Renderer {
    /// The Flutter web engine (`cli/elpian_client`, built with `flutter build web`).
    #[default]
    Flutter,
    /// The native DOM host (`native/web`, `@elpian/web`), built with npm.
    Native,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, ValueEnum, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Mode {
    Js,
    Bytecode,
    Both,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    #[serde(default = "default_out")]
    out_dir: PathBuf,
    #[serde(default = "default_mode")]
    mode: Mode,
    #[serde(default)]
    renderer: Renderer,
    engine_dir: Option<PathBuf>,
    engine_project: Option<PathBuf>,
    #[serde(default = "default_base")]
    base_path: String,
    client: Option<Target>,
    server: Option<Target>,
}

#[derive(Clone, Debug, Deserialize)]
struct Target {
    entry: PathBuf,
}
fn default_out() -> PathBuf {
    "dist".into()
}
fn default_mode() -> Mode {
    Mode::Both
}
fn default_base() -> String {
    "/".into()
}

#[derive(Deserialize)]
struct ProjectSpec {
    #[allow(dead_code)]
    name: String,
    #[serde(default)]
    dependencies: BTreeMap<String, PackageRef>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum PackageRef {
    Path(String),
    Object { path: String },
}

#[derive(Deserialize)]
struct PackageSpec {
    name: String,
    entry: String,
}

#[derive(Clone)]
struct Artifact {
    target: &'static str,
    js: PathBuf,
    ast: PathBuf,
    bytecode: Option<PathBuf>,
}

fn main() {
    if let Err(error) = real_main() {
        eprintln!("elpian: {error:#}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        CommandName::Create(args) => create_project(
            &absolute(&env::current_dir()?, &args.directory),
            args.template,
            args.renderer,
        ),
        CommandName::Run { task } => {
            let root = env::current_dir()?;
            match task {
                RunTask::Install => {
                    println!("Installed {} Elpian package(s)", install(&root)?);
                    Ok(())
                }
                RunTask::Build { mode, renderer } => {
                    let mut config = load_config(&root)?;
                    if let Some(mode) = mode {
                        config.mode = mode;
                    }
                    if let Some(renderer) = renderer {
                        config.renderer = renderer;
                    }
                    for artifact in build_project(&root, &config, true)? {
                        println!(
                            "Built {}: {}",
                            artifact.target,
                            artifact
                                .bytecode
                                .as_ref()
                                .unwrap_or(&artifact.ast)
                                .display()
                        );
                    }
                    if config.client.is_some() {
                        println!(
                            "Deployable web app ({} renderer): {}/web",
                            renderer_name(config.renderer),
                            config.out_dir.display()
                        );
                    }
                    Ok(())
                }
                RunTask::Dev {
                    host,
                    port,
                    mode,
                    build_engine,
                    renderer,
                } => {
                    let mut config = load_config(&root)?;
                    if let Some(mode) = mode {
                        config.mode = mode;
                    }
                    if let Some(renderer) = renderer {
                        config.renderer = renderer;
                    }
                    dev(&root, config, &host, port, build_engine)
                }
            }
        }
        CommandName::Package(args) => package_project(&env::current_dir()?, args),
        CommandName::Install(args) => install_package(args),
        CommandName::Serve(args) => serve_registry(args),
    }
}

/// Run one of the workspace binaries, inheriting stdio.
///
/// The same shape `dev` already uses to run the host: the CLI drives the
/// workspace's tools rather than linking them, which keeps it buildable on its
/// own and means a tool and the CLI cannot drift into two versions of the same
/// logic.
fn run_workspace_bin(bin: &str, args: &[&str]) -> Result<()> {
    let manifest = workspace().join("rust/Cargo.toml");
    let status = Command::new("cargo")
        .args(["run", "--quiet", "--manifest-path"])
        .arg(manifest)
        .args(["--bin", bin, "--"])
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()?;
    if !status.success() {
        bail!("{bin} exited {status}");
    }
    Ok(())
}

fn package_project(root: &Path, args: PackageArgs) -> Result<()> {
    if !args.no_build {
        let config = load_config(root)?;
        build_project(root, &config, false)?;
    }

    // The package manifest is the project's own `elpian.app.json`, so the file
    // that describes the app to the host is the file the author edits — not one
    // the CLI invents at package time and nobody ever sees.
    let manifest_path = root.join("elpian.app.json");
    if !manifest_path.is_file() {
        bail!(
            "{} is missing. It declares the app's id, version, capabilities, \
             network posture and functions — see wiki/22-packaging.md",
            manifest_path.display()
        );
    }
    let manifest: serde_json::Value = read_json(&manifest_path)?;
    let id = manifest["id"].as_str().unwrap_or("app");
    let version = manifest["version"].as_str().unwrap_or("0.0.0");

    let out = args
        .out
        .unwrap_or_else(|| root.join(format!("{id}-{version}.elpianpkg")));

    // Where the build actually wrote. The packager must not assume: a project's
    // `outDir` is its own choice.
    let build_dir = load_config(root)
        .map(|config| absolute(root, &config.out_dir))
        .unwrap_or_else(|_| root.join("build"));

    let mut argv: Vec<String> = vec![
        "package".into(),
        root.display().to_string(),
        out.display().to_string(),
        "--build-dir".into(),
        build_dir.display().to_string(),
    ];
    if let Some(key) = &args.key {
        argv.push("--key".into());
        argv.push(key.clone());
    }
    run_workspace_bin(
        "elpian-pkg",
        &argv.iter().map(String::as_str).collect::<Vec<_>>(),
    )
}

fn install_package(args: InstallArgs) -> Result<()> {
    let mut argv: Vec<String> = vec![
        "install".into(),
        args.package.display().to_string(),
        "--registry".into(),
        args.registry.display().to_string(),
    ];
    if let Some(key) = &args.key {
        argv.push("--key".into());
        argv.push(key.clone());
    }
    if args.deploy {
        argv.push("--deploy".into());
    }
    if args.force {
        argv.push("--force".into());
    }
    run_workspace_bin(
        "elpian-pkg",
        &argv.iter().map(String::as_str).collect::<Vec<_>>(),
    )
}

fn serve_registry(args: ServeArgs) -> Result<()> {
    let mut argv: Vec<String> = vec![
        "--registry".into(),
        args.registry.display().to_string(),
        "--host".into(),
        args.host.clone(),
        "--port".into(),
        args.port.to_string(),
    ];
    if let Some(data_root) = &args.data_root {
        argv.push("--data-root".into());
        argv.push(data_root.display().to_string());
    }
    run_workspace_bin(
        "elpiand",
        &argv.iter().map(String::as_str).collect::<Vec<_>>(),
    )
}

fn load_config(root: &Path) -> Result<Config> {
    let file = root.join("elpian.config.json");
    let config: Config = serde_json::from_slice(
        &fs::read(&file).with_context(|| format!("cannot read {}", file.display()))?,
    )?;
    if config.client.is_none() && config.server.is_none() {
        bail!("configure a client or server target");
    }
    Ok(config)
}

fn install(root: &Path) -> Result<usize> {
    let spec: ProjectSpec = read_json(&root.join("elpian.json"))?;
    let packages = root.join(".elpian/packages");
    fs::create_dir_all(&packages)?;
    let mut lock = serde_json::Map::new();
    for (name, reference) in &spec.dependencies {
        validate_package_name(name)?;
        let declared = match reference {
            PackageRef::Path(path) | PackageRef::Object { path } => path,
        };
        let source = fs::canonicalize(root.join(declared))
            .with_context(|| format!("package {name} path {declared} does not exist"))?;
        let package: PackageSpec = read_json(&source.join("elpian.package.json"))?;
        if package.name != *name {
            bail!(
                "package {} declares name {}, expected {name}",
                source.display(),
                package.name
            );
        }
        if !source.join(&package.entry).is_file() {
            bail!("package {name} entry {} does not exist", package.entry);
        }
        let destination = packages.join(name);
        if let Ok(existing) = fs::read_link(&destination) {
            if fs::canonicalize(destination.parent().unwrap().join(existing))? != source {
                fs::remove_file(&destination)?;
            }
        } else if destination.exists() {
            bail!(
                "{} exists and is not a managed package link",
                destination.display()
            );
        }
        if !destination.exists() {
            fs::create_dir_all(destination.parent().unwrap())?;
            create_dir_link(&source, &destination)?;
        }
        lock.insert(name.clone(), json!({ "path": source }));
    }
    fs::create_dir_all(root.join(".elpian"))?;
    write_json(
        &root.join(".elpian/elpian.lock.json"),
        &json!({ "version": 1, "packages": lock }),
    )?;
    Ok(spec.dependencies.len())
}

#[cfg(unix)]
fn create_dir_link(source: &Path, destination: &Path) -> Result<()> {
    std::os::unix::fs::symlink(source, destination)?;
    Ok(())
}
#[cfg(windows)]
fn create_dir_link(source: &Path, destination: &Path) -> Result<()> {
    std::os::windows::fs::symlink_dir(source, destination)?;
    Ok(())
}

fn build_project(root: &Path, config: &Config, package_web: bool) -> Result<Vec<Artifact>> {
    let out = absolute(root, &config.out_dir);
    fs::create_dir_all(&out)?;
    let mut artifacts = Vec::new();
    for (name, target) in [
        ("client", config.client.as_ref()),
        ("server", config.server.as_ref()),
    ] {
        let Some(target) = target else { continue };
        let js = out.join(format!("{name}.elpian.js"));
        let ast = out.join(format!("{name}.elpian.ast.json"));
        let bytecode_path = out.join(format!("{name}.elpian.bc"));
        let mut seen = HashSet::new();
        let mut modules = Vec::new();
        bundle_module(
            root,
            &resolve_source(&absolute(root, &target.entry))?,
            &mut seen,
            &mut modules,
        )?;
        let source = modules.join("\n");
        fs::write(&js, &source)?;
        let ast_json = js2elpian::compile_js_to_ast(source.clone());
        let ast_value: serde_json::Value = serde_json::from_str(&ast_json)?;
        if let Some(error) = ast_value.get("error") {
            bail!("{name}: {error}");
        }
        fs::write(&ast, ast_json)?;
        let bytecode = if config.mode != Mode::Js {
            let bytes = js2elpian::compile_js_to_bytecode(&source)
                .ok_or_else(|| anyhow!("{name}: JavaScript is outside the Elpian subset"))?;
            fs::write(&bytecode_path, bytes)?;
            Some(bytecode_path)
        } else {
            None
        };
        artifacts.push(Artifact {
            target: name,
            js,
            ast,
            bytecode,
        });
    }
    let client = artifacts.iter().find(|item| item.target == "client");
    let manifest = json!({
        "version": 1,
        "client": client.map(|item| json!({
            "format": if item.bytecode.is_some() { "bytecode" } else { "ast" },
            "url": format!("__elpian/{}", item.bytecode.as_ref().unwrap_or(&item.ast).file_name().unwrap().to_string_lossy()),
            "sourceUrl": format!("__elpian/{}", item.js.file_name().unwrap().to_string_lossy())
        })),
        "server": config.server.as_ref().map(|_| json!({ "endpoint": "__elpian/api" })),
        // A mini app's id: the client addresses its agents (and server functions)
        // under `/apps/<app>/…` on the same origin.
        "app": app_id(root)
    });
    write_json(&out.join("elpian.manifest.json"), &manifest)?;

    // A mini app's server functions: one bytecode module each.
    build_server_functions(root, config, &out)?;

    if package_web && client.is_some() {
        package_web_export(root, config, &artifacts, &out)?;
    }
    Ok(artifacts)
}

/// The mini app id from `elpian.app.json`, when the project is a mini app.
fn app_id(root: &Path) -> Option<String> {
    let manifest: serde_json::Value = read_json(&root.join("elpian.app.json")).ok()?;
    manifest["id"].as_str().map(str::to_string)
}

/// Compile `src/server/{actions,components}/*` into `build/fn/<name>.bc`.
///
/// **One module per function, not one bundle.** That is what lets the host load
/// and unload them independently, which is the entire serverless requirement —
/// a single bundle would have to be resident whenever any one function was
/// called.
///
/// The *directory* says which kind a function is, and the manifest must agree.
/// A directory convention rather than a decorator because the language subset
/// has none, and because it can be read statically: the alternative is
/// evaluating guest code at build time to find a registration table, which is
/// worse in every way.
fn build_server_functions(root: &Path, config: &Config, out: &Path) -> Result<()> {
    let manifest_path = root.join("elpian.app.json");
    if !manifest_path.is_file() {
        return Ok(()); // not a mini app
    }
    let manifest: serde_json::Value = read_json(&manifest_path)?;

    // An agentic app's agents (instructions, skills, scripts) travel with the
    // build output, which is the layout `elpian package` and the host read.
    let agents_out = out.join("agents");
    if agents_out.exists() {
        fs::remove_dir_all(&agents_out)?;
    }
    if root.join("agents").is_dir() {
        copy_tree(&root.join("agents"), &agents_out)?;
    }
    fs::copy(&manifest_path, out.join("elpian.app.json"))?;

    let declared: Vec<(String, String)> = manifest["functions"]
        .as_array()
        .map(|entries| {
            entries
                .iter()
                .filter_map(|e| {
                    Some((
                        e["name"].as_str()?.to_string(),
                        e["kind"].as_str().unwrap_or("action").to_string(),
                    ))
                })
                .collect()
        })
        .unwrap_or_default();
    if declared.is_empty() {
        return Ok(());
    }

    let fn_dir = out.join("fn");
    fs::create_dir_all(&fn_dir)?;

    // The server SDK is prepended to every function module. Each is compiled
    // alone, so each needs its own copy of the vocabulary — that is the cost of
    // independent load and unload, and it is paid in bytes rather than in
    // coupling.
    let sdk =
        fs::read_to_string(workspace().join("guest-sdk/js/elpian-server.js")).unwrap_or_default();

    for (name, kind) in &declared {
        let dir = match kind.as_str() {
            "component" => "components",
            _ => "actions",
        };
        let source_path = ["ts", "js"]
            .iter()
            .map(|ext| root.join(format!("src/server/{dir}/{name}.{ext}")))
            .find(|p| p.is_file())
            .ok_or_else(|| {
                anyhow!(
                    "{name} is declared as a {kind} in elpian.app.json but \
                     src/server/{dir}/{name}.ts does not exist"
                )
            })?;

        let mut seen = HashSet::new();
        let mut modules = Vec::new();
        bundle_module(root, &source_path, &mut seen, &mut modules)?;
        let source = format!("{sdk}\n{}", modules.join("\n"));

        let bytes = js2elpian::compile_js_to_bytecode(&source)
            .ok_or_else(|| anyhow!("{name}: JavaScript is outside the Elpian subset"))?;
        fs::write(fn_dir.join(format!("{name}.bc")), bytes)?;
    }

    // The client half is what a device fetches, under the name the host serves
    // it as.
    if config.client.is_some() {
        let built = out.join("client.elpian.bc");
        if built.is_file() {
            fs::copy(&built, out.join("client.bc"))?;
        }
    }

    // `elpian.app.json` is copied beside the modules so the build output *is*
    // the layout `elpian package` and the host both read.
    fs::copy(&manifest_path, out.join("elpian.app.json"))?;
    println!("Built {} server function(s)", declared.len());
    Ok(())
}

fn bundle_module(
    root: &Path,
    file: &Path,
    seen: &mut HashSet<PathBuf>,
    output: &mut Vec<String>,
) -> Result<()> {
    let file = fs::canonicalize(file)?;
    if !seen.insert(file.clone()) {
        return Ok(());
    }
    let source = fs::read_to_string(&file)?;
    let import_re =
        Regex::new(r#"(?ms)^\s*import\s+(?:[\s\S]*?\s+from\s+)?[\"']([^\"']+)[\"']\s*;?"#)?;
    for capture in import_re.captures_iter(&source) {
        let dependency = resolve_import(root, &file, &capture[1])?;
        bundle_module(root, &dependency, seen, output)?;
    }
    let transformed = transpile_typescript(&file, &source)?;
    let without_imports = import_re.replace_all(&transformed, "");
    let export_decl =
        Regex::new(r"(?m)^\s*export\s+((?:async\s+)?(?:function|class|const|let|var)\b)")?;
    let export_list = Regex::new(r"(?ms)^\s*export\s*\{.*?\}\s*;?")?;
    let cleaned = export_list
        .replace_all(&export_decl.replace_all(&without_imports, "$1"), "")
        .to_string();
    output.push(format!(
        "// {}\n{}",
        file.strip_prefix(root).unwrap_or(&file).display(),
        cleaned
    ));
    Ok(())
}

fn transpile_typescript(path: &Path, source: &str) -> Result<String> {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(path)
        .map_err(|_| anyhow!("unsupported source type: {}", path.display()))?;
    let parsed = OxcParser::new(&allocator, source, source_type).parse();
    if !parsed.diagnostics.is_empty() {
        bail!(
            "TypeScript parse failed in {}: {}",
            path.display(),
            parsed.diagnostics[0]
                .clone()
                .render_with_source_code(source.to_string())
        );
    }
    let mut program = parsed.program;
    let semantic = SemanticBuilder::new()
        .with_excess_capacity(2.0)
        .with_enum_eval(true)
        .build(&program);
    if !semantic.diagnostics.is_empty() {
        bail!("TypeScript semantics failed in {}", path.display());
    }
    let transformed = Transformer::new(&allocator, path, &TransformOptions::default())
        .build_with_scoping(semantic.semantic.into_scoping(), &mut program);
    if !transformed.diagnostics.is_empty() {
        bail!("TypeScript transform failed in {}", path.display());
    }
    Ok(Codegen::new().build(&program).code)
}

fn resolve_import(root: &Path, importer: &Path, specifier: &str) -> Result<PathBuf> {
    if specifier.starts_with('.') {
        return resolve_source(&importer.parent().unwrap().join(specifier));
    }
    let parts: Vec<_> = specifier.split('/').collect();
    let package_name = if specifier.starts_with('@') {
        parts[..2].join("/")
    } else {
        parts[0].to_string()
    };
    let package_dir = root.join(".elpian/packages").join(&package_name);
    let package: PackageSpec = read_json(&package_dir.join("elpian.package.json"))?;
    let subpath = specifier
        .strip_prefix(&package_name)
        .unwrap()
        .trim_start_matches('/');
    resolve_source(&package_dir.join(if subpath.is_empty() {
        &package.entry
    } else {
        subpath
    }))
    .with_context(|| format!("cannot resolve Elpian package {specifier}; run `elpian run install`"))
}

fn resolve_source(path: &Path) -> Result<PathBuf> {
    let candidates = [
        path.to_path_buf(),
        path.with_extension("ts"),
        path.with_extension("tsx"),
        path.with_extension("js"),
        path.join("index.ts"),
    ];
    candidates
        .into_iter()
        .find(|item| item.is_file())
        .ok_or_else(|| anyhow!("source file not found: {}", path.display()))
}

fn renderer_name(renderer: Renderer) -> &'static str {
    match renderer {
        Renderer::Flutter => "flutter",
        Renderer::Native => "native",
    }
}

/// The web root the project's client is served from: `engineDir` when set,
/// otherwise the configured renderer's host, built (or refreshed) for the
/// project's base path.
fn resolve_engine(root: &Path, config: &Config, force: bool) -> Result<PathBuf> {
    if let Some(dir) = config.engine_dir.as_ref() {
        return Ok(absolute(root, dir));
    }
    let base = normalize_base(&config.base_path);
    match config.renderer {
        Renderer::Flutter => {
            let engine_project = config
                .engine_project
                .as_ref()
                .map(|value| absolute(root, value))
                .unwrap_or_else(|| cli_root().join("elpian_client"));
            ensure_engine(&engine_project, &base, force)
        }
        Renderer::Native => ensure_native_engine(&base, force),
    }
}

/// Stage the native DOM host (`native/web`) as a web root for `base`.
///
/// `@elpian/web` is built once with npm (`npm ci` in `native/`, then the
/// package's build, which bundles `dist/elpian-web.js` and copies the fonts and
/// the Elpian VM / QuickJS runtime files into `assets/`). The staged root adds
/// an `index.html` that fetches the same `__elpian/elpian.manifest.json` the
/// Flutter shell reads and mounts the client as a `miniapp` session on the
/// Elpian VM. Like the Flutter engine it is keyed by base path.
fn ensure_native_engine(base: &str, force: bool) -> Result<PathBuf> {
    let native = workspace().join("native");
    let web = native.join("web");
    if !web.join("package.json").is_file() {
        bail!("the native web host is missing at {}", web.display());
    }
    let bundle = web.join("dist/elpian-web.js");
    if force
        || !bundle.is_file()
        || !web.join("assets/runtime").is_dir()
        || native_host_stale(&web, &bundle)?
    {
        if !native.join("node_modules").is_dir() {
            run_checked(Command::new(npm()).current_dir(&native).args([
                "ci",
                "--no-audit",
                "--no-fund",
            ]))
            .context("installing the native web host's npm dependencies")?;
        }
        run_checked(Command::new(npm()).current_dir(&web).args(["run", "build"]))
            .context("building the native web host (@elpian/web)")?;
    }
    let slug: String = base
        .trim_matches('/')
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    let engine = web.join("build/elpian-engine").join(if slug.is_empty() {
        "root".to_string()
    } else {
        slug
    });
    if engine.exists() {
        fs::remove_dir_all(&engine)?;
    }
    fs::create_dir_all(&engine)?;
    for file in ["elpian-web.js", "elpian-web.js.map"] {
        let source = web.join("dist").join(file);
        if source.is_file() {
            fs::copy(&source, engine.join(file))?;
        }
    }
    copy_tree(&web.join("assets"), &engine.join("assets"))?;
    fs::write(
        engine.join("index.html"),
        NATIVE_INDEX_HTML.replace("{{BASE}}", base),
    )?;
    Ok(engine)
}

/// Whether any `native/web/src` file is newer than the built bundle.
fn native_host_stale(web: &Path, bundle: &Path) -> Result<bool> {
    let built = fs::metadata(bundle)?.modified()?;
    for entry in WalkDir::new(web.join("src")) {
        let entry = entry?;
        if entry.file_type().is_file() && entry.metadata()?.modified()? > built {
            return Ok(true);
        }
    }
    Ok(false)
}

fn npm() -> &'static str {
    if cfg!(windows) { "npm.cmd" } else { "npm" }
}

/// The native renderer's page: the counterpart of `cli/elpian_client`'s
/// `main.dart` — fetch the manifest, download the client AST / bytecode and
/// run it on the Elpian VM, rendered by the DOM host.
const NATIVE_INDEX_HTML: &str = r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <base href="{{BASE}}">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Elpian</title>
  <style>
    /* The host follows the system light/dark preference (its viewport's darkMode); the page does too. */
    :root { color-scheme: light dark; }
    html, body { margin: 0; height: 100%; background: Canvas; color: CanvasText; font-family: system-ui, sans-serif; }
    #app { position: fixed; inset: 0; }
    .elpian-status { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; text-align: center; padding: 32px; box-sizing: border-box; }
    .elpian-status h1 { font-size: 24px; margin: 0 0 12px; }
    .elpian-status pre { white-space: pre-wrap; max-width: 720px; margin: 0 auto 24px; user-select: text; }
    .elpian-status button { font: inherit; padding: 10px 24px; border-radius: 20px; border: 0; background: #6750a4; color: #fff; cursor: pointer; }
  </style>
</head>
<body>
  <div id="app"></div>
  <script type="module">
    import { installElpian, mountElpian } from './elpian-web.js';

    installElpian({ assetBase: new URL('assets/', document.baseURI).href });
    const app = document.getElementById('app');
    let session = null;

    function status(html) {
      let el = document.querySelector('.elpian-status');
      if (!html) { el?.remove(); return; }
      if (!el) { el = document.createElement('div'); el.className = 'elpian-status'; document.body.appendChild(el); }
      el.innerHTML = html;
      return el;
    }

    function failure(message) {
      const el = status('<div><h1>Elpian client could not start</h1><pre></pre><button>Retry</button></div>');
      el.querySelector('pre').textContent = message;
      el.querySelector('button').onclick = start;
    }

    async function fetchOk(url) {
      const res = await fetch(url, { cache: 'no-store' });
      if (!res.ok) throw new Error(`GET ${url} returned HTTP ${res.status}`);
      return res;
    }

    function base64(bytes) {
      let bin = '';
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(bin);
    }

    async function start() {
      status('<div>Loading…</div>');
      try {
        await session?.close();
        session = null;
        const nonce = Date.now();
        const manifest = await (await fetchOk(new URL(`__elpian/elpian.manifest.json?v=${nonce}`, document.baseURI))).json();
        const client = manifest?.client;
        if (!client || (client.format !== 'bytecode' && client.format !== 'ast') || typeof client.url !== 'string') {
          throw new Error('Elpian manifest has no valid client target');
        }
        const res = await fetchOk(new URL(`${client.url}?v=${nonce}`, document.baseURI));
        const bytes = new Uint8Array(await res.arrayBuffer());
        if (!bytes.length) throw new Error('Elpian client artifact is empty');
        const options = { machineId: 'elpian-dynamic-client', runtime: 'elpian' };
        // A mini app's agents and functions are served by the same host, under /apps/<id>/.
        if (typeof manifest.app === 'string') {
          options.appId = manifest.app;
          options.baseUrl = new URL('.', document.baseURI).href;
        }
        if (client.format === 'bytecode') options.bytecodeBase64 = base64(bytes);
        else options.astJson = new TextDecoder().decode(bytes);
        status(null);
        session = await mountElpian(app, 'miniapp', options);
      } catch (e) {
        failure(String(e instanceof Error ? e.message : e));
      }
    }

    start();
  </script>
</body>
</html>
"#;

/// Where the built Flutter engine for `base` lives.
///
/// Keyed by base path on purpose. `flutter build web` writes to `build/web`, so
/// a single shared directory meant that building any project re-based the engine
/// out from under every other project — the previous one then requested its
/// assets at the domain root and rendered a blank page, with nothing in the app
/// to indicate why. Giving each base path its own directory lets them coexist,
/// and makes switching between them a cache hit rather than a rebuild.
fn engine_dir_for(engine_project: &Path, base: &str) -> PathBuf {
    let slug: String = base
        .trim_matches('/')
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    let slug = if slug.is_empty() {
        "root".to_string()
    } else {
        slug
    };
    engine_project.join("build/elpian-engine").join(slug)
}

/// Build the engine for `base` if the cached one is stale. Returns its directory.
fn ensure_engine(engine_project: &Path, base: &str, force: bool) -> Result<PathBuf> {
    let engine = engine_dir_for(engine_project, base);
    let marker = engine.join(".elpian_runtime");
    if force || runtime_stale(engine_project, &marker, base)? {
        fs::create_dir_all(&engine)?;
        run_checked(Command::new("flutter").current_dir(engine_project).args([
            "build",
            "web",
            "--base-href",
            base,
            "--output",
            &engine.to_string_lossy(),
        ]))?;
        fs::write(
            &marker,
            format!("elpian_client/lib/main.dart\nbasePath={base}\n"),
        )?;
    }
    Ok(engine)
}

fn package_web_export(
    root: &Path,
    config: &Config,
    artifacts: &[Artifact],
    out: &Path,
) -> Result<()> {
    let engine = resolve_engine(root, config, false)?;
    if !engine.join("index.html").is_file() {
        bail!(
            "{} web host missing at {}",
            renderer_name(config.renderer),
            engine.display()
        );
    }
    let web = out.join("web");
    if web.exists() {
        fs::remove_dir_all(&web)?;
    }
    copy_tree(&engine, &web)?;
    let guest = web.join("__elpian");
    fs::create_dir_all(&guest)?;
    fs::copy(
        out.join("elpian.manifest.json"),
        guest.join("elpian.manifest.json"),
    )?;
    for item in artifacts {
        for file in [&item.js, &item.ast]
            .into_iter()
            .chain(item.bytecode.iter())
        {
            fs::copy(file, guest.join(file.file_name().unwrap()))?;
        }
    }
    disable_service_worker(&web)?;
    Ok(())
}

fn dev(root: &Path, config: Config, host: &str, port: u16, force_engine: bool) -> Result<()> {
    build_project(root, &config, false)?;
    let engine = resolve_engine(root, &config, force_engine)?;
    println!(
        "[elpian] {} renderer: {}",
        renderer_name(config.renderer),
        engine.display()
    );
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |event| {
        if changed(&event) {
            let _ = tx.send(event);
        }
    })?;
    for path in [
        root.join("src"),
        root.join("agents"),
        root.join("packages"),
        root.join("elpian.app.json"),
        root.join("elpian.json"),
        root.join("elpian.config.json"),
    ] {
        if path.exists() {
            watcher.watch(
                &path,
                if path.is_dir() {
                    RecursiveMode::Recursive
                } else {
                    RecursiveMode::NonRecursive
                },
            )?;
        }
    }
    let rebuild_root = root.to_path_buf();
    let rebuild_config = config.clone();
    std::thread::spawn(move || {
        while rx.recv().is_ok() {
            while rx.try_recv().is_ok() {}
            match build_project(&rebuild_root, &rebuild_config, false) {
                Ok(_) => println!("[elpian] rebuilt"),
                Err(error) => eprintln!("[elpian] build failed: {error:#}"),
            }
        }
    });
    let manifest = workspace().join("rust/Cargo.toml");
    let out = absolute(root, &config.out_dir);
    let mut command = Command::new("cargo");
    command
        .current_dir(root)
        .args(["run", "--quiet", "--manifest-path"])
        .arg(manifest)
        // `elpiand` replaced the old `elpian-server`. The dev server is now a
        // case of the real host rather than a second implementation of it: the
        // thing you develop against is the thing that ships, so a difference
        // between them cannot hide until deployment.
        .args([
            "--bin",
            "elpiand",
            "--",
            "--host",
            host,
            "--port",
            &port.to_string(),
            "--web-root",
        ])
        .arg(&engine)
        .arg("--artifact-root")
        .arg(&out);
    // The build output doubles as the registry: `elpian.app.json` plus
    // `fn/<name>.bc` under it is exactly the layout the host reads, so a
    // project that declares server functions is served without a separate
    // install step.
    if out.join("elpian.app.json").is_file() || out.join("index.json").is_file() {
        command.arg("--registry").arg(&out);
    }
    // Development: an app's declared secrets (ANTHROPIC_API_KEY,
    // OPENAI_API_KEY, …) are read from this environment, which the host
    // inherits — as are ELPIAN_AGENT_PROVIDER=scripted and
    // ELPIAN_AGENT_SCRIPT for running agents offline.
    command.arg("--dev");
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    let status = command.status()?;
    if !status.success() {
        bail!("Elpian Rust server exited {status}");
    }
    Ok(())
}

fn create_project(root: &Path, template: Template, renderer: Renderer) -> Result<()> {
    if root.exists() {
        bail!("{} already exists", root.display());
    }
    fs::create_dir_all(root.join("src"))?;
    let client = !matches!(template, Template::Server);
    let server = matches!(
        template,
        Template::Server | Template::Fullstack | Template::ClosedFullstack
    );
    let showcase = matches!(template, Template::Showcase);
    let agentic = matches!(template, Template::Agentic);
    let mini_app = matches!(template, Template::ClosedFullstack | Template::Agentic);
    let name = root.file_name().unwrap().to_string_lossy();
    let dependencies = if client {
        json!({ "@elpian/sdk": { "path": "./packages/elpian-sdk" } })
    } else {
        json!({})
    };
    write_json(
        &root.join("elpian.json"),
        &json!({ "name": name, "spec": 1, "dependencies": dependencies }),
    )?;
    write_json(
        &root.join("elpian.config.json"),
        &json!({
            "outDir": "dist", "mode": "both", "basePath": "/",
            "renderer": renderer_name(renderer),
            "client": client.then(|| json!({ "entry": "src/client.ts" })),
            // A mini app has no monolithic server entry: its server *is* the
            // per-function modules under `src/server/`, which `build_server_
            // functions` compiles one at a time. Declaring an entry here would
            // ask the build for a file the template deliberately does not have.
            "server": (server && !mini_app).then(|| json!({ "entry": "src/server.ts" }))
        }),
    )?;
    fs::write(
        root.join("tsconfig.json"),
        "{\n  \"compilerOptions\": { \"target\": \"ES2015\", \"strict\": true, \"module\": \"ESNext\" },\n  \"include\": [\"src\"]\n}\n",
    )?;
    fs::write(root.join(".gitignore"), "dist/\n.elpian/\n")?;
    let readme = if showcase {
        SHOWCASE_README.to_string()
    } else {
        format!("# {name}\n\nRun `elpian run install`, then `elpian run dev`.\n")
    };
    fs::write(root.join("README.md"), readme)?;
    if client {
        fs::write(
            root.join("src/client.ts"),
            if showcase {
                SHOWCASE_TEMPLATE
            } else if agentic {
                AGENTIC_CLIENT_TEMPLATE
            } else {
                CLIENT_TEMPLATE
            },
        )?;
        let sdk = root.join("packages/elpian-sdk");
        fs::create_dir_all(&sdk)?;
        write_json(
            &sdk.join("elpian.package.json"),
            &json!({ "name": "@elpian/sdk", "version": "0.1.0", "spec": 1, "entry": "index.ts" }),
        )?;
        fs::write(sdk.join("index.ts"), SDK_TEMPLATE)?;
    }
    if server && !mini_app {
        fs::write(root.join("src/server.ts"), SERVER_TEMPLATE)?;
    }
    if agentic {
        scaffold_agentic_app(root, &name)?;
    } else if mini_app {
        scaffold_mini_app(root, &name)?;
    }
    println!("Created {}", root.display());
    if agentic {
        println!(
            "  cd {} && elpian run install\n  \
             ELPIAN_AGENT_PROVIDER=scripted elpian run dev     # offline, canned agent\n  \
             ANTHROPIC_API_KEY=... elpian run dev              # the real agent",
            root.display()
        );
        return Ok(());
    }
    if mini_app {
        println!(
            "  elpian run build && elpian package && \\\n    elpian install <pkg> --registry ./registry --deploy && \\\n    elpian serve --registry ./registry"
        );
    }
    Ok(())
}

/// The extra files a mini app needs beyond a plain project: a manifest, and one
/// module per server function.
///
/// One module per function is not a style choice — it is what lets the host load
/// and unload them independently, which is the whole serverless requirement. A
/// single bundle would have to be resident whenever any one function was called.
fn scaffold_mini_app(root: &Path, name: &str) -> Result<()> {
    fs::create_dir_all(root.join("src/server/actions"))?;
    fs::create_dir_all(root.join("src/server/components"))?;

    write_json(
        &root.join("elpian.app.json"),
        &json!({
            "id": name.to_lowercase().replace('_', "-"),
            "version": "0.1.0",
            // Only what the sample below actually uses. A manifest that asks for
            // more than the code needs is how an app ends up over-privileged
            // without anybody deciding to.
            // `clock` is here because the sample action below calls `now()`.
            // A manifest that omits a capability the code uses does not fail
            // loudly — the call returns null and the bug shows up as a wrong
            // value much later, which is exactly how the reference sample was
            // first written.
            "capabilities": ["state", "logging", "clock"],
            // Anything unrecognised is closed, but saying it explicitly is the
            // point of this template.
            "network": "closed",
            "limits": { "instructions": 50_000_000u64, "memoryBytes": 33_554_432u64 },
            "functions": [
                { "name": "createNote", "kind": "action" },
                { "name": "NoteList", "kind": "component" }
            ]
        }),
    )?;

    fs::write(
        root.join("src/server/actions/createNote.ts"),
        MINI_APP_ACTION,
    )?;
    fs::write(
        root.join("src/server/components/NoteList.ts"),
        MINI_APP_COMPONENT,
    )?;
    fs::write(root.join("README.md"), mini_app_readme(name))?;
    Ok(())
}

/// The extra files an agentic mini app needs: a manifest declaring an agent,
/// its instructions and skills, a server function it uses as a tool, and a
/// script so it runs offline.
fn scaffold_agentic_app(root: &Path, name: &str) -> Result<()> {
    fs::create_dir_all(root.join("src/server/actions"))?;
    fs::create_dir_all(root.join("agents/skills/catalog"))?;
    fs::create_dir_all(root.join("agents/skills/ordering"))?;

    write_json(
        &root.join("elpian.app.json"),
        &json!({
            "id": name.to_lowercase().replace('_', "-"),
            "version": "0.1.0",
            // `render` and `server_call` for the client, `agents` for its
            // A2UISurface, `state`/`logging` for the server function.
            "capabilities": ["render", "server_call", "agents", "state", "logging"],
            "network": "closed",
            // The provider key is a declared secret: an operator supplies it
            // (`elpiand --secrets`), and `elpian run dev` reads it from the
            // environment. It is never sent to a client.
            "secrets": ["ANTHROPIC_API_KEY"],
            "limits": { "instructions": 50_000_000u64, "memoryBytes": 33_554_432u64 },
            "functions": [
                {
                    "name": "listProducts",
                    "kind": "action",
                    "description": "List the shop's products, optionally filtered by category.",
                    "params": {
                        "type": "object",
                        "properties": {
                            "category": { "type": "string", "enum": ["tea", "coffee"] }
                        },
                        "additionalProperties": false
                    }
                }
            ],
            "agents": [
                {
                    "name": "assistant",
                    "description": "Helps customers find and order products.",
                    "instructions": "agents/assistant.md",
                    "skills": ["catalog", "ordering"],
                    "tools": ["listProducts"],
                    "provider": "anthropic",
                    "model": "claude-opus-5-5",
                    "effort": "medium",
                    "maxTurns": 12,
                    "maxOutputTokens": 64000
                }
            ]
        }),
    )?;
    fs::write(
        root.join("src/server/actions/listProducts.ts"),
        AGENTIC_ACTION,
    )?;
    fs::write(root.join("agents/assistant.md"), AGENTIC_INSTRUCTIONS)?;
    fs::write(
        root.join("agents/skills/catalog/SKILL.md"),
        AGENTIC_SKILL_CATALOG,
    )?;
    fs::write(
        root.join("agents/skills/ordering/SKILL.md"),
        AGENTIC_SKILL_ORDERING,
    )?;
    fs::write(root.join("agents/scripted.json"), AGENTIC_SCRIPT)?;
    fs::write(root.join("README.md"), agentic_readme(name))?;
    Ok(())
}

fn agentic_readme(name: &str) -> String {
    format!(
        "# {name}\n\n\
         A fullstack mini app whose backend is partly an **agent**. The client\n\
         renders static Elpian UI and, next to it, an `A2UISurface` the agent\n\
         fills with A2UI v0.9.1.\n\n\
         ```text\n\
         elpian.app.json                     id, grants, posture, functions, agents\n\
         src/client.ts                       static UI + A2UISurface\n\
         src/server/actions/listProducts.ts  a server function, also the agent's tool\n\
         agents/assistant.md                 the agent's instructions\n\
         agents/skills/*/SKILL.md            skills it loads on demand\n\
         agents/scripted.json                canned turns for offline runs\n\
         ```\n\n\
         ## Run\n\n\
         ```bash\n\
         elpian run install\n\
         ELPIAN_AGENT_PROVIDER=scripted elpian run dev   # offline\n\
         ANTHROPIC_API_KEY=sk-... elpian run dev         # Claude\n\
         ```\n\n\
         The agent is served at `POST /apps/<id>/agent/assistant` as NDJSON. Its\n\
         tools are the app's own functions, called with the caller's identity and\n\
         counted against the app's quota. See `wiki/18-fullstack.md`.\n"
    )
}

fn mini_app_readme(name: &str) -> String {
    format!(
        "# {name}\n\n\
         A mini app with both halves and a **closed** network posture: the client\n\
         can reach its own server functions and nothing else, and the server\n\
         functions can reach nothing at all.\n\n\
         ```text\n\
         elpian.app.json                     id, grants, posture, functions\n\
         src/client.ts                       the client half\n\
         src/server/actions/createNote.ts    returns JSON, writes state\n\
         src/server/components/NoteList.ts   returns a UI payload\n\
         ```\n\n\
         ## Build, package, serve\n\n\
         ```bash\n\
         elpian run install\n\
         elpian run build\n\
         export ELPIAN_SIGNING_KEY=dev-key\n\
         elpian package\n\
         elpian install {name}-0.1.0.elpianpkg --registry ./registry --deploy\n\
         elpian serve --registry ./registry\n\
         ```\n\n\
         ## Things worth knowing\n\n\
         * A component **returns** its payload; it never calls `render`. That is\n\
           what makes it cacheable and testable without a host.\n\
         * Caching is opt-in: `ui(tree, [\"notes\"], 60)`. A component naming\n\
           neither a tag nor a TTL is never cached.\n\
         * Errors are **values**, not throws — the language subset has no\n\
           `try`/`catch`, so anything you must handle has to be returnable.\n\
         * `x == null` is true for `0`, so test `res.error != null` rather than\n\
           truthiness.\n\n\
         See `wiki/18-fullstack.md`.\n"
    )
}

fn changed(event: &notify::Result<notify::Event>) -> bool {
    // Reads count as inotify events, so a rebuild that opens the watched sources would retrigger itself.
    event
        .as_ref()
        .map(|item| !matches!(item.kind, EventKind::Access(_)))
        .unwrap_or(false)
}

fn runtime_stale(project: &Path, marker: &Path, base: &str) -> Result<bool> {
    if !marker.is_file() {
        return Ok(true);
    }
    if !fs::read_to_string(marker)?
        .lines()
        .any(|line| line.trim() == format!("basePath={base}"))
    {
        return Ok(true);
    }
    let built = fs::metadata(marker)?.modified()?;
    let ui = ui_package(project).unwrap_or_else(|| project.join(".."));
    for source in [
        project.join("lib/main.dart"),
        ui.join("lib/src/vm/elpian_vm_widget.dart"),
        ui.join("lib/src/vm/elpian_vm.dart"),
        ui.join("lib/src/vm/wasm_vm.dart"),
    ] {
        if source.is_file() && fs::metadata(source)?.modified()? > built {
            return Ok(true);
        }
    }
    Ok(false)
}

fn ui_package(project: &Path) -> Option<PathBuf> {
    let pubspec = fs::read_to_string(project.join("pubspec.yaml")).ok()?;
    let value = pubspec
        .lines()
        .skip_while(|line| line.trim_end() != "  elpian_ui:")
        .skip(1)
        .take_while(|line| line.starts_with("    "))
        .find_map(|line| line.trim().strip_prefix("path:"))?;
    Some(absolute(
        project,
        Path::new(value.trim().trim_matches(['"', '\''])),
    ))
}

fn disable_service_worker(web: &Path) -> Result<()> {
    let bootstrap = web.join("flutter_bootstrap.js");
    if bootstrap.is_file() {
        let source = fs::read_to_string(&bootstrap)?;
        let re = Regex::new(
            r"(?s)_flutter\.loader\.load\(\{\s*serviceWorkerSettings:.*?\}\s*\}\);?\s*$",
        )?;
        fs::write(
            bootstrap,
            re.replace(&source, "_flutter.loader.load();\n").as_bytes(),
        )?;
    }
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    for entry in WalkDir::new(source) {
        let entry = entry?;
        let relative = entry.path().strip_prefix(source)?;
        let target = destination.join(relative);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&target)?;
        } else {
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

fn normalize_base(value: &str) -> String {
    format!("/{}/", value.trim_matches('/')).replace("//", "/")
}
/// The CLI crate's directory — where the bundled `elpian_client` engine lives.
///
/// `CARGO_MANIFEST_DIR` is baked in at COMPILE time, so it goes stale the moment
/// the checkout is moved or renamed, and Cargo will not rebuild for that (no
/// source changed). The failure is a bare "No such file or directory" with no
/// hint of which path. So: trust the baked path only if it still contains the
/// engine project, otherwise recover it from the running executable, which is at
/// <cli>/target/<profile>/elpian.
fn cli_root() -> PathBuf {
    let baked = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    if baked.join("elpian_client").is_dir() {
        return baked;
    }
    if let Ok(exe) = env::current_exe() {
        // …/cli/target/release/elpian -> …/cli
        if let Some(dir) = exe
            .parent()
            .and_then(|p| p.parent())
            .and_then(|p| p.parent())
            && dir.join("elpian_client").is_dir()
        {
            return dir.to_path_buf();
        }
    }
    baked
}
/// The elpian repository root — the CLI crate now lives inside it.
fn workspace() -> PathBuf {
    cli_root().parent().unwrap().to_path_buf()
}
fn absolute(root: &Path, value: &Path) -> PathBuf {
    if value.is_absolute() {
        value.to_path_buf()
    } else {
        root.join(value)
    }
}
fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    Ok(serde_json::from_slice(&fs::read(path).with_context(
        || format!("cannot read {}", path.display()),
    )?)?)
}
fn write_json(path: &Path, value: &serde_json::Value) -> Result<()> {
    fs::write(path, format!("{}\n", serde_json::to_string_pretty(value)?))?;
    Ok(())
}
fn run_checked(command: &mut Command) -> Result<()> {
    let status = command.status()?;
    if !status.success() {
        bail!("command exited {status}");
    }
    Ok(())
}
fn validate_package_name(name: &str) -> Result<()> {
    if name.is_empty() || name.contains("..") || name.starts_with('/') || name.ends_with('/') {
        bail!("invalid package name: {name}");
    }
    Ok(())
}

const CLIENT_TEMPLATE: &str = r##"import { el, render } from '@elpian/sdk';

let count: number = 0;
let name: string = '';
const items: string[] = ['alpha', 'beta', 'gamma'];
let picked: string = '-';

function view() {
  return el('div', { style: { padding: '32', display: 'flex', flexDirection: 'column', gap: 12 } }, [
    el('h1', { text: 'Hello from TypeScript' }, []),
    el('p', { text: 'This UI is running as Elpian bytecode.' }, []),

    // Handlers are closures. They capture module state directly, so there is no
    // need for a top-level function per button.
    el('button', {
      key: 'inc',
      text: 'Count: ' + count,
      onClick: () => { count = count + 1; render(view()); },
    }, []),

    // The payoff: the closure captures the mapped item, so each row knows which
    // one it is. A named handler cannot — it would have to encode the identity
    // in the key and parse it back out of the event.
    el('ul', {}, items.map((item) =>
      el('li', {
        text: item,
        style: { cursor: 'pointer', padding: '6' },
        onClick: () => { picked = item; render(view()); },
      }, []))),
    el('p', { text: 'picked: ' + picked }, []),

    // Handlers receive the event. `value` carries an input's current text.
    el('input', {
      key: 'name',
      value: name,
      placeholder: 'your name',
      onInput: (event) => { name = '' + event.value; },
    }, []),
    el('button', {
      key: 'greet',
      text: 'Greet',
      onClick: () => { picked = name.length > 0 ? 'hello, ' + name : 'type a name first'; render(view()); },
    }, []),
  ]);
}

render(view());
"##;
const SERVER_TEMPLATE: &str = r#"export function hello(input: { name?: string }) {
  const name = input.name || 'world';
  return { message: 'Hello, ' + name + ', from the Elpian server VM!' };
}
"#;
const SDK_TEMPLATE: &str = r##"export type ElpianEvent = {
  type: string;
  target: string;
  currentTarget: string;
  value?: unknown;
  data?: unknown;
  [k: string]: unknown;
};
export type ElpianHandler = string | ((event: ElpianEvent) => void);
export type ElpianNode = {
  type: string;
  key?: string;
  props: Record<string, unknown>;
  events?: Record<string, string>;
  children?: ElpianNode[];
};

// ---------------------------------------------------------------------------
// Handler registry — what lets `onClick` take a closure.
//
// The host reads handlers from a top-level `events` map whose values must be
// STRINGS naming a VM function: it calls that function by name in a later turn.
// A closure cannot cross that seam — `render()` serialises the tree with
// JSON.stringify, which silently drops function values, leaving `events: {}`
// and a widget that renders perfectly and ignores every tap.
//
// So closures are kept on this side. Each node carrying one is given a stable
// key, its closures are stored under that key, and the wire gets the name of a
// single dispatcher. When the host fires an event it calls that dispatcher,
// which looks the closure back up by `currentTarget` (the element id, which is
// the node's key) and the event type.
// ---------------------------------------------------------------------------

const __handlers: Record<string, Record<string, (event: ElpianEvent) => void>> = {};
let __seq = 0;

/** The single VM function the host ever calls back for a closure handler. */
export function __elpianEvent(event: ElpianEvent): void {
  const byNode = __handlers['' + event.currentTarget];
  if (byNode == null) { return; }
  const fn = byNode[event.type];
  if (fn == null) { return; }
  fn(event);
}

export function el(
  type: string,
  props: Record<string, unknown>,
  children: ElpianNode[],
): ElpianNode {
  const rest: Record<string, unknown> = {};
  const events: Record<string, string> = {};
  const closures: Record<string, (event: ElpianEvent) => void> = {};
  let hasClosure = false;

  for (const name in props) {
    const value = props[name];
    if (name === 'key') { continue; }
    if (name.length > 2 && name.slice(0, 2) === 'on') {
      const event = name.slice(2).toLowerCase();
      if (typeof value === 'string') {
        // A named top-level function still works, unchanged.
        events[event] = value;
      } else if (typeof value === 'function') {
        closures[event] = value as (e: ElpianEvent) => void;
        hasClosure = true;
      }
      continue;
    }
    rest[name] = value;
  }

  // The element id the host reports as `currentTarget` is the node's key, so a
  // node with a closure must have one. An explicit key wins; otherwise take a
  // positional one, which is stable across renders because the counter resets
  // on every render().
  let key = props['key'];
  if (hasClosure && (key == null || key === '')) {
    key = '__el' + __seq;
    __seq = __seq + 1;
  }

  if (hasClosure) {
    __handlers['' + key] = closures;
    for (const event in closures) {
      events[event] = '__elpianEvent';
    }
  }

  const node: ElpianNode = { type: type, props: rest, events: events, children: children };
  if (key != null) { node.key = '' + key; }
  return node;
}

declare function askHost(name: string, payload: unknown): unknown;

// ---------------------------------------------------------------------------
// Agents. An `A2UISurface` node renders what one of this app's agents sends;
// `agentSend` talks to an agent from code. Both need the `agents` capability.
// ---------------------------------------------------------------------------

export type A2UISurfaceProps = {
  /** The agent's name in elpian.app.json. */
  agent: string;
  /** Optional: another app's id (defaults to this app). */
  app?: string;
  /** Optional: the server (defaults to the session's). */
  baseUrl?: string;
  /** Widgets with the same key share one conversation. */
  conversation?: string;
  /** A first message, sent when the surface mounts. */
  prompt?: string;
  /** Render only this A2UI surface (default: all, in creation order). */
  surfaceId?: string;
  /** Render the agent's prose. */
  showText?: boolean;
  /** Add an input row for messaging the agent. */
  chat?: boolean;
  /** Static A2UI messages, rendered without an agent. */
  messages?: unknown[];
  [k: string]: unknown;
};

/** A node that renders an agent's A2UI surfaces next to static UI. */
export function a2uiSurface(props: A2UISurfaceProps): ElpianNode {
  return el('A2UISurface', props, []);
}

/** Send `message` to `agent`; returns `{ conversationId }`. */
export function agentSend(agent: string, message: string, conversation?: string): unknown {
  return askHost('agent.send', [{ agent: agent, conversation: conversation, message: message }]);
}

/** Send an A2UI action to `agent` as the next turn of `conversation`. */
export function agentAction(agent: string, action: unknown, conversation?: string): unknown {
  return askHost('agent.action', [{ agent: agent, conversation: conversation, action: action }]);
}

/** The current data model of one A2UI surface of a conversation. */
export function a2uiDataModel(conversation: string, surfaceId: string): unknown {
  return askHost('a2ui.dataModel', [{ conversation: conversation, surfaceId: surfaceId }]);
}

export function render(node: ElpianNode): void {
  askHost('render', JSON.stringify(node));
  // Reset so the next view() build reproduces the same positional keys and
  // overwrites this render's closures rather than accumulating them.
  __seq = 0;
}
"##;

const SHOWCASE_TEMPLATE: &str = r##"import { el, render } from '@elpian/sdk';

// ---------------------------------------------------------------------------
// State — module-level variables, the whole of an Elpian client's state model.
// ---------------------------------------------------------------------------

type Body = { id: string; shape: string; color: string; orbit: number; size: number };

let tab: string = 'scene';
let spin: number = 24;
let lightEnergy: number = 14;
let showFloor: boolean = true;
let selected: string = 'ring';
let events: string[] = ['scene ready'];

const palette: string[] = ['#6699ff', '#ffb347', '#8ef5c0', '#ff7a90', '#c69bff'];

const bodies: Body[] = [
  { id: 'ring',  shape: 'torus',    color: '#6699ff', orbit: 0,   size: 1 },
  { id: 'core',  shape: 'sphere',   color: '#ffb347', orbit: 0,   size: 1 },
  { id: 'moonA', shape: 'box',      color: '#8ef5c0', orbit: 120, size: 1 },
  { id: 'moonB', shape: 'capsule',  color: '#ff7a90', orbit: 240, size: 1 },
];

// ---------------------------------------------------------------------------
// The 3D scene — built declaratively from the state above.
//
// Re-emitted on every render; Scene3D rebuilds the world only when the
// description actually changes, so 2D-only interactions cost nothing in 3D.
// ---------------------------------------------------------------------------

// A ring of objects without trigonometry: nest each under a rotated pivot and
// offset the child along one axis. Scene-DSL nodes are plain maps, not `el()`
// widget nodes — `el` builds the 2D tree, this builds the 3D one.
function orbiter(body: Body) {
  return {
    type: 'node',
    id: body.id + '-pivot',
    rotation: [0, body.orbit, 0],
    children: [
      {
        type: 'mesh',
        id: body.id,
        shape: body.shape,
        color: body.color,
        metallic: 0.35,
        roughness: 0.3,
        radius: 0.45 * body.size,
        size: 0.7 * body.size,
        innerRadius: 0.5 * body.size,
        outerRadius: 0.9 * body.size,
        height: 0.9 * body.size,
        position: [body.orbit === 0 ? 0 : 3.1, 1.4, 0],
      },
    ],
  };
}

function scene() {
  const nodes = [];
  for (let i = 0; i < bodies.length; i++) {
    nodes.push(orbiter(bodies[i]));
  }
  if (showFloor) {
    nodes.push({
      type: 'mesh',
      id: 'floor',
      shape: 'plane',
      width: 18,
      depth: 18,
      color: '#141a24',
      roughness: 0.95,
      position: [0, -0.4, 0],
    });
  }
  nodes.push({
    type: 'node',
    id: 'spin-rate',
    rotation: [0, spin, 0],
    children: [],
  });

  return {
    environment: { bg: '#0b0f16', ambient: '#7f8db0', ambientEnergy: 0.65 },
    camera: { id: 'cam', position: [0, 4.2, 10.5], rotation: [-16, 0, 0], fov: 52 },
    lights: [
      {
        type: 'directional',
        id: 'key',
        color: '#fff4e0',
        energy: lightEnergy / 10,
        shadow: true,
        rotation: [-52, -34, 0],
      },
      { type: 'omni', id: 'rim', color: '#4d7dff', energy: 2.2, range: 14, position: [-5, 3, -4] },
      { type: 'spot', id: 'spot', color: '#ffd7a1', energy: 3.0, range: 16, angle: 32, position: [4, 6, 4], rotation: [-58, 38, 0] },
    ],
    nodes: nodes,
  };
}

// ---------------------------------------------------------------------------
// 2D chrome — the CSS engine, flex layout, and the widget catalogue.
// ---------------------------------------------------------------------------

function statCard(label: string, value: string, accent: string) {
  return el('div', {
    className: 'card',
    style: {
      display: 'flex', flexDirection: 'column', gap: 4,
      padding: '14', borderRadius: 12, flex: 1,
      backgroundColor: '#141b26', borderWidth: 1, borderColor: '#222c3d',
    },
  }, [
    el('span', { text: label, style: { fontSize: 11, color: '#7d8798', textTransform: 'uppercase' } }, []),
    el('span', { text: value, style: { fontSize: 22, fontWeight: '700', color: accent } }, []),
  ]);
}

function pill(label: string, active: boolean) {
  return el('button', {
    key: 'tab-' + label,
    text: label,
    onClick: () => { tab = label; render(view()); },
    style: {
      padding: '10', borderRadius: 999,
      backgroundColor: active ? '#2f6bff' : '#1a2130',
      color: active ? '#ffffff' : '#95a0b4',
      fontSize: 13, fontWeight: '600',
    },
  }, []);
}

function bodyRow(body: Body) {
  const isSelected = body.id === selected;
  return el('div', {
    key: 'row-' + body.id,
    // A closure captures `body`, so the row knows which one it is. The named
    // form had to encode the id into the key and slice it back out of
    // event.currentTarget.
    onClick: () => { selected = body.id; log('selected ' + body.id); render(view()); },
    style: {
      display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 10,
      padding: '10', borderRadius: 10, cursor: 'pointer',
      backgroundColor: isSelected ? '#1d2740' : '#141b26',
      borderWidth: 1, borderColor: isSelected ? '#2f6bff' : '#222c3d',
    },
  }, [
    el('div', { style: { width: 12, height: 12, borderRadius: 999, backgroundColor: body.color } }, []),
    el('span', { text: body.id, style: { flex: 1, color: '#dfe6f2', fontSize: 14 } }, []),
    el('span', { text: body.shape, style: { color: '#6f7b8f', fontSize: 12 } }, []),
  ]);
}

function scenePanel() {
  const rows = [];
  for (let i = 0; i < bodies.length; i++) {
    rows.push(bodyRow(bodies[i]));
  }
  return el('div', { style: { display: 'flex', flexDirection: 'column', gap: 10 } }, [
    el('h3', { text: 'Bodies', style: { color: '#dfe6f2', fontSize: 15, margin: '0' } }, []),
    el('div', { style: { display: 'flex', flexDirection: 'column', gap: 8 } }, rows),
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8, marginTop: 8 } }, [
      el('button', { key: 'recolor', text: 'Recolour', onClick: () => recolour(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#2f6bff', color: '#fff', fontWeight: '600' } }, []),
      el('button', { key: 'grow', text: 'Grow', onClick: () => grow(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4', fontWeight: '600' } }, []),
    ]),
  ]);
}

function lightingPanel() {
  return el('div', { style: { display: 'flex', flexDirection: 'column', gap: 12 } }, [
    el('h3', { text: 'Lighting', style: { color: '#dfe6f2', fontSize: 15, margin: '0' } }, []),
    el('span', { text: 'Key energy: ' + (lightEnergy / 10), style: { color: '#95a0b4', fontSize: 13 } }, []),
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8 } }, [
      el('button', { key: 'dim', text: '– Dimmer', onClick: () => dimmer(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
      el('button', { key: 'bright', text: 'Brighter +', onClick: () => brighter(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
    ]),
    el('span', { text: 'Orbit spread: ' + spin + '°', style: { color: '#95a0b4', fontSize: 13 } }, []),
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8 } }, [
      el('button', { key: 'spin-', text: 'Tighten', onClick: () => tighten(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
      el('button', { key: 'spin+', text: 'Spread', onClick: () => spread(),
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
    ]),
    el('button', { key: 'floor', text: showFloor ? 'Hide floor' : 'Show floor', onClick: () => toggleFloor(),
      style: { padding: '12', borderRadius: 10, backgroundColor: showFloor ? '#2f6bff' : '#1a2130', color: '#fff', fontWeight: '600' } }, []),
  ]);
}

function logPanel() {
  const items = [];
  for (let i = 0; i < events.length; i++) {
    items.push(el('li', {
      key: 'ev-' + i,
      text: events[i],
      style: { color: '#95a0b4', fontSize: 12, padding: '6' },
    }, []));
  }
  return el('div', { style: { display: 'flex', flexDirection: 'column', gap: 8 } }, [
    el('h3', { text: 'Events', style: { color: '#dfe6f2', fontSize: 15, margin: '0' } }, []),
    el('ul', { style: { display: 'flex', flexDirection: 'column', gap: 2 } }, items),
  ]);
}

function panel() {
  if (tab === 'lighting') { return lightingPanel(); }
  if (tab === 'events') { return logPanel(); }
  return scenePanel();
}

// ---------------------------------------------------------------------------
// The screen: a full-bleed 3D stage with 2D chrome laid over and beside it.
// ---------------------------------------------------------------------------

function view() {
  return el('div', {
    style: {
      display: 'flex', flexDirection: 'column', height: '100vh',
      backgroundColor: '#0b0f16',
    },
  }, [
    // Header
    el('div', {
      style: {
        display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 12,
        padding: '16', backgroundColor: '#101722',
        borderBottomWidth: 1, borderBottomColor: '#1e2635',
      },
    }, [
      el('div', { style: { width: 10, height: 10, borderRadius: 999, backgroundColor: '#2f6bff' } }, []),
      el('h1', { text: 'Elpian Showcase', style: { color: '#eef3fb', fontSize: 18, margin: '0', flex: 1 } }, []),
      el('span', { text: 'Scene3D + 2D GUI', style: { color: '#6f7b8f', fontSize: 12 } }, []),
    ]),

    // Stat row
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 10, padding: '14' } }, [
      statCard('Bodies', '' + bodies.length, '#6699ff'),
      statCard('Lights', '3', '#ffb347'),
      statCard('Key', '' + (lightEnergy / 10), '#8ef5c0'),
      statCard('Selected', selected, '#c69bff'),
    ]),

    // The 3D stage
    el('div', { style: { display: 'flex', flexDirection: 'column', flex: 1, padding: '14', paddingTop: '0' } }, [
      el('div', {
        style: {
          flex: 1, borderRadius: 16, overflow: 'hidden',
          borderWidth: 1, borderColor: '#1e2635',
        },
      }, [
        el('Scene3D', { key: 'stage', initialScene: scene() }, []),
      ]),
    ]),

    // Tabs + panel
    el('div', {
      style: {
        display: 'flex', flexDirection: 'column', gap: 12, padding: '16',
        backgroundColor: '#101722',
        borderTopWidth: 1, borderTopColor: '#1e2635',
      },
    }, [
      el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8 } }, [
        pill('scene', tab === 'scene'),
        pill('lighting', tab === 'lighting'),
        pill('events', tab === 'events'),
      ]),
      panel(),
    ]),
  ]);
}

// ---------------------------------------------------------------------------
// Handlers. Named top-level functions — the `events` map carries names, not
// closures, so per-item identity comes from the event's currentTarget.
// ---------------------------------------------------------------------------

function log(message: string) {
  events.unshift(message);
  if (events.length > 6) { events.pop(); }
}

function recolour() {
  for (let i = 0; i < bodies.length; i++) {
    if (bodies[i].id === selected) {
      const at = (palette.indexOf(bodies[i].color) + 1) % palette.length;
      bodies[i].color = palette[at];
      log(selected + ' → ' + bodies[i].color);
    }
  }
  render(view());
}

function grow() {
  for (let i = 0; i < bodies.length; i++) {
    if (bodies[i].id === selected) {
      bodies[i].size = bodies[i].size >= 1.6 ? 0.6 : bodies[i].size + 0.2;
      log(selected + ' size ' + bodies[i].size);
    }
  }
  render(view());
}

function dimmer() { lightEnergy = lightEnergy > 2 ? lightEnergy - 2 : 1; log('key ' + lightEnergy / 10); render(view()); }
function brighter() { lightEnergy = lightEnergy < 30 ? lightEnergy + 2 : 30; log('key ' + lightEnergy / 10); render(view()); }
function tighten() { spin = spin > 8 ? spin - 8 : 0; log('spread ' + spin); render(view()); }
function spread() { spin = spin + 8; log('spread ' + spin); render(view()); }
function toggleFloor() { showFloor = !showFloor; log(showFloor ? 'floor on' : 'floor off'); render(view()); }

render(view());
"##;

const SHOWCASE_README: &str = r##"# Elpian showcase

A mixed **2D + 3D** application: an embedded Godot `Scene3D` stage surrounded by
a rich Flutter GUI, all emitted from one TypeScript program running as Elpian
bytecode.

```sh
elpian run install
elpian run dev
```

## What it demonstrates

- **`Scene3D`** with a full declarative scene: environment, camera, three light
  types (directional / omni / spot), nested pivot groups for orbiting bodies,
  and a floor plane.
- **The 2D widget catalogue** around it — header, stat cards, tab pills, a
  selectable list, and action buttons, laid out with the CSS flex engine.
- **Interaction crossing the boundary**: 2D controls mutate module state, the
  scene is re-derived from it, and `Scene3D` rebuilds the 3D world only when the
  description actually changes.

## Where 3D runs

`elpian_ui` ships the Dart API; a real engine needs the `elpian_godot` plugin.
Without it `Scene3D` renders a placeholder and every 2D control still works —
which is exactly what the web build shows.
"##;

const AGENTIC_CLIENT_TEMPLATE: &str = r##"import { el, render, a2uiSurface } from '@elpian/sdk';

// Static UI and agent UI side by side. The header and the footer are ordinary
// Elpian nodes; the A2UISurface in between renders whatever the `assistant`
// agent sends (A2UI v0.9.1), and its `chat` row lets the user talk to it.

let visits: number = 0;

function view() {
  return el('div', { style: { padding: '24', display: 'flex', flexDirection: 'column', gap: 16 } }, [
    el('h1', { text: 'Tea & Coffee' }, []),
    el('p', { text: 'Ask the assistant for something to drink.' }, []),

    a2uiSurface({
      agent: 'assistant',
      prompt: 'Show me what you have.',
      chat: true,
      showText: true,
    }),

    el('button', {
      key: 'visits',
      text: 'Static UI still works: ' + visits,
      onClick: () => { visits = visits + 1; render(view()); },
    }, []),
  ]);
}

render(view());
"##;

/// The agentic template's server function — also the agent's tool.
const AGENTIC_ACTION: &str = r#"// An action the client may call, and the `assistant` agent calls as its
// `fn_listProducts` tool — through the same path, as the same caller.

function listProducts(args) {
  var all = [
    { id: "sencha", name: "Sencha", category: "tea", price: 6.5 },
    { id: "assam", name: "Assam", category: "tea", price: 5.0 },
    { id: "espresso", name: "Espresso blend", category: "coffee", price: 9.0 },
    { id: "filter", name: "Filter roast", category: "coffee", price: 8.0 }
  ];
  if (args == null || args.category == null) {
    return { products: all };
  }
  var out = [];
  var i = 0;
  while (i < all.length) {
    if (all[i].category == args.category) {
      out.push(all[i]);
    }
    i = i + 1;
  }
  return { products: out };
}
"#;

const AGENTIC_INSTRUCTIONS: &str = r#"You are the shop assistant of a small tea and coffee shop.

- Find products with the `fn_listProducts` tool; never invent products or prices.
- Show products as UI, not prose: load the `catalog` skill before building a product list.
- When the user wants to buy something, load the `ordering` skill.
- Keep text short. The surface is where the information goes.
"#;

const AGENTIC_SKILL_CATALOG: &str = r#"---
name: catalog
description: Show products as a list with a name, a price and an Order button each.
---

Build one surface, `products`, with `sendDataModel: true`:

- Put the products in the data model at `/products` (an array of `{id, name, price}`).
- Root: a `Column` with a heading `Text` (variant `h3`) and a `List` whose `children` is a
  template: `{"componentId": "product_row", "path": "/products"}`.
- `product_row` is a `Card` whose child is a `Row` with a `Text` bound to `name` (relative path),
  a `Text` with `{"call": "formatCurrency", "args": {"value": {"path": "price"}, "currency": "EUR"},
  "returnType": "string"}`, and a `Button` whose action is
  `{"event": {"name": "order", "context": {"id": {"path": "id"}, "name": {"path": "name"}}}}`.

Update an existing surface with `updateDataModel` rather than recreating it.
"#;

const AGENTIC_SKILL_ORDERING: &str = r#"---
name: ordering
description: Handle an "order" action from a product list.
---

An `order` action arrives as `{"a2uiAction": {"name": "order", "context": {"id", "name"}}}`.

Confirm in one short sentence, and show the confirmation in a surface `order` (create it the first
time; afterwards update its data model): a `Card` with a `Text` "Ordered" heading and a `Text`
bound to `/item`.
"#;

/// Canned turns for `ELPIAN_AGENT_PROVIDER=scripted`: the agent calls the
/// server function, builds the product list, and answers `order` actions.
const AGENTIC_SCRIPT: &str = r#"{
  "exchanges": [
    {
      "when": { "action": "order" },
      "turns": [
        { "tools": [ { "name": "a2ui_send", "input": { "messages": [
          { "version": "v0.9.1", "updateDataModel": { "surfaceId": "products", "path": "/ordered", "value": "{{action.context.name}}" } }
        ] } } ] },
        { "text": "Ordered {{action.context.name}} (scripted)." }
      ]
    },
    {
      "turns": [
        { "text": "Let me look.", "tools": [ { "name": "fn_listProducts", "input": {} } ] },
        { "tools": [ { "name": "a2ui_send", "input": { "messages": [
          { "version": "v0.9.1", "createSurface": { "surfaceId": "products", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json", "sendDataModel": true, "theme": { "agentDisplayName": "Shop assistant" } } },
          { "version": "v0.9.1", "updateComponents": { "surfaceId": "products", "components": [
            { "id": "root", "component": "Column", "children": ["heading", "list", "ordered"] },
            { "id": "heading", "component": "Text", "text": "Today's selection", "variant": "h3" },
            { "id": "list", "component": "List", "children": { "componentId": "product_row", "path": "/products" } },
            { "id": "product_row", "component": "Card", "child": "row" },
            { "id": "row", "component": "Row", "justify": "spaceBetween", "align": "center", "children": ["name", "price", "order"] },
            { "id": "name", "component": "Text", "text": { "path": "name" } },
            { "id": "price", "component": "Text", "text": { "call": "formatCurrency", "args": { "value": { "path": "price" }, "currency": "EUR" }, "returnType": "string" } },
            { "id": "order_label", "component": "Text", "text": "Order" },
            { "id": "order", "component": "Button", "child": "order_label", "variant": "primary", "action": { "event": { "name": "order", "context": { "id": { "path": "id" }, "name": { "path": "name" } } } } },
            { "id": "ordered", "component": "Text", "text": { "call": "formatString", "args": { "value": "Last order: ${/ordered}" }, "returnType": "string" }, "variant": "caption" }
          ] } },
          { "version": "v0.9.1", "updateDataModel": { "surfaceId": "products", "value": { "ordered": "nothing yet", "products": [
            { "id": "sencha", "name": "Sencha", "price": 6.5 },
            { "id": "assam", "name": "Assam", "price": 5.0 },
            { "id": "espresso", "name": "Espresso blend", "price": 9.0 },
            { "id": "filter", "name": "Filter roast", "price": 8.0 }
          ] } } }
        ] } } ] },
        { "text": "Here is today's selection (scripted)." }
      ]
    }
  ]
}
"#;

/// A server action for the `closed-fullstack` template.
const MINI_APP_ACTION: &str = r#"// An action: returns JSON, may write.
//
// Note the failure path. The language subset has no `throw` and no `try`/`catch`
// to catch one with, so an error is a *value* the caller tests.

function createNote(args) {
  if (args == null || args.text == null || args.text == "") {
    return { error: { code: "invalid", message: "a note needs text" } };
  }

  // The key is namespaced by the host under this app. There is no key a guest
  // can construct that reaches another app's state, because the guest never
  // sends an app id.
  var id = "note:" + now();
  kvSet(id, { id: id, text: args.text, at: now() });

  // Tell the host that renders tagged "notes" are stale. An app can only ever
  // invalidate its own.
  revalidate("notes");
  log("created " + id);
  return { id: id };
}
"#;

/// A server component for the `closed-fullstack` template.
const MINI_APP_COMPONENT: &str = r#"// A component: RETURNS a UI payload. It never calls `render` — the server
// posture denies that capability, because a component that rendered as a side
// effect could not be cached, could not be tested without a host, and could
// half-render.

function NoteList(args) {
  var keys = kvList("note:");
  var children = [];
  var i = 0;
  while (i < keys.length) {
    var note = kvGet(keys[i]);
    if (note != null) {
      children.push({ type: "Text", props: { text: note.text } });
    }
    i = i + 1;
  }

  if (children.length == 0) {
    children.push({ type: "Text", props: { text: "No notes yet." } });
  }

  // Caching is opt-in. Tagged so the action above invalidates it, and capped at
  // 60 seconds so a missed revalidation self-corrects rather than serving a
  // stale page forever.
  return ui({ type: "Column", props: {}, children: children }, ["notes"], 60);
}
"#;
