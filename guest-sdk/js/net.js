// =============================================================================
// net.js — Victor networking: HTTP, WebSocket and Socket.IO for Elpian guests.
// =============================================================================
//
// Composed AFTER `godot.js` (import it with `import 'net.js';`). Everything in
// here is user-space Elpian-JS over the reflective Godot bridge — the same
// seam any guest program uses, no privileged access:
//
//   * Net      — HTTP client over Godot's HTTPRequest node, with a base URL,
//                default headers and an automatic cookie jar (so cookie-based
//                sessions like the TritonLand API work out of the box).
//   * WSocket  — a WebSocket client over Godot's WebSocketPeer, polled on a
//                guest timer (it deliberately does NOT touch GD.onProcess,
//                which VReact owns for useFrame).
//   * SocketIO — a Socket.IO v4 client (Engine.IO v4, websocket transport)
//                layered on WSocket: connect / emit / on / off / close with
//                automatic handshake, namespace connect and ping/pong.
//
// The honest constraints of the js2elpian subset apply throughout (no spread,
// no destructuring, no template literals, no try/catch, no regex; `x == null`
// is also true for numeric 0). JSON is the VM's native jsonParse/jsonStringify.
//
//   import 'godot.js';
//   import 'net.js';
//
//   Net.setBase("https://play.tritonland.example");
//   Net.postJson("/api/auth/signin", { email: e, password: p }, (res) => {
//     if (res.ok) { print("signed in as " + res.json().user.username); }
//   });
//
//   let socket = SocketIO.connect("wss://play.tritonland.example", {});
//   socket.on("game:event", (data) => { print(data.type); });
//   socket.emit("presence:ping", { at: 1 });

// ---------------------------------------------------------------------------
// shared state: base URL, default headers, cookie jar
// ---------------------------------------------------------------------------

var __netState = { base: "", headers: {}, cookieNames: [], cookieValues: [], insecure: false };

var Net = {};

// Set the API origin every relative path is resolved against.
Net.setBase = (url) => {
  __netState.base = "" + url;
};

Net.base = () => {
  return __netState.base;
};

// Set (or clear with null) a default header sent on every request.
Net.setHeader = (name, value) => {
  __netState.headers[name] = value;
};

// Allow self-signed TLS (development engines only).
Net.setInsecureTls = (v) => {
  __netState.insecure = v == true;
};

// Resolve a possibly-relative URL against the configured base.
Net.resolve = (url) => {
  let u = "" + url;
  if (u.startsWith("http://") || u.startsWith("https://") || u.startsWith("ws://") || u.startsWith("wss://")) {
    return u;
  }
  return __netState.base + u;
};

// ---- cookie jar ------------------------------------------------------------

function __netSetCookie(name, value) {
  for (let i = 0; i < __netState.cookieNames.length; i++) {
    if (__netState.cookieNames[i] == name) {
      __netState.cookieValues[i] = value;
      return;
    }
  }
  __netState.cookieNames.push(name);
  __netState.cookieValues.push(value);
}

// Ingest one raw `Set-Cookie:` header value.
function __netIngestSetCookie(raw) {
  let semi = raw.indexOf(";");
  let pair = raw;
  if (semi >= 0) {
    pair = raw.substring(0, semi);
  }
  let eq = pair.indexOf("=");
  if (eq <= 0) {
    return;
  }
  let name = pair.substring(0, eq).trim();
  let value = pair.substring(eq + 1, pair.length).trim();
  __netSetCookie(name, value);
}

// The current `Cookie:` request-header value ("" when the jar is empty).
Net.cookieHeader = () => {
  let out = "";
  for (let i = 0; i < __netState.cookieNames.length; i++) {
    if (out != "") {
      out = out + "; ";
    }
    out = out + __netState.cookieNames[i] + "=" + __netState.cookieValues[i];
  }
  return out;
};

// Read one cookie's value ("" when absent).
Net.cookie = (name) => {
  for (let i = 0; i < __netState.cookieNames.length; i++) {
    if (__netState.cookieNames[i] == name) {
      return __netState.cookieValues[i];
    }
  }
  return "";
};

Net.clearCookies = () => {
  __netState.cookieNames = [];
  __netState.cookieValues = [];
};

// ---------------------------------------------------------------------------
// HTTP — Godot HTTPRequest, one throwaway node per request
// ---------------------------------------------------------------------------

// HTTPClient method codes (stable Godot API).
function __netMethodCode(m) {
  let mm = ("" + m).upper();
  if (mm == "GET") { return 0; }
  if (mm == "HEAD") { return 1; }
  if (mm == "POST") { return 2; }
  if (mm == "PUT") { return 3; }
  if (mm == "DELETE") { return 4; }
  if (mm == "OPTIONS") { return 5; }
  if (mm == "PATCH") { return 8; }
  return 0;
}

// Decode a response PackedByteArray (unmarshaled as Packed u8/base64) to text.
function __netBodyText(body) {
  if (body == null) {
    return "";
  }
  if (__isType(body, "string")) {
    return body;
  }
  if (__isType(body, "Packed")) {
    let bytes = base64Decode(body.data);
    return utf8Decode(bytes);
  }
  return "" + body;
}

// Perform one HTTP request.
//
//   Net.request({ url, method, headers (map), body (string), json (any),
//                 timeout (seconds) }, cb)
//
// cb receives { ok, status, headers (lower-cased map), body (string),
// json() (parsed body or null) }. Transport failures surface as status 0.
Net.request = (o, cb) => {
  o = o ?? {};
  let url = Net.resolve(o.url ?? "/");
  let method = o.method ?? "GET";
  let bodyStr = "";
  let hdrs = [];
  let sentTypes = { ct: false };

  if (o.json != null) {
    bodyStr = jsonStringify(o.json);
    hdrs.push("Content-Type: application/json");
    sentTypes.ct = true;
  } else if (o.body != null) {
    bodyStr = "" + o.body;
  }

  // default headers, then per-request headers
  let dks = __netState.headers.keys;
  for (let i = 0; i < dks.length; i++) {
    if (__netState.headers[dks[i]] != null) {
      hdrs.push(dks[i] + ": " + __netState.headers[dks[i]]);
    }
  }
  if (o.headers != null) {
    let ks = o.headers.keys;
    for (let i = 0; i < ks.length; i++) {
      hdrs.push(ks[i] + ": " + o.headers[ks[i]]);
      if (("" + ks[i]).lower() == "content-type") {
        sentTypes.ct = true;
      }
    }
  }
  if (!sentTypes.ct && bodyStr != "" && o.json == null) {
    hdrs.push("Content-Type: text/plain");
  }
  let cookieLine = Net.cookieHeader();
  if (cookieLine != "") {
    hdrs.push("Cookie: " + cookieLine);
  }
  hdrs.push("Accept: application/json, text/plain, */*");

  let node = GD.create("HTTPRequest");
  if (o.timeout != null) {
    node.set("timeout", GFloat(o.timeout));
  } else {
    node.set("timeout", GFloat(30.0));
  }
  if (__netState.insecure) {
    node.set("tls_options", GD.eval("TLSOptions.client_unsafe()", [], []));
  }
  GD.mount(node);

  node.connect("request_completed", (a) => {
    // a = [result, response_code, headers (PackedStringArray), body (PackedByteArray)]
    // result is HTTPRequest.Result: 0 OK, 2 CANT_CONNECT, 3 CANT_RESOLVE,
    // 4 CONNECTION_ERROR, 5 TLS_HANDSHAKE_ERROR, 13 TIMEOUT, ...
    let transport = a[0];
    let status = a[1];
    let rawHeaders = a[2];
    let headerMap = {};
    let list = rawHeaders;
    if (__isType(rawHeaders, "Packed")) {
      list = rawHeaders.data;
    }
    if (__isType(list, "list")) {
      for (let i = 0; i < list.length; i++) {
        let line = "" + list[i];
        let colon = line.indexOf(":");
        if (colon > 0) {
          let hname = line.substring(0, colon).trim().lower();
          let hvalue = line.substring(colon + 1, line.length).trim();
          headerMap[hname] = hvalue;
          if (hname == "set-cookie") {
            __netIngestSetCookie(hvalue);
          }
        }
      }
    }
    let text = __netBodyText(a[3]);
    let res = {
      ok: status >= 200 && status < 300,
      status: status,
      transport: transport,
      headers: headerMap,
      body: text,
      json: () => {
        if (text == "") {
          return null;
        }
        return jsonParse(text);
      },
    };
    node.queueFree();
    if (cb != null) {
      cb(res);
    }
  });

  let err = node.call("request", [url, Packed.strings(hdrs), GInt(__netMethodCode(method)), bodyStr]);
  if (GD.isError(err)) {
    node.queueFree();
    if (cb != null) {
      cb({ ok: false, status: 0, transport: -1, headers: {}, body: "", json: () => { return null; } });
    }
  }
};

Net.get = (url, cb) => {
  Net.request({ url: url, method: "GET" }, cb);
};

Net.postJson = (url, data, cb) => {
  Net.request({ url: url, method: "POST", json: data }, cb);
};

Net.putJson = (url, data, cb) => {
  Net.request({ url: url, method: "PUT", json: data }, cb);
};

Net.del = (url, cb) => {
  Net.request({ url: url, method: "DELETE" }, cb);
};

// Fetch a URL's bytes and hand back a base64 string (textures, GLB payloads).
Net.getBytes = (url, cb) => {
  let o = {};
  o.url = url;
  o.method = "GET";
  let node = GD.create("HTTPRequest");
  node.set("timeout", GFloat(60.0));
  GD.mount(node);
  node.connect("request_completed", (a) => {
    let status = a[1];
    let b64 = "";
    if (__isType(a[3], "Packed")) {
      b64 = a[3].data;
    }
    node.queueFree();
    if (cb != null) {
      cb({ ok: status >= 200 && status < 300, status: status, base64: b64 });
    }
  });
  let hdrs = [];
  let cookieLine = Net.cookieHeader();
  if (cookieLine != "") {
    hdrs.push("Cookie: " + cookieLine);
  }
  let err = node.call("request", [Net.resolve(url), Packed.strings(hdrs), GInt(0), ""]);
  if (GD.isError(err)) {
    node.queueFree();
    if (cb != null) {
      cb({ ok: false, status: 0, base64: "" });
    }
  }
};

// ---------------------------------------------------------------------------
// WSocket — WebSocketPeer polled on a guest timer
// ---------------------------------------------------------------------------
//
// let ws = WSocket.connect("wss://host/path", {
//   headers: { Cookie: "sid=..." },
//   onOpen: () => {}, onText: (s) => {}, onClose: (code) => {}, onError: () => {},
// });
// ws.sendText("hi");  ws.close();  ws.isOpen()

var WSocket = {};

WSocket.connect = (url, o) => {
  o = o ?? {};
  let peer = GD.create("WebSocketPeer");
  if (o.headers != null) {
    let lines = [];
    let ks = o.headers.keys;
    for (let i = 0; i < ks.length; i++) {
      lines.push(ks[i] + ": " + o.headers[ks[i]]);
    }
    peer.set("handshake_headers", Packed.strings(lines));
  }
  let st = { open: false, closed: false, timer: null };

  let handle = {
    peer: peer,
    isOpen: () => st.open,
    isClosed: () => st.closed,
    sendText: (s) => {
      if (st.open) {
        peer.call("send_text", ["" + s]);
      }
    },
    close: (code, reason) => {
      if (!st.closed) {
        peer.call("close", [GInt(code ?? 1000), "" + (reason ?? "")]);
      }
    },
  };

  let finish = (code) => {
    if (st.closed) {
      return;
    }
    st.closed = true;
    st.open = false;
    if (st.timer != null) {
      st.timer.cancel();
    }
    if (o.onClose != null) {
      o.onClose(code);
    }
  };

  let err = peer.call("connect_to_url", [Net.resolve(url)]);
  if (GD.isError(err)) {
    st.closed = true;
    if (o.onError != null) {
      o.onError("connect failed");
    }
    return handle;
  }

  // Pump the peer ~30x/s: poll, drain packets, watch the state machine.
  st.timer = GTimer.periodic(33, () => {
    if (st.closed) {
      return;
    }
    peer.call("poll");
    let state = peer.call("get_ready_state");
    if (state == 1) {
      if (!st.open) {
        st.open = true;
        if (o.onOpen != null) {
          o.onOpen();
        }
      }
      let n = peer.call("get_available_packet_count");
      let guard = 0;
      while (n > 0 && guard < 64) {
        let pkt = peer.call("get_packet");
        let wasText = peer.call("was_string_packet");
        if (wasText == true) {
          let text = __netBodyText(pkt);
          if (o.onText != null) {
            o.onText(text);
          }
        } else {
          if (o.onBinary != null && __isType(pkt, "Packed")) {
            o.onBinary(pkt.data);
          }
        }
        n = peer.call("get_available_packet_count");
        guard = guard + 1;
      }
    } else if (state == 3) {
      let code = peer.call("get_close_code");
      finish(code);
    }
  });

  return handle;
};

// ---------------------------------------------------------------------------
// SocketIO — Socket.IO v4 over the websocket transport
// ---------------------------------------------------------------------------
//
// Engine.IO framing (websocket transport): "0{handshake}" open, "2" ping,
// "3" pong, "4" message. Socket.IO packets ride inside "4": "40" connect,
// "41" disconnect, "42[event, ...args]" event. Default namespace only.
//
// let socket = SocketIO.connect("wss://host", { path: "/socket.io" });
// socket.on("connect", () => {});
// socket.on("chat:new", (payload) => {});
// socket.emit("hello", { a: 1 });
// socket.close();

var SocketIO = {};

function __sioDispatch(sock, event, payload) {
  for (let i = 0; i < sock.handlers.length; i++) {
    if (sock.handlers[i].event == event) {
      sock.handlers[i].cb(payload);
    }
  }
}

SocketIO.connect = (baseUrl, o) => {
  o = o ?? {};
  let path = o.path ?? "/socket.io";
  let url = "" + baseUrl;
  // http(s) -> ws(s)
  if (url.startsWith("https://")) {
    url = "wss://" + url.substring(8, url.length);
  } else if (url.startsWith("http://")) {
    url = "ws://" + url.substring(7, url.length);
  }
  let full = url + path + "/?EIO=4&transport=websocket";

  let sock = {
    handlers: [],
    connected: false,
    sid: "",
    ws: null,
    on: null,
    off: null,
    emit: null,
    close: null,
  };

  let headers = {};
  let cookieLine = Net.cookieHeader();
  if (cookieLine != "") {
    headers["Cookie"] = cookieLine;
  }
  if (o.headers != null) {
    let ks = o.headers.keys;
    for (let i = 0; i < ks.length; i++) {
      headers[ks[i]] = o.headers[ks[i]];
    }
  }

  let ws = WSocket.connect(full, {
    headers: headers,
    onText: (msg) => {
      if (msg.length == 0) {
        return;
      }
      let kind = msg.substring(0, 1);
      if (kind == "0") {
        // Engine.IO open — reply with a Socket.IO namespace connect.
        let hs = jsonParse(msg.substring(1, msg.length));
        if (hs != null && hs.sid != null) {
          sock.sid = hs.sid;
        }
        let auth = "";
        if (o.auth != null) {
          auth = jsonStringify(o.auth);
        }
        // NOTE: read the live peer handle off `sock`, not the `ws` local —
        // this callback outlives the connect frame, and the VM's by-value
        // closure capture would see the forward-declared local as null.
        sock.ws.sendText("40" + auth);
      } else if (kind == "2") {
        // ping -> pong
        sock.ws.sendText("3");
      } else if (kind == "4") {
        let sio = msg.substring(1, msg.length);
        let t = sio.substring(0, 1);
        if (t == "0") {
          sock.connected = true;
          __sioDispatch(sock, "connect", null);
        } else if (t == "1") {
          sock.connected = false;
          __sioDispatch(sock, "disconnect", null);
        } else if (t == "2") {
          // "2[...json array...]" — possibly with an ack id we ignore.
          let payload = sio.substring(1, sio.length);
          let bracket = payload.indexOf("[");
          if (bracket >= 0) {
            let arr = jsonParse(payload.substring(bracket, payload.length));
            if (arr != null && arr.length > 0) {
              let event = "" + arr[0];
              let data = null;
              if (arr.length > 1) {
                data = arr[1];
              }
              __sioDispatch(sock, event, data);
            }
          }
        }
      }
    },
    onClose: (code) => {
      sock.connected = false;
      __sioDispatch(sock, "disconnect", code);
    },
    onError: () => {
      __sioDispatch(sock, "connect_error", null);
    },
  });

  sock.ws = ws;
  sock.on = (event, cb) => {
    sock.handlers.push({ event: event, cb: cb });
  };
  sock.off = (event) => {
    let out = [];
    for (let i = 0; i < sock.handlers.length; i++) {
      if (sock.handlers[i].event != event) {
        out.push(sock.handlers[i]);
      }
    }
    sock.handlers = out;
  };
  sock.emit = (event, data) => {
    let arr = [];
    arr.push(event);
    if (data != null) {
      arr.push(data);
    }
    ws.sendText("42" + jsonStringify(arr));
  };
  sock.close = () => {
    ws.sendText("41");
    ws.close(1000, "bye");
  };
  return sock;
};
