// =============================================================================
// elpian-server.js — the server half of the Elpian fullstack SDK.
// =============================================================================
//
// Imported by a mini app's *server* functions, never by its client. It is a
// separate module rather than part of the client SDK for a reason: a server
// function that reached for `el`, `render` or `dom` would be writing code that
// cannot run, and the shortest way to say so is not to put those names in
// scope.
//
//   // src/server/actions/createNote.js
//   import 'elpian-server.js';
//
//   function createNote(args) {
//     if (ctxUser() == null) { return { error: { code: "forbidden" } }; }
//     kvSet("note:" + args.id, args);
//     revalidate("notes");
//     return { id: args.id };
//   }
//
//   // src/server/components/NoteList.js
//   function NoteList(args) {
//     var keys = kvList("note:");
//     return ui({ type: "Column", children: rows(keys) }, ["notes"]);
//   }
//
// A component RETURNS its payload. It does not call `render` — the server
// posture denies that capability — because a component that rendered as a side
// effect could not be cached, could not be tested without a host, and could
// half-render.
//
// The same subset constraints apply as everywhere else: no spread, no
// destructuring, no template literals, no try/catch, no regex, and `x == null`
// is true for numeric 0.
// =============================================================================

// ---------------------------------------------------------------------------
// the component payload
// ---------------------------------------------------------------------------

// Wrap a UI tree as a component payload.
//
//   return ui(tree)                       // never cached
//   return ui(tree, ["notes"])            // cached until "notes" is revalidated
//   return ui(tree, ["notes"], 30)        // ...or 30 seconds pass
//
// Caching is opt-in. A component that names neither a tag nor a TTL is not
// cached at all, because caching a component that reads changing state would
// serve a stale page with no way for it to say otherwise.
function ui(component, tags, seconds) {
  var payload = { component: component };
  if (tags != null || seconds != null) {
    var r = {};
    if (tags != null) { r.tags = tags; }
    if (seconds != null) { r.seconds = seconds; }
    payload.revalidate = r;
  }
  return payload;
}

// Attach a stylesheet to a payload, returning it for chaining.
function withStylesheet(payload, stylesheet) {
  payload.stylesheet = stylesheet;
  return payload;
}

// Declare the islands this payload references, by name. The device resolves
// each out of the client bundle it already has.
function withIslands(payload, islands) {
  payload.clientComponents = islands;
  return payload;
}

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------
//
// Every key is namespaced by the host under the app it belongs to. A guest
// never sends an app id — so there is no key it can construct that reaches
// another app's state.

function kvGet(key) { return askHost("kv.get", [key]); }
function kvSet(key, value) { return askHost("kv.set", [key, value]); }
function kvDelete(key) { return askHost("kv.delete", [key]); }
function kvList(prefix) { return askHost("kv.list", [prefix == null ? "" : prefix]); }

// Tell the host that renders tagged `tag` are out of date. An app can only ever
// invalidate its own.
function revalidate(tag) { return askHost("cache.revalidate", [tag]); }

// A secret this app's manifest declared. A name that was not declared reads
// exactly like one that does not exist — deliberately, so a guest cannot probe
// for what the host holds.
function secret(name) { return askHost("secret.get", [name]); }

// ---------------------------------------------------------------------------
// the caller
// ---------------------------------------------------------------------------

// The verified caller, or null when the call is anonymous.
//
// This came from a credential the host checked. There is no setter: an identity
// a caller could assert would make every authorisation check in every app
// forgeable by exactly the person it protects against.
function ctxUser() { return askHost("ctx.user", []); }

// Whether the caller holds a role. Anonymous holds none.
function ctxHasRole(role) {
  var user = ctxUser();
  if (user == null || user.roles == null) { return false; }
  var i = 0;
  while (i < user.roles.length) {
    if (user.roles[i] == role) { return true; }
    i = i + 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// calling a sibling function
// ---------------------------------------------------------------------------
//
// Resolves inside this app. The app is not a parameter, so there is no
// cross-app check to bypass — there is nothing to forge.

function callFunction(name, args) {
  return askHost("server.call", [name, args == null ? {} : args]);
}

function renderComponent(name, args) {
  return askHost("server.render", [name, args == null ? {} : args]);
}

// ---------------------------------------------------------------------------
// environment
// ---------------------------------------------------------------------------

function now() { return askHost("time.now", []); }
function log(message) { return askHost("log", ["" + message]); }

// Outbound HTTP, if this app's network posture allows it. A closed app does not
// hold the capability at all, and this reads as null there — not as an error to
// handle, because there is nothing the guest could do about it.
function fetchUrl(url) { return askHost("net.fetch", [url]); }
