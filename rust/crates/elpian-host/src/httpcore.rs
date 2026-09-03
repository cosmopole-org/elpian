//! A small blocking HTTP/1.1 server: request parsing, responses, and a bounded
//! worker pool.
//!
//! # Why not an async runtime
//!
//! The plan flagged tokio + hyper as the likely choice and left it open. Built
//! out, the case for it is weaker than it looked:
//!
//! * Every request maps onto a **blocking, single-threaded** VM turn. Async
//!   buys its keep when work is IO-bound and interleavable; here the work is
//!   guest CPU that cannot be interleaved on one thread at all.
//! * The registry is now sharded, so a worker pool gives real parallelism —
//!   which is what the old thread-per-connection server lacked, and it lacked
//!   it because of the lock, not because of the threads.
//! * The repository's entire dependency set is `serde`, `serde_json` and
//!   `once_cell`. tokio + hyper is 24 packages and a different posture for a
//!   codebase that hand-rolls its own JSON envelope writer for cache reasons.
//!
//! What async would genuinely have bought is WebSocket streaming for S2 and
//! cheap idle connections. Both are reachable from here — RFC 6455 server-side
//! framing is small, and a bounded pool with a queue is the same backpressure
//! story — so this is reversible if the streaming work proves it wrong.
//!
//! **A bounded pool is a safety property, not a tuning knob.** Unbounded
//! thread-per-connection lets a client open sockets until the host runs out of
//! threads, and each thread here can pin a VM instance.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};

/// The largest request body accepted, before any handler sees it.
///
/// Enforced during the read rather than after, so an oversized body is refused
/// without ever being buffered.
const MAX_BODY_BYTES: usize = 8 * 1024 * 1024;

/// The largest request line + headers accepted.
const MAX_HEAD_BYTES: usize = 64 * 1024;

/// One parsed request.
#[derive(Debug, Clone)]
pub struct Request {
    pub method: String,
    pub path: String,
    /// Query string without the `?`, empty when absent.
    pub query: String,
    /// Header names lowercased, so lookups do not have to guess the casing a
    /// client used.
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

impl Request {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.get(&name.to_ascii_lowercase()).map(|s| s.as_str())
    }

    /// Path split on `/` with empty segments dropped.
    pub fn segments(&self) -> Vec<&str> {
        self.path.split('/').filter(|s| !s.is_empty()).collect()
    }
}

/// One response.
pub struct Response {
    pub status: u16,
    pub content_type: String,
    pub body: Vec<u8>,
    pub extra_headers: Vec<(String, String)>,
}

impl Response {
    pub fn json(status: u16, value: &serde_json::Value) -> Response {
        Response {
            status,
            content_type: "application/json".into(),
            body: value.to_string().into_bytes(),
            extra_headers: Vec::new(),
        }
    }

    pub fn text(status: u16, body: &str) -> Response {
        Response {
            status,
            content_type: "text/plain; charset=utf-8".into(),
            body: body.as_bytes().to_vec(),
            extra_headers: Vec::new(),
        }
    }

    pub fn bytes(status: u16, content_type: &str, body: Vec<u8>) -> Response {
        Response {
            status,
            content_type: content_type.into(),
            body,
            extra_headers: Vec::new(),
        }
    }

    pub fn with_header(mut self, name: &str, value: &str) -> Response {
        self.extra_headers.push((name.into(), value.into()));
        self
    }

    /// The error shape every endpoint uses, so a client has one thing to parse.
    pub fn error(status: u16, message: &str) -> Response {
        Response::json(status, &serde_json::json!({ "error": message }))
    }
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        413 => "Payload Too Large",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        _ => "Unknown",
    }
}

/// Read one request off the wire.
///
/// Returns `Err(status)` for a request that cannot be served at all, so the
/// caller can answer with the right code rather than dropping the connection —
/// a client that sends a too-large body deserves a 413, not a reset.
pub fn read_request(stream: &mut BufReader<TcpStream>) -> Result<Request, u16> {
    let mut line = String::new();
    let mut head_bytes = 0usize;
    if stream.read_line(&mut line).map_err(|_| 400u16)? == 0 {
        return Err(400);
    }
    head_bytes += line.len();

    let mut parts = line.split_whitespace();
    let method = parts.next().ok_or(400u16)?.to_string();
    let target = parts.next().ok_or(400u16)?.to_string();
    let (raw_path, query) = match target.split_once('?') {
        Some((p, q)) => (p.to_string(), q.to_string()),
        None => (target, String::new()),
    };
    let path = percent_decode(&raw_path);

    let mut headers = HashMap::new();
    loop {
        let mut header = String::new();
        if stream.read_line(&mut header).map_err(|_| 400u16)? == 0 {
            break;
        }
        head_bytes += header.len();
        if head_bytes > MAX_HEAD_BYTES {
            return Err(413);
        }
        let trimmed = header.trim_end();
        if trimmed.is_empty() {
            break;
        }
        if let Some((name, value)) = trimmed.split_once(':') {
            headers.insert(
                name.trim().to_ascii_lowercase(),
                value.trim().to_string(),
            );
        }
    }

    let length: usize = headers
        .get("content-length")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    if length > MAX_BODY_BYTES {
        return Err(413);
    }
    let mut body = vec![0u8; length];
    if length > 0 {
        stream.read_exact(&mut body).map_err(|_| 400u16)?;
    }

    Ok(Request {
        method,
        path,
        query,
        headers,
        body,
    })
}

/// Decode `%XX` escapes. Anything malformed is left as written rather than
/// dropped, so a path cannot be smuggled past a check by half-encoding it.
fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).ok();
            match hex.and_then(|h| u8::from_str_radix(h, 16).ok()) {
                Some(byte) => {
                    out.push(byte);
                    i += 3;
                    continue;
                }
                None => {}
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn write_response(stream: &mut TcpStream, response: &Response, head_only: bool) {
    let mut head = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n",
        response.status,
        reason(response.status),
        response.content_type,
        response.body.len()
    );
    for (name, value) in &response.extra_headers {
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    head.push_str("\r\n");
    let _ = stream.write_all(head.as_bytes());
    if !head_only {
        let _ = stream.write_all(&response.body);
    }
    let _ = stream.flush();
}

/// A fixed set of workers pulling connections off a bounded queue.
pub struct ServerHandle {
    running: Arc<AtomicBool>,
    /// The bound address, useful when the caller asked for port 0.
    pub addr: std::net::SocketAddr,
}

impl ServerHandle {
    pub fn stop(&self) {
        self.running.store(false, Ordering::Release);
        // Unblock the accept loop by connecting to ourselves once.
        let _ = std::net::TcpStream::connect(self.addr);
    }
}

/// How many connections may wait per worker before the host sheds load.
///
/// A short burst well past the worker count is ordinary traffic — a page
/// opening does not arrive one request at a time — so the queue has to absorb
/// one without shedding. It still has to be *bounded*: an unbounded queue turns
/// overload into unbounded latency, where every client waits and then times
/// out, which is worse for everyone than telling some of them to come back.
///
/// 64 per worker gives a machine-sized host a queue in the hundreds, which
/// absorbs a burst while still capping how far behind the host can fall.
pub const DEFAULT_QUEUE_PER_WORKER: usize = 64;

/// Start serving. Returns once the listener is bound, so a caller (or a test)
/// can connect immediately without polling for readiness.
pub fn serve(
    listener: TcpListener,
    workers: usize,
    handler: Arc<dyn Fn(Request) -> Response + Send + Sync>,
) -> ServerHandle {
    serve_with_queue(listener, workers, DEFAULT_QUEUE_PER_WORKER * workers.max(1), handler)
}

/// As [`serve`], with an explicit queue depth.
pub fn serve_with_queue(
    listener: TcpListener,
    workers: usize,
    queue_depth: usize,
    handler: Arc<dyn Fn(Request) -> Response + Send + Sync>,
) -> ServerHandle {
    let addr = listener.local_addr().expect("bound listener has an address");
    let running = Arc::new(AtomicBool::new(true));

    let (tx, rx) = mpsc::sync_channel::<TcpStream>(queue_depth.max(1));
    let rx = Arc::new(Mutex::new(rx));

    for n in 0..workers.max(1) {
        let rx = Arc::clone(&rx);
        let handler = Arc::clone(&handler);
        std::thread::Builder::new()
            .name(format!("elpian-http-{n}"))
            .spawn(move || loop {
                let next = {
                    let guard = rx.lock().unwrap_or_else(|p| p.into_inner());
                    guard.recv()
                };
                let Ok(stream) = next else { return };
                serve_one(stream, &*handler);
            })
            .expect("worker thread should spawn");
    }

    let accept_running = Arc::clone(&running);
    std::thread::Builder::new()
        .name("elpian-http-accept".into())
        .spawn(move || {
            for connection in listener.incoming() {
                if !accept_running.load(Ordering::Acquire) {
                    return;
                }
                let Ok(stream) = connection else { continue };
                // A full queue means every worker is busy and the backlog is
                // already deep. Answering 503 immediately is better than
                // queueing without bound and timing out much later, having held
                // the client the whole time.
                if let Err(mpsc::TrySendError::Full(refused)) = tx.try_send(stream) {
                    shed(refused);
                }
            }
        })
        .expect("accept thread should spawn");

    ServerHandle { running, addr }
}

/// Refuse a connection with 503, leaving the client able to *read* the refusal.
///
/// Writing the response and dropping the socket immediately is not enough. The
/// client is typically still sending its request when the refusal is written;
/// closing both directions at that moment resets the connection, and the
/// pending response is discarded along with it — so the client sees a broken
/// pipe rather than the 503 it was sent, and cannot tell "at capacity, retry"
/// apart from "the host is broken".
///
/// So: write the refusal, close only the write half (which the client reads as
/// end-of-response), then briefly drain what the client is still sending so the
/// close is orderly.
fn shed(mut stream: TcpStream) {
    let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(2)));
    let _ = stream.set_read_timeout(Some(std::time::Duration::from_millis(250)));
    write_response(
        &mut stream,
        &Response::error(503, "the server is at capacity"),
        false,
    );
    let _ = stream.shutdown(std::net::Shutdown::Write);
    let mut sink = [0u8; 1024];
    // Bounded: enough to let a normal request finish arriving, never enough for
    // a client to hold this thread open by sending slowly.
    for _ in 0..16 {
        match stream.read(&mut sink) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
    }
}

fn serve_one(stream: TcpStream, handler: &dyn Fn(Request) -> Response) {
    // Without these a client that opens a connection and says nothing pins a
    // worker forever, which is a denial of service that costs the client
    // nothing.
    let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(30)));
    let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(30)));

    let mut raw = match stream.try_clone() {
        Ok(clone) => clone,
        Err(_) => return,
    };
    let mut reader = BufReader::new(stream);

    let request = match read_request(&mut reader) {
        Ok(request) => request,
        Err(status) => {
            write_response(&mut raw, &Response::error(status, reason(status)), false);
            return;
        }
    };

    let head_only = request.method.eq_ignore_ascii_case("HEAD");
    let response = handler(request);
    write_response(&mut raw, &response, head_only);
}
