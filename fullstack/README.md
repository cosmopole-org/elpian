# The Elpian fullstack program

This folder is the single source of truth for making the Elpian fullstack system
feature-rich: **server components**, a **controlled proxy** between a mini app's
client and server VMs, a **serverless** backend that loads and unloads function
VMs on demand, a **server-side control plane** (registry, policy, meters,
limits, access control), and a **packaging + install** path through the CLI.

It is written to be executed across multiple independent sessions. Start every
session with `STATUS.md`, then `00-current-state.md`, then the workstream file.

---

## The shape of the thing being built

```
   client device                      elpiand — the Elpian host server
 ┌────────────────────┐          ┌───────────────────────────────────────────────┐
 │  Flutter shell     │          │                                               │
 │ ┌────────────────┐ │  fetch   │  ┌──────────┐      ┌──────────────────────┐  │
 │ │ client Elpian  │◀┼──bytecode┼──│ Registry │      │ Supervisor VM (app)  │  │
 │ │      VM        │ │          │  │  apps ×  │      │ ┌────┐ ┌────┐ ┌────┐ │  │
 │ └───────┬────────┘ │          │  │ versions │      │ │fn A│ │fn B│ │fn C│ │  │
 │         │          │          │  │ manifest │─────▶│ │warm│ │cold│ │warm│ │  │
 │  server.call ──────┼──────────┼─▶│ + grant  │      │ └────┘ └────┘ └────┘ │  │
 │  server.stream ────┼──────────┼─▶│ = policy │      └──────────┬───────────┘  │
 │         │          │          │  └──────────┘                 │              │
 │   net.* (policed)  │          │        ┌──────────────────────▼───────────┐  │
 └─────────┼──────────┘          │        │ Egress broker — allowlist, SSRF, │  │
           │                     │        │ byte metering, audit             │  │
           └─────────────────────┼───────▶└──────────────┬───────────────────┘  │
              brokered egress    │                       │                       │
                                 └───────────────────────┼───────────────────────┘
                                                         ▼
                                                   outer world
                                          (allow / allowlist / denied)
```

A mini app declared `network: "closed"` gets no egress on either side: the
client VM's only reachable peer is its own server functions, and those functions
have no `net.*` at all. The pair can talk to each other through the host and to
nothing else.

## Workstreams

| ID | File | What it delivers | Depends on |
|----|------|------------------|------------|
| 00 | [`00-current-state.md`](00-current-state.md) | Verified findings + file:line map | — |
| S0 | [`S0-concurrency-foundation.md`](S0-concurrency-foundation.md) | Real parallel guest execution; sound VM ownership | — |
| S1 | [`S1-server-runtime.md`](S1-server-runtime.md) | `elpian-host` crate; host-call servicing; `server.call` RPC | S0 |
| S2 | [`S2-server-components.md`](S2-server-components.md) | Server components, streaming, islands, actions | S1 |
| S3 | [`S3-proxy-and-egress.md`](S3-proxy-and-egress.md) | The broker, network modes, the closed cycle | S1 |
| S4 | [`S4-serverless-pool.md`](S4-serverless-pool.md) | On-demand load/unload, lifecycle, cost meters | S1, S5 |
| S5 | [`S5-registry-and-control-plane.md`](S5-registry-and-control-plane.md) | Mini-app registry, policy, admin API, access control | S1 |
| S6 | [`S6-packaging-and-cli.md`](S6-packaging-and-cli.md) | `.elpianpkg`, sign/verify, publish/install/serve | S5 |
| S7 | [`S7-sdk-and-docs.md`](S7-sdk-and-docs.md) | Guest SDKs, templates, wiki chapters | S2, S3 |
| S8 | [`S8-verification.md`](S8-verification.md) | Tests, conformance corpus, benchmarks | all |

## Phasing

Each phase ends in something shippable and independently useful.

| Phase | Workstreams | Ships |
|---|---|---|
| **P0** Foundation | S0 | Guest turns run in parallel; VM ownership is sound |
| **P1** Server runtime + RPC | S1 (+ S3 deny-by-default posture) | A server function can log, keep state and be called from the client |
| **P2** Server components | S2 | `ServerComponent` nodes, actions, streaming |
| **P3** Registry + hosting | S5 | Many mini apps on one host, each governed, with an admin API |
| **P4** Serverless | S4 | Cold start / warm reuse / eviction, quotas and cost meters |
| **P5** The proxy | S3 | Full broker, network modes, closed-cycle enforcement, SSRF hardening |
| **P6** Packaging | S6 | `elpian package` → `elpian publish` → served as a mini app |
| **P7** Polish | S7, S8 | SDKs, docs, samples, benchmarks (rolling, not last) |

**Why the deny-by-default posture lands in P1 and the broker in P5:** a server
function that gains host-call servicing (S1) must not be born with the network.
The capability posture is cheap and must be right from the first commit; the
allowlist, SSRF guards and audit trail are a phase of their own.

## Principles this plan holds to

1. **Reuse the mechanisms that exist.** Capabilities, limits, the VM tree,
   lifecycle control, the JSON control plane and the signed-bundle loader are
   all built and tested. Most of this program is wiring, not invention.
2. **One enforcement seam.** A guest's only outward effect is `askHost`. Every
   new power is a host API with a capability, so it is governed by construction.
   Never add a side channel.
3. **The manifest is a request; the grant is the truth.** A mini app describes
   what it wants. The host decides. The policy is the intersection — that rule
   already exists in Dart (`mini_app.dart:235`) and is ported, not re-designed.
4. **Client-side policy is advisory; server-side policy is enforcement.** The
   device belongs to the user. A closed cycle is closed because the *server*
   refuses, not because the client asked nicely. Stated again wherever it
   matters.
5. **Fail closed, and say so.** A denied capability short-circuits to a typed
   null rather than trapping — keep that behaviour, and make every new refusal
   auditable.
6. **Deterministic artifacts.** Same source, same bytes, same hash. Packaging
   depends on it and so does caching.
