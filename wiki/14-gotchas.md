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
> `elpian-server` that trap poisoned a global lock, so every later request to the
> process died with a dropped connection while the listener stayed up looking
> healthy. Both halves are fixed now (rejection in `js2elpian`, poison recovery
> in `api.rs`), but if you see that signature, you are on an old build.

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

### 8. Handlers are names, not closures

`onClick: 'increment'` is a string naming a top-level function. You cannot
capture a loop variable. For per-item identity, set a stable `key` on the node
and read `event.currentTarget` in the handler
([`10-events.md`](10-events.md), recipe 4).

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

### 19. `elpian run dev` serves the *shared* engine directory

It serves `elpian-cli/elpian_client/build/web`, not your `dist/web`. Building a
different project with a different `basePath` re-bases that shared directory out
from under a running dev server. Give each project an explicit `engineProject`
if you run more than one.

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

`console.log` lowers to `askHost("log", …)`, which `elpian-server` does not
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
| Server dies after one bad request | #1 — poisoned lock; you are on a pre-fix build |
| Assets 404 at the domain root | #17 — `basePath` |
| UI does not update after a state change | #7 — call `render()` |
| Text field cursor jumps | #11 — re-rendering on input |
| Handler fires for the wrong item | #8, #9 — closures / missing `key` |
| `javascript parse error` | #3 — generators, anonymous default export |
| A name is mysteriously undefined | #4 — bundler scope / circular import |
| Style property ignored on a button | #13 |
| Screen will not scroll | #15 — 3D scene in the subtree |
| Server function returns `"[undefined]"` | #23 — wrong function name |
