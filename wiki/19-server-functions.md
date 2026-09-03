# 19 — Server functions

A server function is one exported function in one bytecode module, invoked by
name. This chapter is what an author needs to write one.

---

## 1. The layout

```text
elpian.app.json          the manifest
src/client.js            the client half
src/server/actions/*.js      → one action per file
src/server/components/*.js   → one component per file
build/client.bc
build/fn/<name>.bc       one module per function
```

**One module per function, not one bundle.** This is what makes independent load
and unload possible, which is the whole serverless requirement — a single bundle
would have to be resident whenever any one function was called.

The kind is declared in the manifest, and the directory convention is what the
CLI reads to write it. Not decorators: the subset has none, and evaluating guest
code at build time to read a registration table would be worse.

## 2. Writing one

```js
import 'elpian-server.js';

// An action.
function createNote(args) {
  if (ctxUser() == null) { return { error: { code: "forbidden" } }; }
  kvSet("note:" + args.id, args);
  revalidate("notes");
  return { id: args.id };
}

// A component.
function NoteList(args) {
  var keys = kvList("note:");
  return ui({ type: "Column", props: {}, children: rows(keys) }, ["notes"], 60);
}
```

`ui(tree, tags, seconds)` builds the payload. Both cache arguments are optional
and **caching is opt-in**: a component that names neither a tag nor a TTL is not
cached, because caching one that reads changing state would serve a stale page
with no way for it to say otherwise.

## 3. What a server function may reach

| Call | Capability | Notes |
|---|---|---|
| `log(msg)` | `logging` | |
| `kvGet` / `kvSet` / `kvDelete` / `kvList` | `state` | app-scoped by the *host* |
| `revalidate(tag)` | `state` | invalidates this app's cached renders only |
| `secret(name)` | `state` | manifest-declared names only |
| `ctxUser()` / `ctxHasRole(r)` | `state` | host-verified; no setter exists |
| `now()` | `clock` | |
| `callFunction` / `renderComponent` | `server_call` | siblings in **this** app |
| `fetchUrl(url)` | `network` | absent entirely in `closed` mode |
| `fs.*` | `storage` | rooted in the app's own directory |

And what it may **not**, each for a reason: `render` and the surface ops (a
component returns, it does not draw), `dom`/`canvas` (there is no document on a
server), `timers` (a timer outliving the invocation has nothing to fire into),
`vm_manage` (instances are the host's, and a guest-spawned one would be outside
the pool and the meters), `tasks` (spends host threads rather than guest
instructions, escaping the budget), `module_import` (an app's server code is
what was packaged and verified), and `environment`.

## 4. Scoping is the host's job

A guest never sends an app id — for state, for files, or for calling a sibling.
There is no key it can construct that reaches another app's data, and no
argument to `callFunction` that names another app's function. That is a property
of *where the scoping happens*, not of what the names look like.

The same is true of `ctx.user`: it comes from a credential the host verified. If
identity came from anywhere the caller controls, every authorisation check in
every app would be forgeable by exactly the person it protects against.

An undeclared secret reads exactly like a nonexistent one — deliberately, so a
guest cannot probe for what the host holds.

## 5. Warm instances keep module state

An instance stays loaded between calls, with its module-level state intact. That
is what makes the pool worth having, and it is what guest authors expect.

**It is also a path by which one caller's data can reach another**, for any
function that stashes something derived from `ctx.user` in a module variable.
Set `stateless` on such a function and it gets a fresh instance every call.

```js
// Fine warm: derived from arguments only.
var cache = {};

// NOT fine warm: outlives the caller it belongs to.
var lastUser = null;
```

An instance that trapped is discarded rather than reused — whatever left it in
that state is still in its module scope.

## 6. Bounds

Four, and they bound different things:

* **Instructions** — how much a guest computes. Does nothing about time.
* **Wall-clock deadline** — how long it holds an instance. A guest parked in a
  host call that never returns burns no instructions and runs forever.
* **Host calls per invocation** — a guest looping on `kv.get` spends its time in
  *host* code, and each round trip costs the host far more than the guest's
  budget.
* **Call depth** — a chain of `callFunction` is bounded at 8. Each level holds
  an instance and a stack frame.

## 7. Traps

A guest fault becomes an ordinary trap on that instance. The reason goes to the
operator's log; the caller gets HTTP 500 and "the function failed". An
interpreter trap message describes the guest's internals, and the caller of a
mini app's action has no business reading code they cannot see and did not
write.
