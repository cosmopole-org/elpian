# 00 — The fullstack system as it stands (verified 2026-09-03)

Read this once per session to reload the mental model. Every claim below was
checked against the source at the cited line; nothing here is inferred from
documentation.

---

## 1. What "fullstack" means today

`elpian create --template fullstack` produces `src/client.ts` + `src/server.ts`.
`elpian run build` compiles each into its own bundle
(`cli/rust/main.rs:271`), emits `client.elpian.bc` / `server.elpian.bc` and a
manifest (`cli/rust/main.rs:314`), and `elpian run dev` starts
`elpian-server` with `dist/server.elpian.bc` as `--server-bytecode`
(`cli/rust/main.rs:518`).

That is the whole of it. The server half is a **322-line single-file HTTP
server** (`rust/crates/elpian-vm/src/bin/elpian-server.rs`) with three routes:
static web root, static artifact root, and `/__elpian/api/<fn>`.

## 2. The five findings that shape this plan

### F1 — A server function cannot call the host at all

`run_api` (`elpian-server.rs:170`) does, per request:

```
create_vm_from_bytecode → execute_vm (top level) → execute_vm_func_with_input(fn) → destroy_vm
```

and if the guest makes **any** `askHost` call, the request returns HTTP 501
(`elpian-server.rs:212` and `:217`). There is no host-call servicing loop on the
server. So a server function today cannot log, read the clock, read a file, hold
state, or reach the network. It can transform its JSON input and nothing else.

### F2 — All guest execution is serialised process-wide

The VM registry is one global mutex (`rust/crates/elpian-vm/src/api.rs:33`) and
`execute_vm*` holds it for the **entire duration of the guest turn**
(`api.rs:404`, `:417`, `:430`). The server spawns a thread per connection, so
the concurrency is real at the socket and fake at the VM: two requests cannot
execute guest code at the same time.

Compounding this, `VM` carries `unsafe impl Send`/`Sync`
(`rust/crates/elpian-vm/src/sdk/vm.rs:21-22`) over an
`Rc<RefCell<Executor>>`. Today the global mutex is what makes that not blow up.
Any change to concurrency has to address the soundness story, not just the lock.

### F3 — The client cannot call its server

The guest SDK (`@elpian/sdk`, generated from `cli/rust/main.rs:854`) exports
`el` and `render` and nothing else — there is no `callServer`.

The VM advertises `net.*` (`api.rs:141`) but **nobody services it** on the
Flutter side: `HostHandler` falls through to `_unserviced`
(`lib/src/vm/host_handler.dart:124`), which returns a typed null. The only
working networking in the tree is `guest-sdk/js/net.js`, which is user-space
guest JS over Godot's `HTTPRequest` node — unavailable in the Flutter/WASM
client.

So the `/__elpian/api/<fn>` endpoint exists and has no caller.

### F4 — No registry, no multi-app, no server-side governance

The server takes **one** `--server-bytecode` for the whole process. There is no
mini-app identity, no per-app policy, no admin surface, no auth, no limits
applied to the request VM, no metering, no instance reuse.

Everything needed to build that exists — but only on the client:

| Mechanism | Where | Server-side today |
|---|---|---|
| 17 capabilities, gated at the one `askHost` seam | `sdk/capabilities.rs` | unused |
| `ResourceLimits` / `ResourceUsage` / `Governor` | `sdk/limits.rs` | unused |
| VM tree: adopt, subtree usage, permission intersection, `enforce_tree_budgets` | `sdk/hierarchy.rs`, `api.rs:729-854` | unused |
| Lifecycle: pause / resume / terminate / `RunState` | `sdk/lifecycle.rs` | unused |
| JSON control plane over all of the above | `api/govern.rs` | unused |
| Multi-VM manager (host-neutral, `HostSurface` trait) | `elpian-runtime/src/manager.rs` | unused |
| Mini-app identity: manifest ∩ grant → policy | `lib/src/superapp/mini_app.dart:235` | Dart only |
| Signed code bundles, downgrade protection | `elpian-dart-runtime/src/bundle.rs` | unused |

The plan is mostly **wiring existing, tested mechanisms into a server**, not
inventing them.

### F5 — Cost metering does not exist

`wiki/03-governance.md` says so outright: *"There is no separate
billing/pricing module… If you need per-tenant billing, read
`usage`/`subtree_usage` on a timer and aggregate outside the VM."* A grep for
`cost_meter|CostMeter|billing` over the whole tree returns nothing. This is the
one requirement with no foundation to build on.

## 3. Server components: the precedent to follow

There is no native mechanism, but the Next.js bridge is a working design for the
same problem (`lib/src/integrations/`, `wiki/17-nextjs-integration.md`): the
server returns `{ component, stylesheet?, navigation?, jsCode?, vmAstJson? }`
and the client renders it natively, with `clientComp` nodes carrying interactive
subtrees. `ElpianStreamWidget` (`lib/src/stream/`) already consumes
`setView` / `patch` commands, which is progressive server rendering with the
transport missing.

S2 adopts that payload shape rather than inventing a third one.

## 4. Packaging: what exists

`elpian run build` emits loose files into `dist/` and a self-contained static
web export into `dist/web`. There is no single-file package, no signature over
the artifacts, and no install/publish path. `bundle.rs` has the crypto half
already: `CodeBundle::signing_input` length-delimits its fields, `SignatureScheme`
is pluggable, HMAC-SHA256 is the default, and the load path is
*fetch → verify → reject downgrade → run*.

## 5. Two pre-existing defects to fix in passing

1. **Capability drift.** Rust has 17 capabilities including `Surface`
   (`capabilities.rs`), and the generated catalog maps `godot.op` / `flutter.op`
   to `"surface"` (`lib/src/vm/host_api_catalog.dart:353-364`). But
   `ElpianCapability` (`lib/src/vm/governance/models.dart:215`) has no `surface`
   member. `fromWireName("surface")` returns null, so every Dart caller falls
   back to `ElpianCapability.other` (`host_side_governor.dart:90`,
   `mini_app_host.dart:200`). It fails *safe*, but it re-couples the drawing
   surface to `other` — exactly the coupling the Rust split was made to break —
   and a manifest requesting `surface` has that request silently dropped
   (`mini_app.dart:81`). Fixed in S0; kept fixed by the conformance corpus in S8.

2. **`vm_busy` is a silent drop.** `execute_vm_func*` returns `"vm_busy"` as a
   *result value*, indistinguishable from a guest that returned that string.
   The serverless pool (S4) must never rely on it; it owns instance
   check-out explicitly.
