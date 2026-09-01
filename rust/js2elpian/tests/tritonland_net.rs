//! Runs the REAL net.js prelude in the VM with a stubbed Godot bridge, then
//! drives the exact call path the TritonLand boot gate uses:
//! apiSetServer(origin) -> Net.request({url:"/api/auth/me"}) -> callback.
//! Catches pure-JS failures inside the prelude (the demos never used Net,
//! so this code path is unproven on the engine).

use elpian_vm::api;

#[test]
fn net_prelude_request_path_runs_in_vm() {
    let net_src = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../prelude/net.js"))
        .expect("net.js prelude");

    // Minimal Godot-bridge stubs mirroring godot.js's surface as used by
    // net.js. The mock HTTPRequest node records the request args and lets the
    // test fire request_completed manually.
    let stubs = r#"
var __log = [];
var __mockNode = null;

function GInt(v) { return v; }
function GFloat(v) { return v; }

var Packed = {
  strings: (list) => { return list; },
};

function __makeNode(kind) {
  let n = {
    kind: kind,
    props: {},
    handlers: {},
    requestArgs: null,
    freed: false,
  };
  n.set = (k, v) => { n.props[k] = v; return null; };
  n.connect = (sig, f) => { n.handlers[sig] = f; return null; };
  n.call = (m, args) => {
    if (m == "request") {
      n.requestArgs = args;
      __log.push("request:" + args[0]);
      return 0;
    }
    return 0;
  };
  n.queueFree = () => { n.freed = true; return null; };
  return n;
}

var GD = {
  create: (kind) => {
    __mockNode = __makeNode(kind);
    return __mockNode;
  },
  mount: (n) => { __log.push("mount:" + n.kind); return null; },
  isError: (v) => { return false; },
  eval: (code, a, b) => { return null; },
  load: (p) => { return null; },
};

function __isType(v, t) { return false; }
"#;

    let driver = r#"
var __result = null;

function driveMe() {
  Net.setBase("https://tritonland.onrender.com");
  Net.request({ url: "/api/auth/me", method: "GET" }, (res) => {
    __result = { status: res.status, transport: res.transport, ok: res.ok, body: res.body, auth: res.json() };
  });
  // The engine would fire this when the HTTP response lands; replay the real
  // Render response including its Set-Cookie-free 401.
  let headers = ["Content-Type: application/json", "Set-Cookie: probe=1; Path=/"];
  __mockNode.handlers["request_completed"]([0, 401, headers, "{\"authenticated\":false}"]);
  return jsonStringify({
    url: __mockNode.requestArgs[0],
    method: __mockNode.requestArgs[2],
    timeout: __mockNode.props.timeout,
    log: __log,
    result: __result,
    cookieAfter: Net.cookieHeader(),
    freed: __mockNode.freed,
  });
}
"#;

    let program = format!("{stubs}\n{net_src}\n{driver}");
    assert!(
        js2elpian::create_vm_from_js("tl-net".to_string(), program),
        "net.js + driver failed to COMPILE in js2elpian"
    );
    let _boot = api::execute_vm("tl-net".to_string());
    let out = api::execute_vm_func("tl-net".to_string(), "driveMe".to_string(), 1);
    println!("NET DIAG: {}", out.result_value);
    let v = out.result_value;
    assert!(v.contains("https://tritonland.onrender.com/api/auth/me"), "request URL wrong: {v}");
    assert!(v.contains("status") && v.contains("401"), "callback did not deliver status: {v}");
    assert!(v.contains("transport"), "transport code missing from response: {v}");
    assert!(v.contains("probe=1"), "cookie jar did not ingest Set-Cookie: {v}");
}

/// The Socket.IO handshake path: the engine.io "0{...}" open frame arrives via
/// the websocket pump TIMER — long after SocketIO.connect's frame returned.
/// The VM captures closure locals BY VALUE, so the old code's forward
/// reference to the `ws` local inside onText was null at fire time:
/// `ws.sendText("40")` crashed the whole engine ("the specified data is not
/// runnable"). Pins the fix (reading the live handle off `sock.ws`) by
/// replaying the full handshake + an event frame through the real prelude.
#[test]
fn socketio_handshake_survives_deferred_ontext() {
    let net_src = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../prelude/net.js"))
        .expect("net.js prelude");

    // Stubs: a mock WebSocketPeer the pump can poll, plus a manual timer
    // registry so the test fires the pump exactly when it wants.
    let stubs = r#"
var __sent = [];
var __timers = [];
var __peer = null;

function GInt(v) { return v; }
function GFloat(v) { return v; }
function __isType(v, t) {
  if (t == "String") { return typeOf(v) == "string"; }
  return false;
}

var Packed = {
  strings: (list) => { return list; },
};

var GD = {
  create: (kind) => {
    let n = {
      kind: kind,
      props: {},
      state: 0,
      queue: [],
      set: null, call: null, connect: null, queueFree: null,
    };
    n.set = (k, v) => { n.props[k] = v; return null; };
    n.connect = (sig, f) => { return null; };
    n.queueFree = () => { return null; };
    n.call = (m, args) => {
      if (m == "connect_to_url") { return 0; }
      if (m == "poll") { return null; }
      if (m == "get_ready_state") { return n.state; }
      if (m == "get_available_packet_count") { return n.queue.length; }
      if (m == "get_packet") { return n.queue.pop(); }
      if (m == "was_string_packet") { return true; }
      if (m == "send_text") { __sent.push("" + args[0]); return 0; }
      if (m == "get_close_code") { return 1000; }
      return 0;
    };
    __peer = n;
    return n;
  },
  mount: (n) => { return null; },
  isError: (v) => { return false; },
};

class GTimer {
  constructor(id) { this.id = id; }
  static periodic(ms, cb) { __timers.push(cb); return new GTimer(__timers.length - 1); }
  static after(ms, cb) { __timers.push(cb); return new GTimer(__timers.length - 1); }
  cancel() { return null; }
}
"#;

    let driver = r#"
var __events = [];

function driveSio() {
  Net.setBase("https://play.example");
  let socket = SocketIO.connect(Net.base(), { path: "/socket.io" });
  socket.on("connect", (x) => { __events.push("connect"); });
  socket.on("state:update", (d) => { __events.push("state:" + d.gold); });
  // The connect frame returned; NOW the engine.io open frame arrives on a
  // later pump tick (the crash scenario).
  __peer.state = 1;
  __peer.queue.push("0{\"sid\":\"abc\",\"pingInterval\":25000}");
  __timers[0]();
  // Server acks the namespace, pings, then pushes an event.
  __peer.queue.push("40{\"sid\":\"n1\"}");
  __timers[0]();
  __peer.queue.push("2");
  __timers[0]();
  __peer.queue.push("42[\"state:update\",{\"gold\":7}]");
  __timers[0]();
  return jsonStringify({ sent: __sent, events: __events, sid: socket.sid });
}
"#;

    let program = format!("{stubs}\n{net_src}\n{driver}");
    assert!(
        js2elpian::create_vm_from_js("tl-sio".to_string(), program),
        "net.js + sio driver failed to COMPILE in js2elpian"
    );
    let _boot = api::execute_vm("tl-sio".to_string());
    let out = api::execute_vm_func("tl-sio".to_string(), "driveSio".to_string(), 1);
    println!("SIO DIAG: {}", out.result_value);
    let v = out.result_value;
    assert!(v.contains("\\\"40\\\"") || v.contains("40"), "namespace connect not sent: {v}");
    assert!(v.contains("connect"), "connect event not dispatched: {v}");
    assert!(v.contains("state:7"), "event payload not dispatched: {v}");
}
