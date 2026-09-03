# S3 — The proxy: network modes and the closed cycle

**Objective.** Give the host exact control over whether a mini app's client VM
and server VMs may reach the outer world, and make "closed cycle" a real,
enforced state in which the pair can only talk to each other through a
controlled proxy.

**Delivers (P1 posture, P5 full broker).** Deny-by-default in P1; the allowlist,
SSRF hardening, byte metering and audit trail in P5.

---

## 1. Why this is enforceable at all

A guest's only outward effect is `askHost`. There is no socket, no syscall, no
FFI from guest code — `wiki/03-governance.md` states it and the executor
enforces it at one seam. So *every* byte a mini app sends anywhere passes
through a host API the host implements. The proxy is not a wrapper that code
could go around; it is the only door.

Two consequences worth stating plainly:

- **`net.*` is unimplemented on the Flutter client today**
  (`host_handler.dart:124` → typed null). S3 is therefore the *first*
  implementation, which means there is no legacy open behaviour to claw back.
  Deny-by-default is free.
- **The client-side policy is advisory.** The device belongs to the user; a
  determined user can patch their own client. The enforcement boundary is the
  *server*: the gateway and the broker. Client-side policy exists to make the
  intended behaviour clear and to stop accidental leaks, not to constrain an
  adversary who owns the client. Every design choice below puts the real check
  on the server.

## 2. The three modes

Declared per mini app, in the manifest as a *request* and in the grant as the
truth (S5).

```json
"network": {
  "mode": "closed",
  "egress": { "allow": [ { "host": "api.stripe.com", "scheme": "https", "methods": ["POST"] } ] }
}
```

| Mode | Client VM | Server function VMs | Use |
|---|---|---|---|
| `closed` | `network` **denied**; `server_call` granted | `network` **denied** | The default for third-party apps. The pair talks to each other and to nothing else. |
| `brokered` | `network` granted, every request rewritten to the host's proxy | `network` granted, every request through the broker | Apps that need specific third-party APIs |
| `open` | direct egress | direct egress | First-party / development only. Requires an explicit host grant and is logged loudly at startup. |

### What `closed` actually means

```
   client VM                     host                    server fn VMs
 ─────────────      ───────────────────────────      ──────────────────
 net.*        → denied (typed null, audited)
 server.call  → gateway → policy check → invoke →    the app's own functions
                                                     net.*  → denied (typed null, audited)
                                                     server.invoke → sibling functions only
                                                     kv.* / fs.* → host storage, app-scoped
```

- The client's *only* transport is `server.call` / `server.render` / the stream
  socket, and the gateway routes those **only** into that app's own function
  namespace. There is no `app` parameter a client can set — the app identity
  comes from the request path, which the host resolved before any guest ran.
- A server function has no `net.*` at all. Not an empty allowlist — the
  capability is off, so the call short-circuits inside the VM and never reaches
  a host implementation.
- Cross-app calls are impossible: `server.invoke` resolves names within
  `ctx.app` only. Two mini apps that want to talk do it through a host-provided
  channel the operator configures explicitly, which is out of scope here.

## 3. The broker (mode `brokered`)

One component, on the server, in front of every outbound request from either
side. Client-originated requests arrive as `POST /apps/<app>/proxy`; server
function requests call it in-process. Same policy, same meters, same audit.

```rust
pub struct EgressDecision { Allow { url: Url, .. }, Deny { reason: DenyReason } }

pub enum DenyReason {
    ModeClosed, HostNotAllowed, SchemeNotAllowed, MethodNotAllowed,
    PrivateAddress, RedirectOffAllowlist, BodyTooLarge, RateLimited,
    ByteQuotaExceeded, Timeout,
}
```

The checks, in order:

1. **Mode.** `closed` → `ModeClosed`, always, before anything is parsed.
2. **Parse and normalise** the URL. Reject non-`http(s)`, userinfo
   (`http://user@evil/`), and anything that fails a strict parse.
3. **Allowlist match** on host + scheme + method + port. Exact hosts and
   single-level wildcards (`*.example.com`); no regexes — a regex allowlist is
   a bypass waiting to happen.
4. **Resolve, then check the addresses.** Deny loopback, link-local
   (**including `169.254.169.254`, the cloud metadata endpoint**), RFC1918,
   CGNAT, IPv6 ULA/mapped-v4, and `.local`. Unless the operator explicitly
   allowed a private target for a first-party app.
5. **Connect to the resolved address**, carrying the hostname for TLS and
   `Host:`. This closes the DNS-rebinding window — checking a name and then
   letting the HTTP client re-resolve it is the classic hole.
6. **Header hygiene.** Strip hop-by-hop headers and any `X-Elpian-*`; inject
   nothing that identifies the host operator unless configured; never forward
   the end user's session cookie by default.
7. **Redirects** are followed only if each hop passes 2–5 again; `max_hops`
   default 3.
8. **Caps.** Request and response body caps, total wall-clock timeout,
   concurrent connections per app, requests/second per app.
9. **Meter and audit.** Bytes in/out onto the app's egress meter (S4); one
   audit record per decision: app, version, function, instance, target,
   method, status, bytes, ms, decision, reason.

A denied call returns a **typed null** to the guest, matching what the VM does
for a denied capability, plus an audit record — so a guest sees one consistent
"the interface is unplugged" behaviour whether the refusal came from the
capability gate or from the broker.

## 4. The client net policy

New, in Dart, alongside the mini-app policy that already exists:

```dart
class ElpianNetPolicy {
  final ElpianNetMode mode;          // closed | brokered | open
  final Uri? proxyEndpoint;          // where brokered requests go
  final Set<String> allowedHosts;    // advisory pre-filter
  final int maxBodyBytes;
  final int requestsPerSecond;
  final void Function(NetAudit)? onDecision;
}
```

Wired into `HostHandler` as the implementation of `net.*`:
`closed` → typed null + audit; `brokered` → rewrite to `proxyEndpoint` with the
app's request token; `open` → direct `http` package call. It also becomes the
transport under `server.call` / `server.render`, so one place decides what
leaves the device.

`MiniAppGrant` (`lib/src/superapp/mini_app.dart:145`) gains a `netPolicy`
field, so a super app hosting mini apps locally gets the same three modes
without a server involved — the mode is a property of the mini app, not of the
deployment.

## 5. Files

| File | Change |
|---|---|
| `elpian-host/src/broker/**` | **New** — policy, resolver guard, audit |
| `elpian-host/src/surface/net.rs` | `net.*` for server functions → broker |
| `elpian-host/src/gateway/routes.rs` | `POST /apps/<app>/proxy` |
| `lib/src/vm/net_policy.dart` | **New** — the client policy |
| `lib/src/vm/host_handler.dart` | Implement `net.*` through the policy |
| `lib/src/superapp/mini_app.dart` | `netPolicy` on the grant, resolved into the policy |
| `rust/crates/elpian-vm/src/api/govern.rs` | Network mode in the JSON control plane |

## 6. Verification

The security-relevant tests. These are the ones that must not be allowed to
rot; put them in CI.

- **Closed is closed.** For an app in `closed` mode: `net.fetch` from the client
  VM returns null and never opens a socket (assert with a listening canary
  server that records connections); `net.fetch` from a server function likewise;
  `server.call` to another app's function name 403s.
- **SSRF corpus.** A table-driven test over: `http://127.0.0.1`,
  `http://169.254.169.254/latest/meta-data/`, `http://[::1]`,
  `http://10.0.0.1`, `http://0.0.0.0`, `http://2130706433` (decimal IP),
  `http://127.0.0.1.nip.io`, `http://user@allowed.example.com@evil.example`,
  a DNS name that resolves to a private address, and a redirect chain
  allowed→private. All denied with the right `DenyReason`.
- **Rebinding.** A stub resolver that returns a public address on the first
  lookup and a private one on the second: assert the connection uses the
  checked address.
- **Allowlist matching**: `*.example.com` matches `a.example.com`, does not
  match `example.com.evil.test` or `a.b.example.com`.
- **Caps**: oversized request and response bodies denied; rate limit returns
  `RateLimited`; byte quota exhaustion returns `ByteQuotaExceeded` and increments
  the meter.
- **Audit completeness**: every allow and every deny produces exactly one
  record; no request is unlogged.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Client policy mistaken for a security boundary | Documented in the wiki chapter and in the code comment on `ElpianNetPolicy`; server-side check is mandatory and independent |
| A new host API becomes an accidental egress path | Every host API family maps to a capability by prefix; add a test that enumerates `all_host_apis()` and asserts each name's capability is intentional (catches a name landing on `Other`) |
| The broker becomes a slow serial choke point | It is async (S1's gateway); per-app connection pools; the VM is not held while a brokered call is in flight |
| Allowlist expressiveness pressure ("just let me use a regex") | Hold the line: exact hosts + one wildcard level. Add explicit entries instead |
