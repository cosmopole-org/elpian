# 14 — Gotchas (read this before writing code)

The concentrated list of mistakes that look fine but break at runtime. If your
program fails on the first run, the cause is almost certainly here.

---

## Language / compiler

### 1. There is no `async` / `await` — the VM has no event loop

`async` and `await` are rejected at build time, in both statement and expression
position:

```
elpian: server: "js: `async` functions are not supported — the Elpian VM has no
event loop; use the timer host APIs (setTimeout/setInterval) and callback style instead"
```

There is no Promise, no microtask queue, and no opcode to suspend on one. Deferred
work uses `setTimeout`/`setInterval` calling a named function
([`12-host-apis.md`](12-host-apis.md)).

> **On an older toolchain this was the worst trap in the system.** `async` used to
> compile *cleanly* and produce a program that trapped the VM on first call
> (`executor.rs:459: the specified data is not runnable`) — and on
> the old `elpian-server` that trap poisoned a global lock, so every later request to the
> process died with a dropped connection while the listener stayed up looking
> healthy. Both halves are fixed now (rejection in `js2elpian`, poison recovery
> in `api.rs`), but if you see that signature, you are on an old build.

### 1b. Closures capture correctly — but check your toolchain

Every closure form captures as JavaScript specifies, including an arrow nested
inside an arrow:

```ts
items.map((item) => el('li', { onClick: () => { picked = item; } }, []))
```

> **On an older toolchain this silently read `null`.** Arrows are lifted into
> synthetic hoisted definitions, drained by `parse_statement` — but a concise
> body (`=> expr`) never passes through one, so an inner arrow's definition
> bubbled *past* the outer arrow and was hoisted outside it, losing the outer
> parameter. It compiled, ran, and produced null with no error anywhere. Fixed in
> `finish_arrow`, which now drains its own lifts into the arrow's body. If a
> captured loop item reads as null, you are on an old build.

### 1c. A guest property named `type` is ordinary — but check your toolchain

`{ type: 'directional', energy: lightEnergy / 10 }` is a perfectly normal object.
Scene-DSL nodes are built almost entirely out of `type` keys.

> **On an older toolchain this corrupted every other value in the same object
> literal.** The closure-capture transform walks the AST generically and decided
> "is this JSON object a node?" by testing for the presence of a `type` key. An
> object literal's property map is keyed by *your* property names, so a `type`
> property made the map look like a node: the walker handed it to the rewriter,
> matched no node kind, and never descended into the sibling values. A captured
> variable read there kept its unrewritten form and evaluated to its **box**, so
> `lightEnergy / 10` became `[14] / 10` and trapped the VM with
>
> ```
> elpian error: array can not be divisioned with other types
> ```
>
> while `n + 0` silently produced `[14, 0]`. The trap fired at the *top level*,
> before the first `render()`, so the host had no view at all — the spinner
> flashed and the screen went white, with nothing in the app to explain it.
> Fixed by requiring `type` to be a **string** to count as a node tag. It only
> bit variables that were actually boxed, which is why a cut-down repro of the
> same code could pass while the real program failed.

### 2. There is no `fetch`, `window`, `document`, or `localStorage`

They compile to undefined identifiers and fail at runtime the same way. All I/O
goes through `askHost`.

### 3. Generators and anonymous `export default` fail the parse

```
elpian: client: "js: expected identifier, found Punct(\"*\")"
```

Named `export default function name()` is fine. `export { a as b }` silently
loses the alias — only `a` exists.

### 4. The bundler is textual — one flat scope

`import` lines are regex-matched, dependencies are inlined **above** you, and
`export` keywords are stripped. Consequences:

- Two modules defining `helper` **collide**. Prefix top-level names.
- `import { el as e }` does not work — named imports are not bindings, they are
  a promise that the name exists globally.
- Circular imports are deduplicated by a `seen` set; the second visit is skipped,
  which can leave a name undefined at call time.

### 5. TypeScript types are erased, never enforced

`function f(x: number)` will happily receive a string. Validate at runtime if it
matters.

---

## The UI model

### 6. Handlers go in `events`, not `props` — this is the #1 UI bug

```json
✅ { "type": "button", "props": { "text": "Go" }, "events": { "click": "go" } }
❌ { "type": "button", "props": { "text": "Go", "onClick": "go" } }
```

`ElpianNode.fromJson` reads handlers **only** from top-level `json['events']`.
Nothing maps `props.onClick`. And `EventEnabledWidget` returns the child
**unwrapped** when `events` is null or empty — so **no GestureDetector is
attached at all**. The button renders perfectly and ignores every tap, with no
error anywhere.

The generated SDK's `el()` does the `on*` → `events` split for you. If you write
your own node builder, you must replicate it.

### 7. Nothing is reactive — you must call `render()` yourself

Mutating a variable does not redraw. Every handler ends with `render(view())`.

### 8. Handlers cross the wire as names — but the SDK accepts closures

The `events` map can only carry strings, because `render()` uses
`JSON.stringify`. The generated SDK bridges this: an `on*` closure is stored in
a guest-side registry keyed by the node's `key`, and the wire gets a dispatcher
name. So `onClick: () => { … }` works and captures loop variables.

If you write your own node builder instead of using the SDK's `el()`, closures
will be **silently dropped** — `JSON.stringify` removes function values, leaving
`events: {}` and gotcha #6.

### 9. Always set `key` on interactive nodes

Without it the element id is a synthesised `element_<hashCode>` that changes
across rebuilds, so event routing and scope patching become unstable.

### 10. Handlers run in a *later turn*

A host call is a suspension point. Do not assume a handler has run by the next
line after the render that drew its button.

### 11. Don't re-render on every keystroke

`onInput` firing `render()` resets the field's cursor. Keep the model in sync in
the handler and render on commit.

### 12. A scoped render targeting a missing key is dropped, not escalated

By design — it must not fall back to replacing the whole view. Look for:

```
ElpianVmWidget: scoped render targeted missing scope "…"; keeping current view
```

---

## Widgets & styling

### 13. `Button` consumes part of its own style

Background, foreground, padding, border radius and elevation (from `boxShadow`)
are folded into its `ButtonStyle`; only `margin`, `opacity` and `width`/`height`
are applied around it afterwards. Other properties will not land — wrap it in a
styled `div`/`Container` instead.

### 14. `Button` dispatches both `click` **and** `tap`

If you register handlers for both names on the same button, both fire.

### 15. A subtree containing a 3D scene is viewport-locked

`Scene3D` / `scene3d` within 6 levels of the root disables document scrolling for
the whole screen — a scene cannot be measured for intrinsic height. Put scrolling
UI *beside* a scene, not around it.

### 15b. `flex` only means something inside a flex container

```ts
❌ el('div', { style: { padding: '14' } }, [           // not display:flex
     el('div', { style: { flex: 1 } }, [ … ]),        // flex is meaningless here
   ])
✅ el('div', { style: { display: 'flex', flexDirection: 'column', padding: '14' } }, [
     el('div', { style: { flex: 1 } }, [ … ]),
   ])
```

CSS ignores `flex` on a child of a non-flex parent. Flutter is far less
forgiving: `flex` becomes a `Flexible`, and a `Flexible` that is not a direct
child of a `Row`/`Column` throws while applying parent data, which **aborts the
build of the entire subtree** — a white screen whose reported error points
nowhere near the offending node.

The engine now degrades instead: a `Flexible` about to be placed somewhere other
than a flex parent is unwrapped, so a misplaced `flex` is a cosmetic no-op. Set
`display: 'flex'` on the parent to actually get the behaviour you wanted.

### 16. `%` sizing needs a bounded parent

Percentages resolve against the parent's content box via `FractionallySizedBox`.
With an unbounded parent axis the viewport-resolved pixel fallback is used, which
is usually not what you meant.

---

## The CLI & deployment

### 17. `basePath` is a build-time decision, not a proxy setting

Serving under `/myapp/` requires `"basePath": "/myapp/"` **and a rebuild** —
`index.html` bakes in `<base href="…">`. Get it wrong and the browser requests
`/main.dart.js` at the domain root and 404s, with no error in the app itself.

### 18. Deploy `dist/web`, not the Flutter project's `build/web`

`dist/web` is the engine *plus* `__elpian/` (manifest + VM artifacts). The raw
Flutter output has no application in it.

### 19. `elpian run dev` serves the engine directory, not your `dist/web`

It serves `cli/elpian_client/build/elpian-engine/<base>/`. Engines are keyed by
**base path**, so two projects with different `basePath`s coexist and switching
between them is a cache hit rather than a rebuild.

> Before this was keyed, every project shared `build/web`: building any project
> re-based the engine out from under every other one, and the clobbered app then
> requested its assets at the **domain root** and rendered a blank page with
> nothing in the app to explain why. If you see a blank Flutter page, check
> `base href` in the served `index.html` first.

### 19b. A stale Flutter build cache silently drops package assets

After moving or renaming a checkout, `flutter build web` can emit a bundle with
**none** of `elpian_ui`'s declared assets — no `elpian_wasm_loader.js`, no
`elpian_vm_bg.wasm` — while still reporting success. The app then loads, fails to
start the VM, and shows:

```
Failed to create VM: NoSuchMethodError: method not found: 'elpian_wasm_init'
```

The pubspec is fine and the files exist; the cached asset manifest still points
at the old path. Fix:

```sh
cd cli/elpian_client && flutter clean && flutter pub get
```

Worth checking directly when a web build misbehaves:

```sh
find <engine>/assets/packages/elpian_ui/assets/web_runtime -type f | wc -l   # expect 6
```

### 20. A stale engine may not be rebuilt when you expect

Rebuild is decided by `<engine>/.elpian_runtime`: missing marker, mismatched
`basePath=` line, or `lib/main.dart` / `elpian_vm_widget.dart` /
`api_web.dart` newer than the marker. Editing anything else in `elpian_ui` will
**not** trigger a rebuild — pass `--build-engine` to force it.

---

## The server template

### 21. A fresh VM per request — no state survives

Module-level variables reset on every call. There are no sessions, no caches, no
counters.

### 22. No host calls at all — including `console.log`

`console.log` lowers to `askHost("log", …)`, which the old `elpian-server` did not
service. An unhandled host call returns **HTTP 501** with the host-call data as
the body. This applies to top-level code too: a host call while the program
initialises fails before your function is reached.

### 23. An unknown function name returns `200`, not `404`

The body is `"[undefined]"`. Check the response shape, not the status code.

---

## Governance

### 24. A disabled capability returns null — it does not throw

By design: "the executor does not suspend to the host: it short-circuits the
call to a typed null, so a guest can keep running deterministically with an
interface unplugged rather than crashing." Write guest code that tolerates null
from any host call.

### 25. Tightening a limit below current usage traps on the next charge

`set_limits` retains already-consumed usage. That is a deliberate lever, but it
means lowering a budget can kill a healthy instance immediately.

### 26. A parent is billed for its whole subtree

Aggregate accounting means a hung child eventually costs the parent, its other
children, and the hung child their lives — the "handle it or share its fate"
rule. You cannot escape a budget by spawning helpers.

### 27. A parent cannot grant a capability it lacks

Effective capabilities are the AND along the ancestor path. A VM absent from the
local-grants map is treated as **allow-all** — that is the root posture, and it
means forgetting to grant explicitly gives a child *everything the parent has*.

### 28. QuickJS bypasses governance entirely

`ElpianRuntime.quickJs` is a real JS engine, not the Elpian bytecode VM.
Capabilities, resource meters and the VM tree do not apply. Never use it for
untrusted code.

---

## Quick triage

| Symptom | Look at |
|---|---|
| Button renders but does nothing | #6 — handler is in `props` not `events` |
| `async functions are not supported` | #1 — use timers, not `async` |
| A captured loop item reads as null in a handler | #1b — pre-fix toolchain |
| Server dies after one bad request | #1 — poisoned lock; you are on a pre-fix build |
| Assets 404 at the domain root | #17 — `basePath`, or #19 a clobbered engine |
| Blank screen, spinner flashed first | #1c (guest trapped before first render) or #15b (stray `flex`) |
| `array can not be divisioned with other types` | #1c — pre-fix toolchain |
| `method not found: 'elpian_wasm_init'` | #19b — stale build cache; `flutter clean` |
| UI does not update after a state change | #7 — call `render()` |
| Text field cursor jumps | #11 — re-rendering on input |
| Handler fires for the wrong item | #8, #9 — closures / missing `key` |
| `javascript parse error` | #3 — generators, anonymous default export |
| A name is mysteriously undefined | #4 — bundler scope / circular import |
| Style property ignored on a button | #13 |
| Screen will not scroll | #15 — 3D scene in the subtree |
| Server function returns `"[undefined]"` | #23 — wrong function name |

---

## Fullstack gotchas

### A warm server instance keeps module state

An instance stays loaded between invocations with its module-level variables
intact. That is the point of a warm pool — and it means anything a function
stashes at module scope **outlives the caller it belongs to**.

```js
// Fine: derived from arguments, rebuilt when it matters.
var memo = {};

// A bug: this outlives the caller, and the next one reads it.
var lastUser = null;
function handle(args) { lastUser = ctxUser(); … }
```

Mark such a function `stateless` in the manifest and it gets a fresh instance
every call. See [19](19-server-functions.md) §5.

### `x == null` is true for `0`, so `if (res.result)` is wrong

Already true everywhere in the subset, and it bites hardest on server results,
where `0` is a perfectly ordinary answer. Always test the error:

```js
if (res.error != null) { … }     // right
if (!res.result) { … }           // wrong when the result is 0, "" or false
```

### There is no `try`/`catch`, so errors are values

Every SDK call returns `{ ok, result, error }` and never throws. A guest that
could not catch a throw would simply trap, taking the whole invocation with it.

### Islands are referenced by name, not shipped as source

A server component names an island in `clientComponents`; the device resolves
that name out of the client bundle it already fetched and verified. A name the
bundle does not have renders as its static form — a deployment mistake shows up
as a non-interactive panel, not a blank screen.

### Client-side network policy is advisory

`ElpianNetPolicy` saves a round trip. It is not the boundary, and writing code
that relies on it as one will work in development and fail the moment somebody
edits the device's copy. The server enforces the same rules independently.

### A component must return, not render

`render` is denied to server functions. A component that rendered as a side
effect could not be cached, could not be tested without a host, and could
half-render.

### Caching is opt-in

A component that names neither a tag nor a TTL is never cached. That is
deliberate — caching one that reads changing state would serve a stale page with
no way for it to say otherwise — but it does mean a component you *expected* to
be cached is not, unless you said so with `ui(tree, ["tag"])`.
