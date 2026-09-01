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
#[command(name = "elpian", version, about = "Native Rust toolchain for Elpian projects")]
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
}

#[derive(Args)]
struct CreateArgs {
    directory: PathBuf,
    #[arg(short, long, value_enum, default_value_t = Template::Client)]
    template: Template,
}

#[derive(Clone, Copy, ValueEnum)]
enum Template { Client, Server, Fullstack, Showcase }

#[derive(Subcommand)]
enum RunTask {
    Install,
    Build {
        #[arg(short, long, value_enum)]
        mode: Option<Mode>,
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
    },
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, ValueEnum, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Mode { Js, Bytecode, Both }

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    #[serde(default = "default_out")]
    out_dir: PathBuf,
    #[serde(default = "default_mode")]
    mode: Mode,
    engine_dir: Option<PathBuf>,
    engine_project: Option<PathBuf>,
    #[serde(default = "default_base")]
    base_path: String,
    client: Option<Target>,
    server: Option<Target>,
}

#[derive(Clone, Debug, Deserialize)]
struct Target { entry: PathBuf }
fn default_out() -> PathBuf { "dist".into() }
fn default_mode() -> Mode { Mode::Both }
fn default_base() -> String { "/".into() }

#[derive(Deserialize)]
struct ProjectSpec {
    #[allow(dead_code)] name: String,
    #[serde(default)] dependencies: BTreeMap<String, PackageRef>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum PackageRef { Path(String), Object { path: String } }

#[derive(Deserialize)]
struct PackageSpec { name: String, entry: String }

#[derive(Clone)]
struct Artifact { target: &'static str, js: PathBuf, ast: PathBuf, bytecode: Option<PathBuf> }

fn main() {
    if let Err(error) = real_main() {
        eprintln!("elpian: {error:#}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        CommandName::Create(args) => create_project(&absolute(&env::current_dir()?, &args.directory), args.template),
        CommandName::Run { task } => {
            let root = env::current_dir()?;
            match task {
                RunTask::Install => { println!("Installed {} Elpian package(s)", install(&root)?); Ok(()) }
                RunTask::Build { mode } => {
                    let mut config = load_config(&root)?;
                    if let Some(mode) = mode { config.mode = mode; }
                    for artifact in build_project(&root, &config, true)? {
                        println!("Built {}: {}", artifact.target, artifact.bytecode.as_ref().unwrap_or(&artifact.ast).display());
                    }
                    if config.client.is_some() { println!("Deployable web app: {}/web", config.out_dir.display()); }
                    Ok(())
                }
                RunTask::Dev { host, port, mode, build_engine } => {
                    let mut config = load_config(&root)?;
                    if let Some(mode) = mode { config.mode = mode; }
                    dev(&root, config, &host, port, build_engine)
                }
            }
        }
    }
}

fn load_config(root: &Path) -> Result<Config> {
    let file = root.join("elpian.config.json");
    let config: Config = serde_json::from_slice(&fs::read(&file).with_context(|| format!("cannot read {}", file.display()))?)?;
    if config.client.is_none() && config.server.is_none() { bail!("configure a client or server target"); }
    Ok(config)
}

fn install(root: &Path) -> Result<usize> {
    let spec: ProjectSpec = read_json(&root.join("elpian.json"))?;
    let packages = root.join(".elpian/packages");
    fs::create_dir_all(&packages)?;
    let mut lock = serde_json::Map::new();
    for (name, reference) in &spec.dependencies {
        validate_package_name(name)?;
        let declared = match reference { PackageRef::Path(path) | PackageRef::Object { path } => path };
        let source = fs::canonicalize(root.join(declared)).with_context(|| format!("package {name} path {declared} does not exist"))?;
        let package: PackageSpec = read_json(&source.join("elpian.package.json"))?;
        if package.name != *name { bail!("package {} declares name {}, expected {name}", source.display(), package.name); }
        if !source.join(&package.entry).is_file() { bail!("package {name} entry {} does not exist", package.entry); }
        let destination = packages.join(name);
        if let Ok(existing) = fs::read_link(&destination) {
            if fs::canonicalize(destination.parent().unwrap().join(existing))? != source { fs::remove_file(&destination)?; }
        } else if destination.exists() { bail!("{} exists and is not a managed package link", destination.display()); }
        if !destination.exists() {
            fs::create_dir_all(destination.parent().unwrap())?;
            create_dir_link(&source, &destination)?;
        }
        lock.insert(name.clone(), json!({ "path": source }));
    }
    fs::create_dir_all(root.join(".elpian"))?;
    write_json(&root.join(".elpian/elpian.lock.json"), &json!({ "version": 1, "packages": lock }))?;
    Ok(spec.dependencies.len())
}

#[cfg(unix)]
fn create_dir_link(source: &Path, destination: &Path) -> Result<()> { std::os::unix::fs::symlink(source, destination)?; Ok(()) }
#[cfg(windows)]
fn create_dir_link(source: &Path, destination: &Path) -> Result<()> { std::os::windows::fs::symlink_dir(source, destination)?; Ok(()) }

fn build_project(root: &Path, config: &Config, package_web: bool) -> Result<Vec<Artifact>> {
    let out = absolute(root, &config.out_dir);
    fs::create_dir_all(&out)?;
    let mut artifacts = Vec::new();
    for (name, target) in [("client", config.client.as_ref()), ("server", config.server.as_ref())] {
        let Some(target) = target else { continue };
        let js = out.join(format!("{name}.elpian.js"));
        let ast = out.join(format!("{name}.elpian.ast.json"));
        let bytecode_path = out.join(format!("{name}.elpian.bc"));
        let mut seen = HashSet::new();
        let mut modules = Vec::new();
        bundle_module(root, &resolve_source(&absolute(root, &target.entry))?, &mut seen, &mut modules)?;
        let source = modules.join("\n");
        fs::write(&js, &source)?;
        let ast_json = js2elpian::compile_js_to_ast(source.clone());
        let ast_value: serde_json::Value = serde_json::from_str(&ast_json)?;
        if let Some(error) = ast_value.get("error") { bail!("{name}: {error}"); }
        fs::write(&ast, ast_json)?;
        let bytecode = if config.mode != Mode::Js {
            let bytes = js2elpian::compile_js_to_bytecode(&source).ok_or_else(|| anyhow!("{name}: JavaScript is outside the Elpian subset"))?;
            fs::write(&bytecode_path, bytes)?;
            Some(bytecode_path)
        } else { None };
        artifacts.push(Artifact { target: name, js, ast, bytecode });
    }
    let client = artifacts.iter().find(|item| item.target == "client");
    let manifest = json!({
        "version": 1,
        "client": client.map(|item| json!({
            "format": if item.bytecode.is_some() { "bytecode" } else { "ast" },
            "url": format!("__elpian/{}", item.bytecode.as_ref().unwrap_or(&item.ast).file_name().unwrap().to_string_lossy()),
            "sourceUrl": format!("__elpian/{}", item.js.file_name().unwrap().to_string_lossy())
        })),
        "server": config.server.as_ref().map(|_| json!({ "endpoint": "__elpian/api" }))
    });
    write_json(&out.join("elpian.manifest.json"), &manifest)?;
    if package_web && client.is_some() { package_web_export(root, config, &artifacts, &out)?; }
    Ok(artifacts)
}

fn bundle_module(root: &Path, file: &Path, seen: &mut HashSet<PathBuf>, output: &mut Vec<String>) -> Result<()> {
    let file = fs::canonicalize(file)?;
    if !seen.insert(file.clone()) { return Ok(()); }
    let source = fs::read_to_string(&file)?;
    let import_re = Regex::new(r#"(?ms)^\s*import\s+(?:[\s\S]*?\s+from\s+)?[\"']([^\"']+)[\"']\s*;?"#)?;
    for capture in import_re.captures_iter(&source) {
        let dependency = resolve_import(root, &file, &capture[1])?;
        bundle_module(root, &dependency, seen, output)?;
    }
    let transformed = transpile_typescript(&file, &source)?;
    let without_imports = import_re.replace_all(&transformed, "");
    let export_decl = Regex::new(r"(?m)^\s*export\s+((?:async\s+)?(?:function|class|const|let|var)\b)")?;
    let export_list = Regex::new(r"(?ms)^\s*export\s*\{.*?\}\s*;?")?;
    let cleaned = export_list.replace_all(&export_decl.replace_all(&without_imports, "$1"), "").to_string();
    output.push(format!("// {}\n{}", file.strip_prefix(root).unwrap_or(&file).display(), cleaned));
    Ok(())
}

fn transpile_typescript(path: &Path, source: &str) -> Result<String> {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(path).map_err(|_| anyhow!("unsupported source type: {}", path.display()))?;
    let parsed = OxcParser::new(&allocator, source, source_type).parse();
    if !parsed.diagnostics.is_empty() {
        bail!("TypeScript parse failed in {}: {}", path.display(), parsed.diagnostics[0].clone().render_with_source_code(source.to_string()));
    }
    let mut program = parsed.program;
    let semantic = SemanticBuilder::new().with_excess_capacity(2.0).with_enum_eval(true).build(&program);
    if !semantic.diagnostics.is_empty() { bail!("TypeScript semantics failed in {}", path.display()); }
    let transformed = Transformer::new(&allocator, path, &TransformOptions::default())
        .build_with_scoping(semantic.semantic.into_scoping(), &mut program);
    if !transformed.diagnostics.is_empty() { bail!("TypeScript transform failed in {}", path.display()); }
    Ok(Codegen::new().build(&program).code)
}

fn resolve_import(root: &Path, importer: &Path, specifier: &str) -> Result<PathBuf> {
    if specifier.starts_with('.') {
        return resolve_source(&importer.parent().unwrap().join(specifier));
    }
    let parts: Vec<_> = specifier.split('/').collect();
    let package_name = if specifier.starts_with('@') { parts[..2].join("/") } else { parts[0].to_string() };
    let package_dir = root.join(".elpian/packages").join(&package_name);
    let package: PackageSpec = read_json(&package_dir.join("elpian.package.json"))?;
    let subpath = specifier.strip_prefix(&package_name).unwrap().trim_start_matches('/');
    resolve_source(&package_dir.join(if subpath.is_empty() { &package.entry } else { subpath }))
        .with_context(|| format!("cannot resolve Elpian package {specifier}; run `elpian run install`"))
}

fn resolve_source(path: &Path) -> Result<PathBuf> {
    let candidates = [path.to_path_buf(), path.with_extension("ts"), path.with_extension("tsx"), path.with_extension("js"), path.join("index.ts")];
    candidates.into_iter().find(|item| item.is_file()).ok_or_else(|| anyhow!("source file not found: {}", path.display()))
}

fn package_web_export(root: &Path, config: &Config, artifacts: &[Artifact], out: &Path) -> Result<()> {
    let engine_project = config.engine_project.as_ref().map(|value| absolute(root, value)).unwrap_or_else(|| cli_root().join("elpian_client"));
    let engine = config.engine_dir.as_ref().map(|value| absolute(root, value)).unwrap_or_else(|| engine_project.join("build/web"));
    let base = normalize_base(&config.base_path);
    let marker = engine.join(".elpian_runtime");
    if config.engine_dir.is_none() && runtime_stale(&engine_project, &marker, &base)? {
        run_checked(Command::new("flutter").current_dir(&engine_project).args(["build", "web", "--base-href", &base]))?;
        fs::write(&marker, format!("elpian_client/lib/main.dart\nbasePath={base}\n"))?;
    }
    if !engine.join("index.html").is_file() { bail!("Flutter engine missing at {}", engine.display()); }
    let web = out.join("web");
    if web.exists() { fs::remove_dir_all(&web)?; }
    copy_tree(&engine, &web)?;
    let guest = web.join("__elpian");
    fs::create_dir_all(&guest)?;
    fs::copy(out.join("elpian.manifest.json"), guest.join("elpian.manifest.json"))?;
    for item in artifacts {
        for file in [&item.js, &item.ast].into_iter().chain(item.bytecode.iter()) { fs::copy(file, guest.join(file.file_name().unwrap()))?; }
    }
    disable_service_worker(&web)?;
    Ok(())
}

fn dev(root: &Path, config: Config, host: &str, port: u16, force_engine: bool) -> Result<()> {
    build_project(root, &config, false)?;
    let engine_project = config.engine_project.as_ref().map(|value| absolute(root, value)).unwrap_or_else(|| cli_root().join("elpian_client"));
    let engine = config.engine_dir.as_ref().map(|value| absolute(root, value)).unwrap_or_else(|| engine_project.join("build/web"));
    let base = normalize_base(&config.base_path);
    let marker = engine.join(".elpian_runtime");
    if config.engine_dir.is_none() && (force_engine || runtime_stale(&engine_project, &marker, &base)?) {
        run_checked(Command::new("flutter").current_dir(&engine_project).args(["build", "web", "--base-href", &base]))?;
        fs::write(&marker, format!("elpian_client/lib/main.dart\nbasePath={base}\n"))?;
    }
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |event| { if changed(&event) { let _ = tx.send(event); } })?;
    for path in [root.join("src"), root.join("packages"), root.join("elpian.json"), root.join("elpian.config.json")] {
        if path.exists() { watcher.watch(&path, if path.is_dir() { RecursiveMode::Recursive } else { RecursiveMode::NonRecursive })?; }
    }
    let rebuild_root = root.to_path_buf();
    let rebuild_config = config.clone();
    std::thread::spawn(move || while rx.recv().is_ok() {
        while rx.try_recv().is_ok() {}
        match build_project(&rebuild_root, &rebuild_config, false) { Ok(_) => println!("[elpian] rebuilt"), Err(error) => eprintln!("[elpian] build failed: {error:#}") }
    });
    let manifest = workspace().join("rust/Cargo.toml");
    let out = absolute(root, &config.out_dir);
    let mut command = Command::new("cargo");
    command.current_dir(root).args(["run", "--quiet", "--manifest-path"]).arg(manifest).args(["--bin", "elpian-server", "--", "--host", host, "--port", &port.to_string(), "--web-root"]).arg(&engine).arg("--artifact-root").arg(&out);
    let server_bytecode = out.join("server.elpian.bc");
    if server_bytecode.is_file() { command.arg("--server-bytecode").arg(server_bytecode); }
    command.stdin(Stdio::inherit()).stdout(Stdio::inherit()).stderr(Stdio::inherit());
    let status = command.status()?;
    if !status.success() { bail!("Elpian Rust server exited {status}"); }
    Ok(())
}

fn create_project(root: &Path, template: Template) -> Result<()> {
    if root.exists() { bail!("{} already exists", root.display()); }
    fs::create_dir_all(root.join("src"))?;
    let client = !matches!(template, Template::Server);
    let server = matches!(template, Template::Server | Template::Fullstack);
    let showcase = matches!(template, Template::Showcase);
    let name = root.file_name().unwrap().to_string_lossy();
    let dependencies = if client { json!({ "@elpian/sdk": { "path": "./packages/elpian-sdk" } }) } else { json!({}) };
    write_json(&root.join("elpian.json"), &json!({ "name": name, "spec": 1, "dependencies": dependencies }))?;
    write_json(&root.join("elpian.config.json"), &json!({
        "outDir": "dist", "mode": "both", "basePath": "/",
        "client": client.then(|| json!({ "entry": "src/client.ts" })),
        "server": server.then(|| json!({ "entry": "src/server.ts" }))
    }))?;
    fs::write(root.join("tsconfig.json"), "{\n  \"compilerOptions\": { \"target\": \"ES2015\", \"strict\": true, \"module\": \"ESNext\" },\n  \"include\": [\"src\"]\n}\n")?;
    fs::write(root.join(".gitignore"), "dist/\n.elpian/\n")?;
    let readme = if showcase { format!("{SHOWCASE_README}") } else {
        format!("# {name}\n\nRun `elpian run install`, then `elpian run dev`.\n")
    };
    fs::write(root.join("README.md"), readme)?;
    if client {
        fs::write(
            root.join("src/client.ts"),
            if showcase { SHOWCASE_TEMPLATE } else { CLIENT_TEMPLATE },
        )?;
        let sdk = root.join("packages/elpian-sdk"); fs::create_dir_all(&sdk)?;
        write_json(&sdk.join("elpian.package.json"), &json!({ "name": "@elpian/sdk", "version": "0.1.0", "spec": 1, "entry": "index.ts" }))?;
        fs::write(sdk.join("index.ts"), SDK_TEMPLATE)?;
    }
    if server { fs::write(root.join("src/server.ts"), SERVER_TEMPLATE)?; }
    println!("Created {}", root.display());
    Ok(())
}

fn changed(event: &notify::Result<notify::Event>) -> bool {
    // Reads count as inotify events, so a rebuild that opens the watched sources would retrigger itself.
    event.as_ref().map(|item| !matches!(item.kind, EventKind::Access(_))).unwrap_or(false)
}

fn runtime_stale(project: &Path, marker: &Path, base: &str) -> Result<bool> {
    if !marker.is_file() { return Ok(true); }
    if !fs::read_to_string(marker)?.lines().any(|line| line.trim() == format!("basePath={base}")) { return Ok(true); }
    let built = fs::metadata(marker)?.modified()?;
    let ui = ui_package(project).unwrap_or_else(|| project.join(".."));
    for source in [project.join("lib/main.dart"), ui.join("lib/src/vm/elpian_vm_widget.dart"), ui.join("lib/src/vm/frb_generated/api_web.dart")] {
        if source.is_file() && fs::metadata(source)?.modified()? > built { return Ok(true); }
    }
    Ok(false)
}

fn ui_package(project: &Path) -> Option<PathBuf> {
    let pubspec = fs::read_to_string(project.join("pubspec.yaml")).ok()?;
    let value = pubspec.lines().skip_while(|line| line.trim_end() != "  elpian_ui:").skip(1).take_while(|line| line.starts_with("    ")).find_map(|line| line.trim().strip_prefix("path:"))?;
    Some(absolute(project, Path::new(value.trim().trim_matches(['"', '\'']))))
}

fn disable_service_worker(web: &Path) -> Result<()> {
    let bootstrap = web.join("flutter_bootstrap.js");
    if bootstrap.is_file() {
        let source = fs::read_to_string(&bootstrap)?;
        let re = Regex::new(r"(?s)_flutter\.loader\.load\(\{\s*serviceWorkerSettings:.*?\}\s*\}\);?\s*$")?;
        fs::write(bootstrap, re.replace(&source, "_flutter.loader.load();\n").as_bytes())?;
    }
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    for entry in WalkDir::new(source) {
        let entry = entry?; let relative = entry.path().strip_prefix(source)?; let target = destination.join(relative);
        if entry.file_type().is_dir() { fs::create_dir_all(&target)?; } else { if let Some(parent) = target.parent() { fs::create_dir_all(parent)?; } fs::copy(entry.path(), target)?; }
    }
    Ok(())
}

fn normalize_base(value: &str) -> String { format!("/{}/", value.trim_matches('/')).replace("//", "/") }
fn cli_root() -> PathBuf { PathBuf::from(env!("CARGO_MANIFEST_DIR")) }
/// The elpian repository root — the CLI crate now lives inside it.
fn workspace() -> PathBuf { cli_root().parent().unwrap().to_path_buf() }
fn absolute(root: &Path, value: &Path) -> PathBuf { if value.is_absolute() { value.to_path_buf() } else { root.join(value) } }
fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> { Ok(serde_json::from_slice(&fs::read(path).with_context(|| format!("cannot read {}", path.display()))?)?) }
fn write_json(path: &Path, value: &serde_json::Value) -> Result<()> { fs::write(path, format!("{}\n", serde_json::to_string_pretty(value)?))?; Ok(()) }
fn run_checked(command: &mut Command) -> Result<()> { let status = command.status()?; if !status.success() { bail!("command exited {status}"); } Ok(()) }
fn validate_package_name(name: &str) -> Result<()> { if name.is_empty() || name.contains("..") || name.starts_with('/') || name.ends_with('/') { bail!("invalid package name: {name}"); } Ok(()) }

const CLIENT_TEMPLATE: &str = r#"import { el, render } from '@elpian/sdk';
let count: number = 0;
function view() {
  return el('div', { style: { padding: '32', color: '#172033' } }, [
    el('h1', { text: 'Hello from TypeScript' }, []),
    el('p', { text: 'This UI is running as Elpian bytecode.' }, []),
    el('button', { text: 'Count: ' + count, onClick: 'increment' }, []),
  ]);
}
function increment() { count = count + 1; render(view()); }
render(view());
"#;
const SERVER_TEMPLATE: &str = r#"export function hello(input: { name?: string }) {
  const name = input.name || 'world';
  return { message: 'Hello, ' + name + ', from the Elpian server VM!' };
}
"#;
const SDK_TEMPLATE: &str = r#"export type ElpianNode = { type: string; props: Record<string, unknown>; events?: Record<string, string>; children?: ElpianNode[] };
export function el(type: string, props: Record<string, unknown>, children: ElpianNode[]): ElpianNode {
  // The host reads handlers from a top-level `events` map keyed by the
  // lowercase event name ("click"), not from `onClick` inside props.
  const rest: Record<string, unknown> = {};
  const events: Record<string, string> = {};
  for (const key in props) {
    const value = props[key];
    if (typeof value === 'string' && key.length > 2 && key.slice(0, 2) === 'on') {
      events[key.slice(2).toLowerCase()] = value;
    } else {
      rest[key] = value;
    }
  }
  return { type, props: rest, events, children };
}
declare function askHost(name: string, payload: unknown): unknown;
export function render(node: ElpianNode): void { askHost('render', JSON.stringify(node)); }
"#;

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

function pill(label: string, active: boolean, handler: string) {
  return el('button', {
    key: 'tab-' + label,
    text: label,
    onClick: handler,
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
    onClick: 'selectBody',
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
      el('button', { key: 'recolor', text: 'Recolour', onClick: 'recolour',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#2f6bff', color: '#fff', fontWeight: '600' } }, []),
      el('button', { key: 'grow', text: 'Grow', onClick: 'grow',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4', fontWeight: '600' } }, []),
    ]),
  ]);
}

function lightingPanel() {
  return el('div', { style: { display: 'flex', flexDirection: 'column', gap: 12 } }, [
    el('h3', { text: 'Lighting', style: { color: '#dfe6f2', fontSize: 15, margin: '0' } }, []),
    el('span', { text: 'Key energy: ' + (lightEnergy / 10), style: { color: '#95a0b4', fontSize: 13 } }, []),
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8 } }, [
      el('button', { key: 'dim', text: '– Dimmer', onClick: 'dimmer',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
      el('button', { key: 'bright', text: 'Brighter +', onClick: 'brighter',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
    ]),
    el('span', { text: 'Orbit spread: ' + spin + '°', style: { color: '#95a0b4', fontSize: 13 } }, []),
    el('div', { style: { display: 'flex', flexDirection: 'row', gap: 8 } }, [
      el('button', { key: 'spin-', text: 'Tighten', onClick: 'tighten',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
      el('button', { key: 'spin+', text: 'Spread', onClick: 'spread',
        style: { flex: 1, padding: '12', borderRadius: 10, backgroundColor: '#1a2130', color: '#cbd4e4' } }, []),
    ]),
    el('button', { key: 'floor', text: showFloor ? 'Hide floor' : 'Show floor', onClick: 'toggleFloor',
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
    el('div', { style: { flex: 1, padding: '14', paddingTop: '0' } }, [
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
        pill('scene', tab === 'scene', 'tabScene'),
        pill('lighting', tab === 'lighting', 'tabLighting'),
        pill('events', tab === 'events', 'tabEvents'),
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

function tabScene() { tab = 'scene'; render(view()); }
function tabLighting() { tab = 'lighting'; render(view()); }
function tabEvents() { tab = 'events'; render(view()); }

function selectBody(event) {
  const target = event.currentTarget;
  if (typeof target === 'string' && target.slice(0, 4) === 'row-') {
    selected = target.slice(4);
    log('selected ' + selected);
    render(view());
  }
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
