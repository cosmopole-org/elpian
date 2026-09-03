# 18 — Fullstack: one app, two VMs, one door

A mini app has two halves. The **client half** runs on the device, in an Elpian
VM, drawing the UI. The **server half** runs on the host, in Elpian VMs of its
own, holding state and doing the work the device should not be trusted with.
They are one app: one manifest, one governance posture, one package, one
version.

This chapter is the whole model in one place. The chapters after it go into
each part: [19](19-server-functions.md) on server functions,
[20](20-proxy-and-egress.md) on the network, [21](21-hosting.md) on running a
host, [22](22-packaging.md) on shipping.

---

## 1. Why this can be governed at all

A guest's only outward effect is `askHost`. There is no socket call and no
syscall in the instruction set, so **every byte a mini app sends anywhere passes
through a host API the host implements**.

That one fact is what makes the rest of this possible. The proxy in chapter 20
is not a wrapper something could route around; it is the only door. The
capability gate is checked *inside the VM*, before a call is even emitted, so a
denied API short-circuits to a typed null without any host code running.

## 2. What runs where

| | Client VM | Server function VM |
|---|---|---|
| Where | the device | the host |
| Lives for | as long as the app is open | one invocation, or a pooled reuse |
| Draws | yes (`render`, `flutter.*`) | **no** |
| Holds state | in memory, lost on close | `kv.*`, durable |
| Reaches the network | only through the host | only through the broker |
| Knows the caller | it *is* the caller | `ctx.user`, host-verified |
| Trusted with secrets | never | `secret.get`, declared names only |

The server posture is written positively — deny-all, then name what a server
function may hold — rather than as "the client set minus some things". That
matters because a new client capability would otherwise be granted to server
functions by default, and defaults should fail closed.

## 3. The request lifecycle

```text
device                     host                          function VM
  |                          |                                |
  |-- GET  /apps/notes/manifest.json ------------------->|    |
  |<-- {client, functions[], network} ------------------ |    |
  |-- GET  /apps/notes/client.bc ---------------------->|     |
  |<-- bytecode (content-addressed, hash in manifest) --|     |
  |                          |                                |
  |  [client VM runs]        |                                |
  |-- POST /apps/notes/fn/save  {"text": "..."} ------->|     |
  |                          |-- authorise the caller ->|     |
  |                          |-- quota: admit? -------->|     |
  |                          |-- lease an instance ---->|---->|
  |                          |                          | kv.set
  |                          |<-------------------------|<----|
  |<-- {"ok":true,"result":true,"coldStart":false} -----|     |
```

Four things happen before any guest code runs, in this order, and the order is
the point:

1. **Routing** decides which app. The app id comes from the path, never from the
   body — which is why `server.call` needs no cross-app check: by the time guest
   code runs, the app was already decided.
2. **Authentication** turns a credential into `ctx.user`, or into anonymous.
3. **The quota ladder** decides whether to serve at all. Refusing here costs
   nothing; refusing after the instructions are spent costs exactly what the
   quota exists to bound.
4. **Governance** is applied to the instance — on creation *and* on reuse, so a
   warm instance cannot carry a capability that was revoked between calls.

## 4. Two kinds of server function

An **action** returns JSON. It may write. Invoked with `server.call`, or
`POST /apps/<app>/fn/<name>`.

A **component** returns a *UI payload*. It is expected to be a pure function of
its arguments and the app's state, which is what makes it cacheable. Invoked
with `server.render`, or `POST /apps/<app>/render/<name>`.

Asking for the wrong one is an error (HTTP 400), not a coincidence that happens
to work. A component does **not** call `render` — the server posture denies that
capability — because a component that rendered as a side effect could not be
cached, could not be tested without a host, and could half-render.

## 5. What the client SDK looks like

```js
import 'server.js';

// An action.
callServer("createNote", { title: t }, (res) => {
  if (res.error != null) { print(res.error.message); return; }
  notes.push(res.result);
});

// A form, without a hand-written submit handler.
el("form", { onSubmit: action("createNote", (res) => { … }) }, [ … ]);

// A component, as a node.
let panel = serverComponent("NoteList", { page: 1 }, {
  pending: skeleton(),
  error:   errorCard(),
});
```

Three properties of this API are **forced by the JavaScript subset**, not
chosen — see [04](04-languages.md):

* **Callbacks, not promises.** There is no `async`/`await`.
* **Results, not exceptions.** There is no `try`/`catch`, so an error must be a
  *value*. Every call returns `{ ok, result, error }` and never throws.
* **Explicit null checks.** `x == null` is also true for numeric `0`, so
  `if (res.result)` is wrong whenever `0` is a legitimate result. Write
  `if (res.error != null)`.

## 6. On the device

`ServerComponent` renders a payload:

```dart
ServerComponent(
  client: ElpianServerClient(baseUrl: host, appId: 'notes'),
  name: 'NoteList',
  args: const {'page': 1},
  pending: const CircularProgressIndicator(),
  revalidate: const Duration(seconds: 30),
)
```

Two behaviours that are decisions rather than details:

* A **failed revalidation keeps what is on screen.** Losing working content
  because a refresh failed is worse than showing content a second old. Only the
  *first* fetch shows the pending widget.
* A **generation guard** stops a slow earlier response overwriting a newer one.
  Two fetches can be in flight when arguments change and can finish out of
  order; without the guard the older answer wins and nothing corrects it.

## 7. What is not here

Written plainly, because a chapter that only lists what exists is how a reader
ends up designing against something that does not.

* **Streaming server components.** The payload arrives whole. The
  `ElpianStreamWidget` protocol exists and would carry it, but nothing emits
  frames yet.
* **HTTPS from a server function.** The broker allows it; the host has no TLS
  stack, so it is refused with a message that says so rather than being
  downgraded to cleartext.
* **Per-user render caching.** An authenticated render bypasses the shared cache
  entirely rather than being keyed by identity. Serving one user's page to
  another is the worst possible cache bug, and per-user caching needs designing
  rather than falling into.
* **Cross-app communication.** Deliberately impossible. If two mini apps must
  talk, that needs its own design.
