// =============================================================================
// caspar.js — a Caspar-node protocol client for Elpian guests (Victor).
// =============================================================================
//
// Composed AFTER `godot.js` (import it with `import 'caspar.js';`). Everything
// here is user-space Elpian-JS over the reflective Godot bridge — the client
// speaks the Caspar signed binary action protocol over either transport:
//
//   * "tcp" — a `StreamPeerTCP`, polled on a guest timer (same pattern as
//     WSocket in net.js). The default on desktop/mobile.
//   * "ws"  — a `WebSocketPeer` against the node's CLIENT_WS_API_PORT. The
//     default (and only option) on web exports, where raw TCP is unavailable.
//     Each WS Binary message carries exactly one `u32be(len) || body` frame
//     in both directions (matching caspar's client ws driver), so the same
//     buffer parser serves both transports.
//
// Wire protocol (matches caspar/node/src/drivers/network/framing.rs and the
// TCP/WS client drivers):
//
//   request  : u32be(len) | lp(signature) | lp(userId) | lp(path) | lp(pktId)
//                         | payload_json           (NO tag byte on requests)
//   response : u32be(len) | 0x02 | lp(pktId) | u32be(resCode) | payload
//   update   : u32be(len) | 0x01 | lp(key)   | payload
//   ack      : u32be(1)   | 0x01     (client -> server, after each response)
//
//   lp(x) = u32be(len(x)) || utf8(x)
//
// Signing: authenticated actions carry a base64 RSA-SHA256 signature over the
// exact payload bytes. Godot's mbedTLS `Crypto.sign` produces RSASSA-PKCS#1
// v1.5, which the Caspar node accepts alongside RSA-PSS (see
// docs/API_REFERENCE.md "Request signatures"). The private key is the PEM the
// node returns from the dev `/creatures/login` action.
//
// Surface:
//
//   let node = Caspar.connect({ host: "127.0.0.1", port: 8074,
//                               onState: (s) => {} });
//   node.login("player_one", (res) => { ... });          // dev login + keys
//   node.request("/api/ping", {}, (res) => {});          // raw signed action
//   node.signal({ creatureId, programId, entityId,       // WASM creature
//                 action: "discover", payload: {} },     //   call + result
//               (result) => {});                         //   update frame
//   node.onUpdate((key, data) => {});                    // raw update frames
//   node.close();
//
// The js2elpian subset applies (no spread/destructuring/template literals/
// try-catch/regex; closures capture locals by value; `x == null` is true for
// numeric 0 — flags below avoid null checks on numbers).

// ---------------------------------------------------------------------------
// byte helpers (guest arrays of ints <-> base64 <-> PackedByteArray)
// ---------------------------------------------------------------------------

function __cspBe32At(buf, pos) {
  return buf[pos] * 16777216 + buf[pos + 1] * 65536 + buf[pos + 2] * 256 + buf[pos + 3];
}

function __cspPushBe32(out, n) {
  out.push(floor(n / 16777216) % 256);
  out.push(floor(n / 65536) % 256);
  out.push(floor(n / 256) % 256);
  out.push(n % 256);
}

// Append lp(string) = u32be(len) || utf8 bytes.
function __cspPushLp(out, s) {
  let bytes = utf8Encode("" + s);
  __cspPushBe32(out, bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out.push(bytes[i]);
  }
}

// Parse one lp field. Returns { s, pos } or null when truncated.
function __cspReadLp(buf, pos) {
  if (pos + 4 > buf.length) {
    return null;
  }
  let n = __cspBe32At(buf, pos);
  pos = pos + 4;
  if (pos + n > buf.length) {
    return null;
  }
  let s = utf8Decode(buf.slice(pos, pos + n));
  return { s: s, pos: pos + n };
}

var __cspNextPkt = 1;
var __cspSeed = 246813579;

// Deterministic LCG noise (the VM has no `random` builtin — same pattern as
// the TPS demo's frand). Uniqueness comes from the counter; the noise only
// de-collides ids across reconnecting sessions.
function __cspRand() {
  __cspSeed = (__cspSeed * 1103515245 + 12345) % 2147483648;
  return __cspSeed / 2147483648.0;
}

function __cspPktId() {
  let id = "pkt-" + __cspNextPkt + "-" + floor(__cspRand() * 1000000000.0);
  __cspNextPkt = __cspNextPkt + 1;
  return id;
}

// ---------------------------------------------------------------------------
// Caspar — the connection factory
// ---------------------------------------------------------------------------

var Caspar = {};

// Caspar.connect({ host, port, transport?, tls?, url?, path?, timeoutMs?,
//                  onState? }) -> handle
//
// transport: "tcp" | "ws" | "auto" (default auto: "ws" on web exports —
// browsers have no raw TCP — "tcp" everywhere else). Point `port` at the
// node's CLIENT_TCP_API_PORT or CLIENT_WS_API_PORT accordingly. tls: true
// dials wss:// (ws) / is not supported by the tcp path here.
//
// ws-mode addressing: `url` ("ws://… " / "wss://…") wins outright — the form
// a browser-served client uses to ride its own page origin through an HTTP
// server's /ws tunnel (an https:// page may only open wss://, and single-port
// hosts expose nothing else). Otherwise the URL is built from
// tls/host/port + optional `path`.
// onState receives "connecting" | "connected" | "error" | "closed".
Caspar.connect = (o) => {
  o = o ?? {};
  let mode = "" + (o.transport ?? "auto");
  if (mode != "tcp" && mode != "ws") {
    let isWeb = GD.os().call("has_feature", ["web"]);
    mode = isWeb == true ? "ws" : "tcp";
  }
  let st = {
    mode: mode,
    peer: GD.create(mode == "ws" ? "WebSocketPeer" : "StreamPeerTCP"),
    crypto: GD.create("Crypto"),
    key: null,
    status: "connecting",
    buf: [],
    pending: [],        // [{id, cb, deadline, done}]
    corr: [],           // [{id, cb, deadline, done}]
    updates: [],        // [cb(key, data)]
    userId: "",
    user: null,
    authed: false,
    timer: null,
    timeoutMs: 15000,
    clock: 0.0,
  };
  if (__isType(o.timeoutMs, "number") && o.timeoutMs > 0) {
    st.timeoutMs = o.timeoutMs;
  }

  let setState = (s) => {
    if (st.status == s) {
      return;
    }
    st.status = s;
    if (o.onState != null) {
      o.onState(s);
    }
  };

  // ---- outbound -----------------------------------------------------------
  // Both transports carry the same `u32be(len) || body` frame: TCP as a raw
  // stream write, WS as one Binary message per frame.

  let sendRaw = (bytes) => {
    let packed = Packed.bytesBase64(base64Encode(bytes));
    let r = null;
    if (st.mode == "ws") {
      r = st.peer.call("put_packet", [packed]);
    } else {
      r = st.peer.call("put_data", [packed]);
    }
    return !GD.isError(r);
  };

  let sendFrame = (bodyBytes) => {
    let frame = [];
    __cspPushBe32(frame, bodyBytes.length);
    for (let i = 0; i < bodyBytes.length; i++) {
      frame.push(bodyBytes[i]);
    }
    return sendRaw(frame);
  };

  let sendAck = () => {
    sendRaw([0, 0, 0, 1, 1]);
  };

  // Sign payload bytes with the login key (Godot Crypto -> PKCS#1 v1.5,
  // accepted by the node alongside PSS). Returns "" when not authed.
  let signBytes = (payloadBytes) => {
    if (!st.authed || st.key == null) {
      return "";
    }
    let hctx = GD.create("HashingContext");
    hctx.call("start", [GInt(2)]); // HashingContext.HASH_SHA256
    hctx.call("update", [Packed.bytesBase64(base64Encode(payloadBytes))]);
    let digest = hctx.call("finish");
    let sig = st.crypto.call("sign", [GInt(2), digest, st.key]);
    if (sig != null && __isType(sig, "Packed")) {
      return sig.data; // PackedByteArray unmarshals as base64 — exactly the wire form
    }
    return "";
  };

  // ---- inbound ------------------------------------------------------------

  let deliverResponse = (body) => {
    // body: 0x02 | lp(pktId) | u32be(resCode) | payload
    let r = __cspReadLp(body, 1);
    if (r == null) {
      return;
    }
    let pktId = r.s;
    let pos = r.pos;
    if (pos + 4 > body.length) {
      return;
    }
    let resCode = __cspBe32At(body, pos);
    pos = pos + 4;
    let text = "";
    if (pos < body.length) {
      text = utf8Decode(body.slice(pos, body.length));
    }
    let data = null;
    if (text != "") {
      data = jsonParse(text);
    }
    for (let i = 0; i < st.pending.length; i++) {
      let p = st.pending[i];
      if (!p.done && p.id == pktId) {
        p.done = true;
        if (p.cb != null) {
          p.cb({ ok: resCode == 0, code: resCode, data: data, raw: text });
        }
        return;
      }
    }
  };

  let deliverUpdate = (body) => {
    // body: 0x01 | lp(key) | payload
    let r = __cspReadLp(body, 1);
    if (r == null) {
      return;
    }
    let key = r.s;
    let text = "";
    if (r.pos < body.length) {
      text = utf8Decode(body.slice(r.pos, body.length));
    }
    let data = null;
    if (text != "") {
      data = jsonParse(text);
    }

    // Route creature signal results to their correlation waiters.
    if (key == "creatures/signal/result" && __isType(data, "map")) {
      let corrId = data["correlationId"];
      if (corrId != null) {
        for (let i = 0; i < st.corr.length; i++) {
          let w = st.corr[i];
          if (!w.done && w.id == corrId) {
            w.done = true;
            if (w.cb != null) {
              w.cb(data);
            }
            return;
          }
        }
      }
    }

    for (let i = 0; i < st.updates.length; i++) {
      st.updates[i](key, data);
    }
  };

  let parseFrames = () => {
    let guard = 0;
    while (guard < 32) {
      guard = guard + 1;
      if (st.buf.length < 4) {
        return;
      }
      let bodyLen = __cspBe32At(st.buf, 0);
      if (st.buf.length < 4 + bodyLen) {
        return;
      }
      let body = st.buf.slice(4, 4 + bodyLen);
      st.buf = st.buf.slice(4 + bodyLen, st.buf.length);
      if (bodyLen == 0) {
        continue;
      }
      let tag = body[0];
      if (tag == 2) {
        sendAck(); // release the server's per-connection send gate
        deliverResponse(body);
      } else if (tag == 1) {
        deliverUpdate(body); // fire-and-forget (includes "__ping" keepalives)
      }
    }
  };

  let sweepTimeouts = () => {
    for (let i = 0; i < st.pending.length; i++) {
      let p = st.pending[i];
      if (!p.done && st.clock > p.deadline) {
        p.done = true;
        if (p.cb != null) {
          p.cb({ ok: false, code: -1, data: null, error: "timeout" });
        }
      }
    }
    for (let i = 0; i < st.corr.length; i++) {
      let w = st.corr[i];
      if (!w.done && st.clock > w.deadline) {
        w.done = true;
        if (w.cb != null) {
          w.cb({ ok: false, error: "timeout", timeout: true });
        }
      }
    }
    // Compact finished waiters so the lists don't grow without bound.
    if (st.pending.length > 32) {
      let keep = [];
      for (let i = 0; i < st.pending.length; i++) {
        if (!st.pending[i].done) {
          keep.push(st.pending[i]);
        }
      }
      st.pending = keep;
    }
    if (st.corr.length > 32) {
      let keep = [];
      for (let i = 0; i < st.corr.length; i++) {
        if (!st.corr[i].done) {
          keep.push(st.corr[i]);
        }
      }
      st.corr = keep;
    }
  };

  // ---- the pump -----------------------------------------------------------

  let host = "" + (o.host ?? "127.0.0.1");
  let port = 8074;
  if (__isType(o.port, "number") && o.port > 0) {
    port = o.port;
  }

  if (st.mode == "ws") {
    let wsUrl = "";
    if (o.url != null && ("" + o.url) != "") {
      wsUrl = "" + o.url;
    } else {
      let scheme = o.tls == true ? "wss://" : "ws://";
      wsUrl = scheme + host + ":" + port;
      if (o.path != null && ("" + o.path) != "") {
        wsUrl = wsUrl + o.path;
      }
    }
    let err = st.peer.call("connect_to_url", [wsUrl]);
    if (GD.isError(err)) {
      setState("error");
    }
  } else {
    let err = st.peer.call("connect_to_host", [host, GInt(port)]);
    if (GD.isError(err)) {
      setState("error");
    }
    st.peer.call("set_no_delay", [true]);
  }

  // Append incoming bytes to the frame buffer.
  let ingest = (packed) => {
    if (!__isType(packed, "Packed")) {
      return 0;
    }
    let bytes = base64Decode(packed.data);
    for (let i = 0; i < bytes.length; i++) {
      st.buf.push(bytes[i]);
    }
    return bytes.length;
  };

  st.timer = GTimer.periodic(33, () => {
    if (st.status == "closed") {
      return;
    }
    st.clock = st.clock + 0.033;
    st.peer.call("poll");

    if (st.mode == "ws") {
      // WebSocketPeer.State: 0 CONNECTING, 1 OPEN, 2 CLOSING, 3 CLOSED.
      let s = st.peer.call("get_ready_state");
      if (s == 1) {
        if (st.status != "connected") {
          setState("connected");
        }
        let n = st.peer.call("get_available_packet_count");
        let guard = 0;
        while (__isType(n, "number") && n > 0 && guard < 64) {
          ingest(st.peer.call("get_packet"));
          n = st.peer.call("get_available_packet_count");
          guard = guard + 1;
        }
        parseFrames();
      } else if (s == 3) {
        setState(st.status == "connected" ? "closed" : "error");
      }
    } else {
      // StreamPeerTCP.Status: 0 NONE, 1 CONNECTING, 2 CONNECTED, 3 ERROR.
      let s = st.peer.call("get_status");
      if (s == 2) {
        if (st.status != "connected") {
          setState("connected");
        }
        let avail = st.peer.call("get_available_bytes");
        let drained = 0;
        while (__isType(avail, "number") && avail > 0 && drained < 262144) {
          let chunkLen = avail;
          if (chunkLen > 32768) {
            chunkLen = 32768;
          }
          let r = st.peer.call("get_partial_data", [GInt(chunkLen)]);
          if (!__isType(r, "list") || r.length < 2) {
            break;
          }
          drained = drained + ingest(r[1]);
          avail = st.peer.call("get_available_bytes");
        }
        parseFrames();
      } else if (s == 3) {
        setState("error");
      } else if (s == 0 && st.status == "connected") {
        setState("closed");
      }
    }
    sweepTimeouts();
  });

  // ---- handle -------------------------------------------------------------
  // Built incrementally: closures capture locals BY VALUE in this subset, so
  // methods that call sibling methods must capture the (already-assigned)
  // object reference, never a forward-declared literal.

  let handle = {};

  handle.status = () => st.status;
  handle.userId = () => st.userId;
  handle.user = () => st.user;
  handle.isAuthed = () => st.authed;

  // Raw signed action call. cb({ok, code, data, raw}).
  handle.request = (path, payload, cb) => {
    let payloadStr = jsonStringify(payload ?? {});
    let payloadBytes = utf8Encode(payloadStr);
    let sig = signBytes(payloadBytes);
    let pktId = __cspPktId();
    st.pending.push({
      id: pktId, cb: cb, deadline: st.clock + st.timeoutMs / 1000.0, done: false,
    });
    let body = [];
    __cspPushLp(body, sig);
    __cspPushLp(body, st.userId);
    __cspPushLp(body, "" + path);
    __cspPushLp(body, pktId);
    for (let i = 0; i < payloadBytes.length; i++) {
      body.push(payloadBytes[i]);
    }
    if (!sendFrame(body)) {
      for (let i = 0; i < st.pending.length; i++) {
        if (st.pending[i].id == pktId && !st.pending[i].done) {
          st.pending[i].done = true;
        }
      }
      if (cb != null) {
        cb({ ok: false, code: -1, data: null, error: "send failed" });
      }
    }
  };

  // Dev login: creates the account on first use, returns {user, privateKey}
  // and arms request signing. cb({ok, user, error?}).
  handle.login = (username, cb) => {
    handle.request("/creatures/login", {
      username: "" + username,
      emailToken: username + "@dev.local",
      metadata: {},
    }, (res) => {
      if (!res.ok || res.data == null || res.data.user == null) {
        if (cb != null) {
          cb({ ok: false, error: "login failed (code " + res.code + ")" });
        }
        return;
      }
      st.user = res.data.user;
      st.userId = "" + res.data.user.id;
      let pem = res.data.privateKey;
      if (pem != null && ("" + pem).length > 0) {
        let key = GD.create("CryptoKey");
        let kerr = key.call("load_from_string", ["" + pem, false]);
        if (!GD.isError(kerr) && kerr == 0) {
          st.key = key;
          st.authed = true;
        }
      }
      if (cb != null) {
        cb({ ok: true, user: st.user, authed: st.authed });
      }
    });
  };

  // Signal a WASM creature entity and wait for its result update frame.
  //   node.signal({creatureId, programId, entityId, action, payload,
  //                storeId?, timeoutMs?}, (result) => {})
  // result is the creature's JSON response (correlationId included), or
  // {ok:false, error, timeout?} on failure.
  handle.signal = (s, cb) => {
    s = s ?? {};
    let corrId = "corr-" + __cspPktId();
    let inner = {};
    inner.action = "" + (s.action ?? "");
    let payload = {};
    if (s.payload != null) {
      let ks = s.payload.keys;
      for (let i = 0; i < ks.length; i++) {
        payload[ks[i]] = s.payload[ks[i]];
      }
    }
    payload.correlationId = corrId;
    inner.payload = payload;
    let dataStr = jsonStringify({
      correlationId: corrId,
      payload: jsonStringify(inner),
    });
    let waitMs = st.timeoutMs;
    if (__isType(s.timeoutMs, "number") && s.timeoutMs > 0) {
      waitMs = s.timeoutMs;
    }
    st.corr.push({
      id: corrId, cb: cb, deadline: st.clock + waitMs / 1000.0, done: false,
    });
    handle.request("/creatures/signal", {
      type: "pvp",
      data: dataStr,
      storeId: "" + (s.storeId ?? ""),
      creatureId: "" + (s.creatureId ?? ""),
      programId: "" + (s.programId ?? ""),
      entityId: "" + (s.entityId ?? ""),
      temp: false,
    }, (res) => {
      if (!res.ok) {
        for (let i = 0; i < st.corr.length; i++) {
          let w = st.corr[i];
          if (!w.done && w.id == corrId) {
            w.done = true;
            if (cb != null) {
              cb({ ok: false, error: "signal rejected (code " + res.code + ")" });
            }
          }
        }
      }
      // On accept (passed:true) the creature's answer arrives as an update
      // frame and is routed by correlationId above.
    });
  };

  // Subscribe to raw update frames: cb(key, data).
  handle.onUpdate = (cb) => {
    st.updates.push(cb);
  };

  handle.transport = () => st.mode;

  handle.close = () => {
    if (st.status == "closed") {
      return;
    }
    st.status = "closed";
    if (st.timer != null) {
      st.timer.cancel();
    }
    if (st.mode == "ws") {
      st.peer.call("close", [GInt(1000), "bye"]);
    } else {
      st.peer.call("disconnect_from_host");
    }
    if (o.onState != null) {
      o.onState("closed");
    }
  };

  return handle;
};

// ---------------------------------------------------------------------------
// CaspiNet — the CaspiGames service-discovery convenience layer
// ---------------------------------------------------------------------------
//
// The gaming super-app pattern: one "main" discovery creature (entity id
// "main") introduces every other backend service. Given the connect-form
// values (node URL + main creature id + main program id), this resolves the
// full service registry and hands back per-service signal helpers.
//
//   let caspi = CaspiNet.open({
//     node: nodeHandle,                 // a connected+authed Caspar handle
//     mainCreatureId: "...",
//     mainProgramId: "...",
//   });
//   caspi.discover((res) => { ... });   // res.services -> registry map
//   caspi.call("games", "list", {}, (r) => {});

var CaspiNet = {};

CaspiNet.open = (o) => {
  o = o ?? {};
  let st = {
    node: o.node,
    mainCreatureId: "" + (o.mainCreatureId ?? ""),
    mainProgramId: "" + (o.mainProgramId ?? ""),
    services: {},   // name -> {name, creatureId, programId, entityId, ...}
    platform: null,
    ready: false,
  };

  let self = {
    isReady: () => st.ready,
    platform: () => st.platform,
    services: () => st.services,
    service: (name) => st.services[name],

    // Ask the main creature for the platform manifest + service registry.
    discover: (cb) => {
      st.node.signal({
        creatureId: st.mainCreatureId,
        programId: st.mainProgramId,
        entityId: "main",
        action: "discover",
        payload: {},
      }, (res) => {
        if (res != null && res.ok == true && __isType(res.services, "list")) {
          st.platform = res.platform;
          let map = {};
          for (let i = 0; i < res.services.length; i++) {
            let svc = res.services[i];
            if (__isType(svc, "map") && svc.name != null) {
              map[svc.name] = svc;
            }
          }
          st.services = map;
          st.ready = true;
        }
        if (cb != null) {
          cb(res);
        }
      });
    },

    // Call an action on a discovered service by name.
    call: (serviceName, action, payload, cb) => {
      let svc = st.services[serviceName];
      if (svc == null) {
        if (cb != null) {
          cb({ ok: false, error: "unknown service: " + serviceName });
        }
        return;
      }
      st.node.signal({
        creatureId: svc.creatureId,
        programId: svc.programId,
        entityId: svc.entityId,
        action: action,
        payload: payload,
      }, cb);
    },
  };

  return self;
};
