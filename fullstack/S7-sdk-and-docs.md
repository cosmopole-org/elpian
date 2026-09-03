# S7 — The guest SDKs and the documentation

**Objective.** Give guest authors a working vocabulary for the fullstack model
on both sides of the seam, inside the constraints of the JavaScript subset, and
write the wiki chapters that make the whole thing usable by someone who did not
build it.

**Delivers (P7, rolling).** `@elpian/sdk` gains the client half, a new
`@elpian/server` package carries the server half, and five wiki chapters.

---

## 1. The subset constrains the API

`wiki/04-languages.md` and the compiler define what guest code may use.
`guest-sdk/js/net.js` states the working constraints plainly: **no spread, no
destructuring, no template literals, no try/catch, no regex**, and `x == null`
is also true for numeric `0`.

Three consequences the SDK design has to accept:

1. **Callbacks, not promises.** `callServer(name, args, cb)`. No `async/await`,
   no thenables.
2. **Result objects, not exceptions.** No `try/catch` means an error must be a
   value: every call hands back `{ ok, result, error }` and never throws.
3. **Explicit null checks.** `if (res.error != null)` — never truthiness, given
   the `0 == null` behaviour.

This is a real constraint, not a preference. Designing a promise-based API and
discovering it cannot compile is the expensive way to learn it.

## 2. `@elpian/sdk` — the client half

Existing exports (`el`, `render`, `__elpianEvent` and its closure registry)
stay. Added:

```ts
// Invoke a server action.
callServer('createNote', { title: t }, (res) => {
  if (res.error != null) { toast(res.error.message); return; }
  notes.push(res.result); render(view());
});

// Fetch a server component's payload imperatively.
serverRender('NoteList', { page: 1 }, (res) => { pane = res.component; render(view()); });

// Or declaratively, as a node.
serverComponent('NoteList', { page: 1 }, {
  pending: skeleton(), error: errorCard(), revalidate: 10,
});

// Bind a form to an action without hand-writing the submit handler.
el('form', { onSubmit: action('createNote', (res) => { … }) }, [ … ]);
```

All of it lowers to `askHost('server.call' | 'server.render', …)`, so the
capability gate (`server_call`) and the client net policy (S3) apply
uniformly — the SDK adds ergonomics, never reach.

## 3. `@elpian/server` — the server half

A new package, because a server guest needs a different vocabulary and must not
be tempted by client-only names:

```ts
import { ui, ctx } from '@elpian/server';

// src/server/actions/createNote.ts
export default function (args, ctx) {
  if (ctx.user == null) { return { error: { code: 'forbidden' } }; }
  const id = ctx.kv.set('note:' + ctx.random.id(), args);
  ctx.revalidate('notes');
  return { id: id };
}

// src/server/components/NoteList.ts
export default function (args, ctx) {
  const notes = ctx.kv.list('note:');
  return ui.div({ className: 'list' }, notes.map(noteRow));   // returns, never renders
}
```

`ctx` is host-constructed per invocation and is the only ambient authority:

| `ctx` member | Backed by | Notes |
|---|---|---|
| `ctx.app`, `ctx.version`, `ctx.function` | host | identity, for logs |
| `ctx.user` | the `AuthProvider` (S5) | **verified**; `null` when anonymous. Never from the request body |
| `ctx.kv` | `kv.*` (S1) | app-scoped; charged to the storage budget |
| `ctx.fs` | `fs.*` (S1) | app-rooted |
| `ctx.fetch` | `net.*` → the broker (S3) | absent entirely in `closed` mode |
| `ctx.secret(name)` | `secret.get` (S1) | names declared in the manifest; values never packaged |
| `ctx.revalidate(tag)` | host cache (S2) | action → component invalidation |
| `ctx.log` | `log` | tagged with app + function |
| `ctx.emit(frame)` | `render` / `ui.patch` (S2) | streaming components only |

`ui` is the same builder as the client's `el`, shared so a component's output
is the same tree shape the client renders locally.

**One deliberate omission:** no `ctx.db`. Storage is `kv` + `fs` until there is
a reason for more; adding a database surface is a separate decision with its own
governance questions.

## 4. Documentation

New chapters, in the existing `wiki/` style — written to be read start to
finish, with the "what is *not* here" honesty the current chapters have:

| Chapter | Covers |
|---|---|
| `18-fullstack.md` | The whole model: two VMs, one app; what runs where and why; the request lifecycle end to end |
| `19-server-functions.md` | Actions vs components; the directory convention; `ctx`; warm-instance state and its contract; timeouts and traps |
| `20-proxy-and-egress.md` | The three network modes; what `closed` guarantees; **that client-side policy is advisory and the server is the boundary**; the broker's checks |
| `21-hosting.md` | Registry, manifest vs grant, the admin API, access control, quotas, cost meters and their approximations |
| `22-packaging.md` | `.elpianpkg`, determinism, signing, publish/install, the HMAC→ed25519 path |

Updated: `03-governance.md` (new capabilities; server posture; the cost-meter
section that currently says none exists), `05-cli.md` (new commands; the dev
server becoming a registry case), `12-host-apis.md` (`server.*`, `kv.*`,
`secret.*`), `14-gotchas.md` (warm state; `0 == null`; islands by name;
advisory client policy), `17-nextjs-integration.md` (a pointer to the native
path and how the payload shapes relate).

## 5. Samples

- `fullstack-sample/` — upgraded to the new layout: one action, one server
  component, one island, `network: "closed"`. This is the reference the E2E
  tests drive (S8).
- A second sample in `brokered` mode calling one allowlisted third-party API,
  so the broker has a worked example and the allowlist has a real shape.

## 6. Verification

- Every snippet in the new chapters compiles through `js2elpian` — a doc test
  that extracts fenced `ts`/`js` blocks and runs the compiler over them. The
  subset is strict enough that untested documentation examples will be wrong.
- `fullstack-sample` builds, packages, installs, serves, and its E2E path
  passes (S8).
- `elpian create --template closed-fullstack` produces a project that builds
  and runs with no edits.
