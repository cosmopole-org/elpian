# 21 — Running a host

`elpiand` serves mini apps: their client bytecode to devices, and their server
functions to those clients.

```bash
elpiand --registry ./data [--host H] [--port P] [--workers N] [--queue N] [--data-root DIR]
```

---

## 1. The registry directory

```text
data/
  notes/
    app.json          id, version, capabilities, network, limits, functions
    client.bc
    fn/save.bc
    fn/NoteList.bc
```

`elpian-pkg install` writes exactly this layout, so a hand-assembled directory
and an installed package are the same thing to the server.

One malformed app is skipped with a diagnostic rather than failing the host. A
registry is a shared surface, and a bad entry is that app's operational problem,
not every other tenant's.

## 2. `app.json`

```json
{
  "id": "notes",
  "version": "1.2.0",
  "capabilities": ["state", "logging"],
  "secrets": ["apiKey"],
  "network": "closed",
  "limits": { "instructions": 50000000, "memoryBytes": 33554432 },
  "functions": [
    { "name": "save",     "kind": "action" },
    { "name": "NoteList", "kind": "component" }
  ]
}
```

An unknown capability name is **dropped, not rejected** — a manifest written
against a newer host must still load on an older one, and dropping is the safe
direction because it can only narrow. A declared function with no module on disk
*is* an error: a manifest must not promise a route that does not exist.

## 3. Manifest ∩ grant

What an app holds is the intersection of what it asked for and what it was
granted — and both directions matter. Intersecting with the grant is the
security property; intersecting with the request is least privilege, so a
generous grant does not push capabilities onto an app that did not ask.

One exception, which is the subtle part: **a manifest that requests nothing is
treated as requesting everything it was granted.** Otherwise an app that simply
omitted the field would launch with no capabilities and fail confusingly. Least
privilege applies to what an app *states*, not to what it forgot to state.

The same model runs on the device (`MiniAppPolicy.resolve`) and on the host, and
`test/fixtures/policy_corpus.json` is read by both test suites. They must not
drift: an app holding different capabilities on a phone than on the host would
surface only as a bug in whichever direction was more permissive.

## 4. The instance pool

Instances load on demand and unload when nothing needs them.

| | |
|---|---|
| Warm reuse | module initialisation runs once, not per call |
| `stateless` | opt out per function — see [19](19-server-functions.md) §5 |
| Idle TTL | an instance nothing has called is unloaded |
| Per-function cap | one hot function cannot evict every other app's |
| Host-wide cap | a bound, not a tuning target |

Eviction never takes a **busy** instance: one mid-call is not idle however long
ago it last finished one, and unloading it would destroy a VM under a running
turn.

## 5. Meters and quotas

Per app: invocations, cold starts, guest instructions, compute ms, peak memory
(a *peak*, not a sum — memory is a level and adding levels measures nothing) and
storage bytes.

The ladder, applied **before** an invocation runs:

| Stage | At | What happens |
|---|---|---|
| `serve` | < 90% | nothing |
| `throttle` | ≥ 90% | one call in four refused |
| `strangle` | ≥ 100% | writes refused, **reads still served** |
| `drain` | ≥ 150% | everything refused |
| `suspend` | operator | everything refused, stays there |

`strangle` is the rung worth having: it keeps the app *readable* while stopping
it writing, which for a runaway loop of writes is usually what an operator
wants.

No quota means unbounded. A host that was not told an app's budget must not
invent one. `0` is a real budget and is not the same as absent.

A refusal is **429**, not 500 — the app is over budget and a caller may usefully
retry. The caller learns only that; the log names the stage and the axis.

## 6. Identity

The host turns a credential into `ctx.user`, or into anonymous. Anonymous is a
legitimate answer: an app may serve anonymous callers.

There is no way to set an identity from a payload, and a test asserts a `user`
field in a request body is ignored entirely.

## 7. The admin surface

```text
GET    /admin/apps
GET    /admin/apps/<app>/meters       usage, stage, suspended
GET    /admin/apps/<app>/instances    loaded / idle
POST   /admin/apps/<app>/drain        unload this app's instances
POST   /admin/apps/<app>/suspend
POST   /admin/apps/<app>/resume
DELETE /admin/apps/<app>/cache
GET    /admin/audit
```

**Unconfigured means nobody**, not everybody. An open, unconfigured admin API is
how hosts get taken over, and it fails silently because nothing looks wrong
until somebody finds it. A wrong token reads identically to no token — telling
them apart would say whether there is a token to find.

Operator credentials are separate from app-user credentials, because an app sees
its caller's token and must not thereby see an admin one.

Every attempt is audited, **refused ones included**: a run of refusals is the
single most interesting thing this log can contain, and a trail of successes
would not show it.

## 8. Concurrency

A bounded worker pool, default 64 queued connections per worker.

The bound is a safety property, not a tuning knob: an unbounded queue turns
overload into unbounded latency, where every client waits and then times out —
worse for everyone than telling some of them to come back. Shedding is an
explicit 503 with an orderly close, never a dropped connection.

## 9. What is not here

* **TLS termination.** Put a reverse proxy in front.
* **Meter persistence.** Counters are in memory and reset on restart.
* **Automatic reload** when the registry directory changes. Restart the host.
* **Hibernation.** An idle instance is unloaded, not parked; `pause_vm` exists
  in the VM and is not yet used by the pool.
