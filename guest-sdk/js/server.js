// =============================================================================
// server.js — the client half of the Elpian fullstack SDK.
// =============================================================================
//
// A mini app's client VM talks to its own server functions through two host
// APIs, `server.call` (an action, returns JSON) and `server.render` (a server
// component, returns a UI payload). This module is the ergonomic surface over
// them.
//
//   import 'server.js';
//
//   callServer("createNote", { title: t }, (res) => {
//     if (res.error != null) { print(res.error.message); return; }
//     notes.push(res.result);
//   });
//
// -----------------------------------------------------------------------------
// Three things about this API are forced by the js2elpian subset, not chosen
// -----------------------------------------------------------------------------
//
// 1. **Callbacks, not promises.** There is no async/await and no thenable, so a
//    call that has to wait for the host takes a continuation.
//
// 2. **Results, not exceptions.** There is no try/catch, so an error has to be
//    a *value*. Every call here hands back `{ ok, result, error }` and never
//    throws. A guest that could not catch a throw would simply trap.
//
// 3. **Explicit null checks.** `x == null` is also true for numeric `0` in this
//    subset, so `if (res.result)` is wrong whenever `0` is a legitimate result.
//    Write `if (res.error != null)`, always.
//
// The app is never a parameter. A guest cannot name another app's function
// because it never names an app at all — the host resolves within the app whose
// bytecode is running, decided when the request was routed.
// =============================================================================

// ---------------------------------------------------------------------------
// result shape
// ---------------------------------------------------------------------------

// Normalise whatever the host returned into { ok, result, error }.
//
// The host answers a refused or failed call with `null`, or with an object
// carrying `error`. Both become the same shape here so guest code has one thing
// to test rather than three.
function __srvResult(raw) {
  if (raw == null) {
    return {
      ok: false,
      result: null,
      error: { code: "unavailable", message: "the server did not answer" }
    };
  }
  if (raw.error != null) {
    var e = raw.error;
    // An error may be a bare string (the host's uniform refusal message) or an
    // object with a code.
    if (typeof e == "string") {
      return { ok: false, result: null, error: { code: "refused", message: e } };
    }
    return {
      ok: false,
      result: null,
      error: {
        code: e.code == null ? "error" : e.code,
        message: e.message == null ? "the call failed" : e.message
      }
    };
  }
  return { ok: true, result: raw, error: null };
}

// ---------------------------------------------------------------------------
// actions
// ---------------------------------------------------------------------------

// Invoke one of this app's server actions.
//
//   callServer("createNote", { title: "x" }, (res) => { ... });
//
// `cb` is optional: an action whose result nothing needs can be fired without
// one. It still runs — this is not fire-and-forget on the server side.
function callServer(name, args, cb) {
  var raw = askHost("server.call", [name, args == null ? {} : args]);
  var res = __srvResult(raw);
  if (cb != null) { cb(res); }
  return res;
}

// Bind a form or button to an action.
//
//   el("form", { onSubmit: action("createNote", (res) => { ... }) }, [ ... ])
//
// The handler receives the event, pulls its `values` (what the host collects
// from a form submit), and sends them as the action's arguments — so the
// common case needs no hand-written submit handler at all.
function action(name, cb) {
  return (ev) => {
    var args = {};
    if (ev != null && ev.values != null) { args = ev.values; }
    callServer(name, args, cb);
  };
}

// ---------------------------------------------------------------------------
// server components
// ---------------------------------------------------------------------------

// Fetch a server component's payload imperatively.
//
//   serverRender("NoteList", { page: 1 }, (res) => {
//     if (res.error != null) { return; }
//     pane = res.component;
//   });
//
// The callback's result carries `component` — the UI tree — alongside the raw
// payload, so a caller does not have to remember which key it lives under.
function serverRender(name, args, cb) {
  var raw = askHost("server.render", [name, args == null ? {} : args]);
  var res = __srvResult(raw);
  if (res.ok) {
    res.component = raw.component;
    res.stylesheet = raw.stylesheet;
    res.clientComponents = raw.clientComponents;
  } else {
    res.component = null;
  }
  if (cb != null) { cb(res); }
  return res;
}

// A server component as a *node*, for use inside a view.
//
//   serverComponent("NoteList", { page: 1 }, {
//     pending: skeleton(),
//     error:   errorCard()
//   })
//
// Returns the payload's component tree, or the caller's `pending`/`error` node.
// Deliberately synchronous: the host services `server.render` on the same
// pausing seam every other host call uses, so by the time this returns the
// answer is here. An asynchronous version would need a re-render mechanism the
// guest does not have, and would make every view that used one stateful.
function serverComponent(name, args, opts) {
  var options = opts == null ? {} : opts;
  var res = serverRender(name, args, null);
  if (res.ok && res.component != null) {
    return res.component;
  }
  if (res.error != null && options.error != null) {
    return options.error;
  }
  if (options.pending != null) {
    return options.pending;
  }
  // Nothing to show and nothing was supplied. An empty node is a better answer
  // than a crash: one failing panel should not take down the screen around it.
  return { type: "SizedBox" };
}

// ---------------------------------------------------------------------------
// islands
// ---------------------------------------------------------------------------

// Register a client-side component a server component may reference by name.
//
// A server component names an island in its `clientComponents`; the device
// resolves that name here, in the client bundle it already fetched and
// verified. Source is never shipped for the device to compile — that would be a
// second compile path on the device and a much wider trust surface.
var __srvIslands = {};

function registerIsland(name, build) {
  __srvIslands[name] = build;
}

// Resolve an island by name, or null if this bundle does not have it.
//
// A caller that gets null should render the payload's static form rather than
// failing: an app shipping a component that names an island its client half
// does not have is a deployment mistake, and a blank screen is a worse answer
// than a non-interactive one.
function island(name, props) {
  var build = __srvIslands[name];
  if (build == null) { return null; }
  return build(props == null ? {} : props);
}
