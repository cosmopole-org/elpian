# S2 — Server components, actions and streaming

**Objective.** Let a mini app's server side return **UI**, not just data, and
let the client render it natively, progressively, with interactive islands
running in the client VM.

**Delivers (P2).** `ServerComponent` nodes in a client tree; form actions;
streaming server components over WS; revalidation and caching.

---

## 1. The model

A server function has a **kind**:

| Kind | Returns | Called by |
|---|---|---|
| `action` | a JSON value | `server.call(name, args)`; form submit |
| `component` | a UI payload | a `ServerComponent` node; `server.render(name, args)` |

A function may not be both — that ambiguity buys nothing and costs a clear
contract. A component that also mutates should call an action.

### The payload

Deliberately the **same shape the Next.js bridge already speaks**
(`wiki/17-nextjs-integration.md`), so `lib/src/integrations/nextjs_bridge.dart`
and its tests carry over instead of a third parallel format:

```json
{
  "component":  { "type": "div", "children": [ … ] },
  "stylesheet": { "rules": [ … ] },
  "islands":    [ { "key": "like-42", "client": "LikeButton", "props": { "id": 42 } } ],
  "data":       { "…": "state the islands need" },
  "navigation": { "redirectTo": "/notes", "replace": true },
  "meta":       { "revalidateSeconds": 10, "etag": "…", "renderedAt": "…" }
}
```

`component` is the only required field. `jsCode` from the Next.js payload is
**not** carried over: shipping source for the client to compile is both a cold
cost and an unnecessary code path when the client already holds the app's
bundle. Islands reference client functions **by name**.

### Islands

An island is a subtree the server places and the *client* VM owns:

```
server component tree                    client VM
┌───────────────────────┐
│ div                   │
│ ├ h1  "Notes"         │
│ ├ NoteRow ×20         │
│ └ island "like-42" ───┼──▶ LikeButton(props) — exported from the client bundle
└───────────────────────┘        renders, handles taps, calls server.call
```

The host sees an `island` node, calls the named client-bundle export with the
declared props, and splices the returned subtree in place. The name must be in
the client manifest's exported-island list, which the CLI derives from
`src/client/islands/`. An unknown island renders a diagnostic placeholder in
debug and an empty box in release — never an error that takes the page down.

**Why by name and not by inline source:** the client bundle is already fetched,
verified and warm. Inline source means a second compile path on the device, a
larger payload per render, and a much wider trust surface.

## 2. Rendering: return a value, don't call `render`

A server component **returns** its payload:

```ts
export default function NoteList(args, ctx) {
  const notes = ctx.kv.list('note:');
  return ui.div({ className: 'list' }, notes.map(row));
}
```

It does *not* call `askHost('render', …)`. Reasons: a pure function is testable
without a host, cacheable by `(fn, args)`, and cannot half-render. `render` and
`ui.patch` stay reserved for the **streaming** path (§4), where emitting
successive frames is the whole point.

## 3. The client side

Two integration modes, in this order:

**Imperative — `server.render`.** The client guest asks for a payload and
embeds it in its own tree:

```ts
serverRender('NoteList', { page: 1 }, (res) => {
  if (res.ok) { pane = res.component; render(view()); }
});
```

**Declarative — the `ServerComponent` node.** The nicer DX, built on the same
host API:

```ts
el('ServerComponent', {
  fn: 'NoteList', args: { page: 1 },
  pending: skeleton(), error: errorCard(),
  revalidate: 10,
}, [])
```

A new widget builder in `lib/src/widgets/` resolves it: fetch → render the
returned tree with the app's engine → cache by `(app, fn, args)` with the
payload's `revalidateSeconds`. It owns four states (pending / ready / error /
revalidating) and holds the previous tree while revalidating, so a refresh does
not flash.

Client-side needs, all new:
- `server.call` / `server.render` serviced in `HostHandler`
  (`lib/src/vm/host_handler.dart`) — the first real network the Flutter host
  performs on a guest's behalf. Routed through the client net policy (S3).
- An island resolver on `ElpianServices`, so islands render in the mini app's
  own registry and cannot reach a sibling's.
- Stylesheet merge: a payload's `stylesheet` loads into the app's engine scoped
  to the component instance, not globally.

## 4. Streaming

`ElpianStreamWidget` (`lib/src/stream/elpian_stream_widget.dart`) already
consumes `setView` / `patch` / `stylesheet` commands. S2 gives it a transport.

```
WS /apps/<app>/stream/<fn>          client → { args }
                                    server → { "action": "setView",  "view":  {…} }
                                    server → { "action": "patch",    "patch": {…} }
                                    server → { "action": "done" }
```

Server-side, a streaming component *does* use `render` / `ui.patch`: each call
becomes one frame on the socket. The instance stays checked out for the life of
the stream and is charged wall-clock time (S4), so `maxStreamSeconds` and
`maxFramesPerSecond` are per-app policy, enforced by the host, not by the guest.

This is also the transport the `example/caspar-node-machine` protocol
(`ui.init` + `ui.patch`) was designed around; the framing is intentionally the
same so that machine model works over Elpian's own server.

## 5. Caching and revalidation

| Layer | Key | Invalidated by |
|---|---|---|
| Host render cache | `(app, version, fn, args-hash)` | `revalidateSeconds`, or `ctx.revalidate(tag)` from an action |
| Client widget cache | same, per widget instance | payload `meta.revalidateSeconds` |
| Client bytecode | content hash | new version in the registry |

`ctx.revalidate(tag)` and a `tags: []` field on a component payload give
action→component invalidation without a pub/sub system: the action names a tag,
the host drops matching cache entries. Bounded, boring, and enough.

## 6. Files

| File | Change |
|---|---|
| `elpian-host/src/surface/server.rs` | `server.render`, streaming frames, cache |
| `elpian-host/src/gateway/ws.rs` | Stream sockets, frame budgets |
| `lib/src/vm/host_handler.dart` | `server.call` / `server.render` |
| `lib/src/widgets/server_component.dart` | **New** — the `ServerComponent` builder |
| `lib/src/core/elpian_services.dart` | Island registry, scoped stylesheet load |
| `lib/src/integrations/nextjs_bridge.dart` | Extract the shared payload parser |
| `lib/src/stream/elpian_stream_widget.dart` | WS transport binding |
| `cli/rust/main.rs` | `src/server/components/`, `src/client/islands/` in the manifests |

## 7. Verification

- A component payload round-trips: server returns a tree → client renders the
  same widget tree a local `renderFromJson` would produce (golden test).
- Island splice: an unknown island name degrades to a placeholder; a known one
  receives its props and its taps reach the client VM.
- Streaming: `setView` then three `patch` frames produce four distinct
  rendered trees; a frame-rate-abusing guest is throttled by the host.
- Cache: two identical calls inside `revalidateSeconds` invoke the guest once;
  `ctx.revalidate(tag)` drops exactly the tagged entries.
- Stylesheet scoping: a component's rules do not leak to a sibling mini app.
- A component that traps renders the `error` slot and does not take down the
  hosting tree.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Payload divergence from the Next.js bridge over time | One parser, shared by both paths; golden payloads in the test corpus |
| A streaming instance pinned for hours | `maxStreamSeconds`, idle frame timeout, wall-clock metering (S4) |
| Island props become a trust hole (server dictates client behaviour) | Islands are resolved from the app's *own* bundle by name; props are data only |
| Server-rendered trees requesting capabilities the client denies | The client's own policy gates rendering as it always has; document that a server payload is data, not authority |
