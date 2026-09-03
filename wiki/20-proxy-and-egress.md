# 20 — The proxy: what a mini app may reach

Three network modes, chosen by the host per app. This chapter is what each one
means, and — more usefully — what it does *not* mean.

---

## 1. The modes

```json
"network": "closed"
"network": { "allow": ["api.example.com", "*.cdn.example.com"] }
"network": "open"
```

| Mode | Client half | Server half |
|---|---|---|
| `closed` | its own server functions, nothing else | nothing |
| `brokered` | its own functions, plus the allowlist via the host | the allowlist via the broker |
| `open` | unrestricted | unrestricted |

**Anything unrecognised is `closed`**, including a missing stanza. A manifest
whose network section was mistyped must not silently get egress.

## 2. What `closed` actually guarantees

Not "the broker refuses it". **The app does not hold `Capability::Network` at
all**, so the call short-circuits inside the VM and there is no host code in the
path to get wrong. There is nothing to bypass because there is nothing there.

The pair of statements is the point, and needs two gates to express: *may talk
to my own server, may not talk to anything else*. `server_call` and `network`
are separate capabilities for exactly this reason.

The guarantee is tested with a canary TCP listener that counts every connection
made to it. A closed app tries `net.fetch`, `net.open`, `vm.import` and
`fs.read`, runs to completion, and the canary records **zero**. A control test
proves the canary detects a connection that is definitely made, so the zero
means something.

## 3. Client-side policy is advisory

`ElpianNetPolicy` lets a device apply the app's posture locally and refuse an
outbound call without a round trip.

**That is a courtesy and a latency saving. It is not the boundary.** A device is
under the user's control and its policy can be edited or replaced. Every rule is
enforced again on the server, and the server's answer is the one that counts.
The client policy exists so a well-behaved app fails fast, not so the host can
stop checking.

This is also why a device's `net.fetch` goes through `POST /apps/<app>/proxy`
rather than the device opening its own socket: routing it through the host means
one policy governs both halves and one audit trail sees both.

## 4. The checks, in order

Cheapest and most decisive first, so a closed app never pays for a DNS lookup
and a malformed URL never reaches the resolver.

1. **Mode** — a closed app is refused outright.
2. **Parse** — no host, no decision.
3. **Scheme** — `http` and `https` only.
4. **Allowlist** — on the *name*, before resolution.
5. **Resolve** — once.
6. **Address** — every answer checked, not just the one that will be used. A
   name resolving to a public address *and* a private one is refused; picking
   the public one would leave which address gets used to resolver ordering.
7. **Connect to the address the broker returned** — never re-resolve.

Step 7 is the whole DNS-rebinding defence: the address checked and the address
connected to must be the same one. A convenience call like
`TcpStream::connect(host)` quietly re-resolves and undoes it. The `Host` header
still carries the *name*, so virtual hosting works and the address cannot drift.

A **redirect is a new request** and goes back through the whole list. Following
one without re-deciding lets any allowlisted host send a guest anywhere,
including back at the host's own network — the usual way an allowlist is
defeated. Relative locations resolve against the origin they came from.

## 5. Addresses that are never reachable

Loopback, RFC1918, link-local (which is where the cloud metadata endpoint
lives), carrier-grade NAT, benchmarking, multicast, reserved — and IPv4-mapped
IPv6 is unwrapped first, or `::ffff:169.254.169.254` walks straight through the
v6 rules.

This is not about privacy. **A server's network position is a capability.** A
mini app that can make the host fetch `http://169.254.169.254/` is asking the
host to read its own cloud credentials and hand them back; one that can reach
`127.0.0.1` is asking it to call services that trust localhost precisely because
they assumed nothing untrusted could.

An allowlist entry does **not** override this. The address check runs after the
allowlist, not instead of it.

## 6. Allowlist matching is on whole labels

`*.example.com` matches `v1.api.example.com` and does **not** match
`evil-example.com`. `example.com` does not match `notexample.com`. Userinfo is
stripped before the host is read, so `http://allowed.example@evil.example/` has
an authority of `evil.example` — a check that matched on the prefix would get
that exactly backwards.

## 7. Every refusal reads the same to the guest

"the request was not permitted", whether the cause was the mode, the allowlist,
a blocked address, a refused connection or a timeout.

A guest that could tell "not allowlisted" from "resolved to a private address"
would have a port scanner built out of the error message. The operator's audit
line does distinguish them.

The one exception is `https`: the host has no TLS stack, and that is a gap in
the host rather than a policy about the app. It reveals nothing about the
network, and an author whose call failed like every other refusal would have no
way to discover why. It is refused, never downgraded to cleartext.

## 8. Audit

Every attempt produces one record — **allowed as well as denied**. A trail with
only denials in it answers "what was blocked" and not "what did this app
actually reach", and the second is the question asked after an incident.

## 9. What is not here

* **TLS.** See above. A hand-rolled stack would be a bad idea and a TLS crate is
  a dependency decision that has not been made.
* **Per-app egress byte budgets.** The meters count instructions, compute and
  storage; bytes out are recorded per request but not yet totalled or capped.
* **A persisted audit trail.** Records are emitted to the operator's log; making
  them durable is the operator's to arrange.
