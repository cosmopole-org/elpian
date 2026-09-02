use std::{
    env, fs,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    thread,
};

static REQUEST_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone)]
struct Config {
    host: String,
    port: u16,
    web_root: PathBuf,
    artifact_root: PathBuf,
    server_bytecode: Option<PathBuf>,
}

fn main() {
    let config = parse_args().unwrap_or_else(|error| {
        eprintln!("elpian-server: {error}");
        std::process::exit(2);
    });
    let listener =
        TcpListener::bind(format!("{}:{}", config.host, config.port)).unwrap_or_else(|error| {
            eprintln!("elpian-server: {error}");
            std::process::exit(1);
        });
    println!(
        "[elpian] Rust VM server: http://{}:{}",
        if config.host == "0.0.0.0" {
            "localhost"
        } else {
            &config.host
        },
        config.port
    );
    for connection in listener.incoming() {
        let config = config.clone();
        match connection {
            Ok(stream) => {
                thread::spawn(move || {
                    let _ = handle(stream, &config);
                });
            }
            Err(error) => eprintln!("elpian-server: connection error: {error}"),
        }
    }
}

fn parse_args() -> Result<Config, String> {
    let mut config = Config {
        host: "127.0.0.1".into(),
        port: 4173,
        web_root: PathBuf::new(),
        artifact_root: PathBuf::new(),
        server_bytecode: None,
    };
    let args: Vec<String> = env::args().skip(1).collect();
    let mut index = 0;
    while index < args.len() {
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("{} needs a value", args[index]))?;
        match args[index].as_str() {
            "--host" => config.host = value.clone(),
            "--port" => config.port = value.parse().map_err(|_| "invalid port".to_string())?,
            "--web-root" => config.web_root = PathBuf::from(value),
            "--artifact-root" => config.artifact_root = PathBuf::from(value),
            "--server-bytecode" => config.server_bytecode = Some(PathBuf::from(value)),
            flag => return Err(format!("unknown flag {flag}")),
        }
        index += 2;
    }
    if !config.web_root.join("index.html").is_file() {
        return Err(format!("{} has no index.html", config.web_root.display()));
    }
    if !config.artifact_root.is_dir() {
        return Err(format!(
            "{} is not an artifact directory",
            config.artifact_root.display()
        ));
    }
    Ok(config)
}

fn handle(mut stream: TcpStream, config: &Config) -> std::io::Result<()> {
    let mut buffer = vec![0u8; 1024 * 1024];
    let mut used = 0;
    loop {
        let read = stream.read(&mut buffer[used..])?;
        if read == 0 {
            return Ok(());
        }
        used += read;
        if let Some(header_end) = find(&buffer[..used], b"\r\n\r\n") {
            let header = String::from_utf8_lossy(&buffer[..header_end]).into_owned();
            let content_length = header
                .lines()
                .find_map(|line| {
                    line.strip_prefix("Content-Length:")
                        .or_else(|| line.strip_prefix("content-length:"))
                })
                .and_then(|v| v.trim().parse::<usize>().ok())
                .unwrap_or(0);
            while used < header_end + 4 + content_length {
                let read = stream.read(&mut buffer[used..])?;
                if read == 0 {
                    break;
                }
                used += read;
            }
            let body = &buffer[header_end + 4..used];
            let first = header.lines().next().unwrap_or("");
            let mut fields = first.split_whitespace();
            let method = fields.next().unwrap_or("GET");
            let target = fields.next().unwrap_or("/");
            return route(&mut stream, method, target, body, config);
        }
        if used == buffer.len() {
            return response(
                &mut stream,
                413,
                "text/plain",
                b"request too large",
                method_is_head("GET"),
            );
        }
    }
}

fn route(
    stream: &mut TcpStream,
    method: &str,
    target: &str,
    body: &[u8],
    config: &Config,
) -> std::io::Result<()> {
    let path = target.split('?').next().unwrap_or("/");
    if let Some(function) = path.strip_prefix("/__elpian/api/") {
        return run_api(stream, method, function, body, config);
    }
    let (root, relative) = if let Some(value) = path.strip_prefix("/__elpian/") {
        (&config.artifact_root, value)
    } else {
        (&config.web_root, path.trim_start_matches('/'))
    };
    let relative = if relative.is_empty() {
        "index.html"
    } else {
        relative
    };
    let file = safe_join(root, relative)
        .filter(|value| value.is_file())
        .unwrap_or_else(|| config.web_root.join("index.html"));
    match fs::read(&file) {
        Ok(bytes) => response(stream, 200, mime(&file), &bytes, method_is_head(method)),
        Err(_) => response(
            stream,
            404,
            "text/plain; charset=utf-8",
            b"not found",
            method_is_head(method),
        ),
    }
}

fn run_api(
    stream: &mut TcpStream,
    method: &str,
    function: &str,
    body: &[u8],
    config: &Config,
) -> std::io::Result<()> {
    let Some(bytecode_file) = &config.server_bytecode else {
        return response(
            stream,
            404,
            "text/plain",
            b"server VM is not configured",
            false,
        );
    };
    let Ok(bytecode) = fs::read(bytecode_file) else {
        return response(
            stream,
            503,
            "text/plain",
            b"server bytecode is unavailable",
            false,
        );
    };
    let id = format!("elpian-http-{}", REQUEST_ID.fetch_add(1, Ordering::Relaxed));
    let input = if method == "GET" {
        "{}".to_string()
    } else {
        String::from_utf8_lossy(body).into_owned()
    };

    // A guest that traps unwinds out of the executor. Contain it here so a bad
    // program fails only its own request instead of killing the connection, and
    // so the VM is destroyed on every path — the early 501 return used to leak
    // one per unserviced host call.
    let vm = id.clone();
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || {
        elpian_vm::api::init_vm_system();
        elpian_vm::api::create_vm_from_bytecode(vm.clone(), bytecode);
        let initial = elpian_vm::api::execute_vm(vm.clone());
        if initial.has_host_call {
            return (501, initial.host_call_data);
        }
        let result =
            elpian_vm::api::execute_vm_func_with_input(vm.clone(), function.to_string(), input, 1);
        if result.has_host_call {
            (501, result.host_call_data)
        } else {
            (200, result.result_value)
        }
    }));
    elpian_vm::api::destroy_vm(id);

    match outcome {
        Ok((status, payload)) => {
            let head = status == 200 && method_is_head(method);
            response(stream, status, "application/json", payload.as_bytes(), head)
        }
        Err(payload) => {
            // Log the detail server-side; the client gets a generic body so a
            // guest trap cannot leak interpreter internals to a caller.
            eprintln!(
                "elpian-server: guest trapped in {function}: {}",
                panic_detail(&payload)
            );
            response(
                stream,
                500,
                "application/json",
                br#"{"error":"the guest program trapped"}"#,
                false,
            )
        }
    }
}

/// Recover a panic payload's message, for logging a guest trap.
fn panic_detail(payload: &Box<dyn std::any::Any + Send>) -> String {
    payload
        .downcast_ref::<String>()
        .cloned()
        .or_else(|| {
            payload
                .downcast_ref::<&'static str>()
                .map(|s| s.to_string())
        })
        .unwrap_or_else(|| "unknown trap".to_string())
}

fn safe_join(root: &Path, relative: &str) -> Option<PathBuf> {
    let path = Path::new(relative);
    if path.components().any(|part| {
        matches!(
            part,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        )
    }) {
        return None;
    }
    Some(root.join(path))
}

fn response(
    stream: &mut TcpStream,
    status: u16,
    mime: &str,
    body: &[u8],
    head: bool,
) -> std::io::Result<()> {
    let label = match status {
        200 => "OK",
        404 => "Not Found",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        503 => "Service Unavailable",
        _ => "Error",
    };
    write!(stream, "HTTP/1.1 {status} {label}\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n", body.len())?;
    if !head {
        stream.write_all(body)?;
    }
    Ok(())
}

fn mime(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
    {
        "html" => "text/html; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "json" => "application/json",
        "wasm" => "application/wasm",
        "css" => "text/css; charset=utf-8",
        "png" => "image/png",
        "svg" => "image/svg+xml",
        "ico" => "image/x-icon",
        "bc" => "application/octet-stream",
        _ => "application/octet-stream",
    }
}

fn method_is_head(method: &str) -> bool {
    method == "HEAD"
}
fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}
