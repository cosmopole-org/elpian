# S5 — The registry and the server-side control plane

**Objective.** Give the server the thing the client already has and the server
completely lacks: an object meaning "one mini app", with an identity, a
manifest, a grant, artifacts, a policy, state, meters and an admin API.

**Delivers (P3).** Many mini apps on one host, each governed independently;
users fetch a mini app's client bytecode from an endpoint and that client talks
only to its own backend, under policy.

---

## 1. The model, ported not invented

The rule already exists, in Dart, with tests: a **manifest** is what the app
asks for, a **grant** is what the host allows, and the **policy** is the
intersection — narrowed by both, so an app gets neither more than it requested
nor more than it was granted (`lib/src/superapp/mini_app.dart:235`,
`MiniAppPolicy.resolve`). Limits intersect axis-by-axis via `tightest`
(`mini_app.dart:269`).

S5 ports that to Rust as `elpian-host/src/policy.rs`, unchanged in behaviour,
including the two subtleties the Dart version documents:

- an empty `requestedCapabilities` means "everything granted", because
  otherwise an app that omitted the field would launch inert and fail
  confusingly;
- an **unrecognised** capability name in a manifest is *dropped*, not rejected —
  dropping can only narrow, so a manifest written against a newer Elpian
  degrades instead of bricking.

Keeping two implementations in lockstep is a real risk, and the tree already
shows the failure mode: `ElpianCapability` is missing `surface`
(`00-current-state.md` §5). The countermeasure is a **shared conformance
corpus** — a JSON file of `(manifest, grant) → expected policy` cases that both
the Rust and the Dart test suites read (S8).

## 2. The record

```jsonc
{
  "id": "notes", "version": 3,
  "name": "Notes", "publisher": "acme",
  "state": "enabled",                         // enabled | suspended | draining | disabled
  "created": "…", "updated": "…",
  "manifest": {                               // authored by the app — UNTRUSTED
    "client":  { "artifact": "sha256:…", "format": "bytecode", "islands": ["LikeButton"] },
    "server":  { "functions": [ { "name": "createNote", "kind": "action",
                                  "module": "sha256:…", "timeoutMs": 5000 } ] },
    "requestedCapabilities": ["logging", "state", "clock"],
    "requestedLimits": { "maxInstructionsPerTurn": 5000000 },
    "network": { "mode": "closed" },
    "secrets": ["STRIPE_KEY"],                // names only, never values
    "access":  { "default": "authenticated" }
  },
  "grant": {                                  // authored by the OPERATOR — trusted
    "capabilities": ["logging", "state", "clock", "storage"],
    "limits": { "maxInstructions": 50000000, "maxMemoryBytes": 67108864 },
    "network": { "mode": "closed" },
    "quotas": { "invocationsPerMinute": 6000, "concurrentInstances": 8 },
    "access": { "default": "authenticated", "functions": { "adminPurge": "role:admin" } },
    "mayHostChildren": false
  },
  "artifacts": { "client.bc": "sha256:…", "server/createNote.bc": "sha256:…" }
}
```

`policy = manifest ∩ grant`, computed at load and recomputed on any grant
change, then pushed to live instances (capabilities can be flipped between
turns, and a revoke propagates to a whole subtree at once —
`wiki/03-governance.md` §3).

## 3. Storage

Content-addressed on disk. No database dependency.

```
<data-root>/
├── registry.json                 # index: id → versions, current, state   (atomic replace)
├── blobs/<sha256[0:2]>/<sha256>  # every artifact, immutable, deduped
├── apps/<id>/<version>/record.json
├── apps/<id>/storage/            # the app's fs.* root  (S1)
├── apps/<id>/kv/                 # the app's kv.* store (S1)
├── meters/<id>/<yyyy-mm>.json    # rolling cost meters   (S4)
└── audit/<yyyy-mm-dd>.log        # egress + admin decisions (S3, S5)
```

Rules: blobs are immutable and named by hash, so a deploy is *"write new blobs,
then atomically swap the record"* and a rollback is swapping it back. Index
writes are temp-file + `rename`. A `RegistryStore` trait keeps a Postgres/S3
backend possible later without the rest of the host knowing.

**Versioning.** Versions are additive and never mutated. `current` points at
one. A deploy of version N+1 drains N's instances (S4) rather than killing
in-flight work. Downgrade is refused by default — the same protection
`bundle.rs` already implements for code bundles.

## 4. The admin API

Authenticated with an operator token (file or env, never a default), optionally
mTLS. All mutations audited with actor, timestamp, before/after.

| Route | Method | Purpose |
|---|---|---|
| `/admin/apps` | GET / POST | List; register a new app **from an `.elpianpkg`** (S6) or from a JSON record + inline blobs |
| `/admin/apps/<id>` | GET / DELETE | Show; remove (blobs GC'd when unreferenced) |
| `/admin/apps/<id>/versions` | GET / POST | List; upload a new version |
| `/admin/apps/<id>/current` | PUT | Point at a version (deploy / rollback) |
| `/admin/apps/<id>/grant` | GET / PUT | Read / replace the grant → recompute policy, push to live instances |
| `/admin/apps/<id>/state` | PUT | `enabled` / `suspended` / `draining` / `disabled` |
| `/admin/apps/<id>/usage` | GET | `usage` + `subtree_usage` right now |
| `/admin/apps/<id>/meters` | GET | Cost meters by window (S4) |
| `/admin/apps/<id>/instances` | GET / DELETE | Live instances and their states; drain or evict |
| `/admin/apps/<id>/log` | GET | Recent guest log, traps, denials, egress decisions |
| `/admin/health` | GET | Pool saturation, memory headroom, queue depths |

This is deliberately the same surface `api/govern.rs` already exposes as JSON to
the Flutter host — *"the crossing point… each function takes and returns JSON so
one narrow ABI covers the whole surface"*. The admin API is that control plane
over HTTP. Reuse `govern.rs`'s shapes verbatim for limits, usage, capabilities
and state so the operator API, the Dart bindings and the FFI all speak one
vocabulary.

## 5. Access control

Two independent questions, kept separate:

**Who may operate the host?** The operator token / mTLS. Nothing else touches
`/admin`.

**Who may use a mini app, and which of its functions?** A pluggable
`AuthProvider`:

```rust
pub trait AuthProvider: Send + Sync {
    fn identify(&self, req: &RequestParts) -> Result<Option<Identity>, AuthError>;
}
pub struct Identity { pub subject: String, pub roles: Vec<String>, pub claims: Map<String, Value> }
```

Built-ins: `none` (public), `bearer-jwt` (verified against a configured
JWKS/secret), `session-cookie` (host-issued, signed), and `forward-header` for
deployments behind an authenticating proxy (trusted only when the peer is on a
configured allowlist — otherwise header spoofing is trivial).

The resolved `Identity` reaches the guest as `ctx.user`, **host-constructed and
never client-supplied**. This is the single most important trust rule in the
control plane: a client can always lie about who it is in the request body, so
identity may only come from a verified credential the host itself checked.

Rules per app: `public` / `authenticated` / `role:<r>` / `allowlist`, with a
default plus per-function overrides. Enforced in the gateway before an instance
is checked out, so an unauthorised call costs no guest CPU.

## 6. Serving the client half

The requirement — "users can fetch a mini app's frontend bytecode and the loaded
front VM interacts with the app's backend in a controlled manner":

```
GET /apps/notes/manifest.json →
  { "client": { "url": "/apps/notes/client.bc?v=sha256:…", "format": "bytecode" },
    "server": { "endpoint": "/apps/notes/fn", "stream": "/apps/notes/stream",
                "functions": [ { "name": "createNote", "kind": "action" } ] },
    "network": { "mode": "closed" },
    "islands": ["LikeButton"] }
```

The existing Flutter shell (`cli/elpian_client/lib/main.dart`) already does
exactly this dance against `__elpian/elpian.manifest.json` — it fetches a
manifest, reads `client.format` and `client.url`, downloads the artifact and
boots `ElpianVmWidget.fromBytecode`. S5 generalises its manifest URL to
`/apps/<id>/manifest.json` and adds the `server`/`network` blocks, which the
host handler uses to configure `server.call` and the net policy for that VM.

Serving specifics: client artifacts are content-addressed, so
`Cache-Control: public, max-age=31536000, immutable` with the hash in the URL;
manifests are `no-store`. Integrity: the manifest carries the artifact's
`sha256` and the shell verifies it after download — cheap, and it makes a
mis-served or truncated artifact a clean error instead of a VM that fails to
compile.

## 7. Files

| File | Change |
|---|---|
| `elpian-host/src/registry/**` | **New** — store, records, versions, blobs, GC |
| `elpian-host/src/policy.rs` | **New** — port of `MiniAppPolicy.resolve` |
| `elpian-host/src/gateway/auth.rs` | **New** — `AuthProvider`, access rules |
| `elpian-host/src/gateway/admin.rs` | **New** — the admin API |
| `cli/elpian_client/lib/main.dart` | Manifest URL from the app path; verify artifact hash; configure net policy + server endpoint |
| `lib/src/superapp/mini_app.dart` | Keep in lockstep with `policy.rs` via the corpus |
| `test/fixtures/policy_corpus.json` | **New** — shared conformance cases (S8) |

## 8. Verification

- **Policy parity**: the shared corpus passes identically in Rust and Dart,
  including the empty-request and unknown-capability cases.
- **Registry round-trip**: register → serve → invoke → new version → rollback,
  with blob dedupe verified (two versions sharing a module store one blob).
- **Atomicity**: kill the process mid-write of `registry.json`; on restart the
  index is the old one, intact.
- **Isolation**: app A cannot read app B's `fs.*` or `kv.*`; ids are namespaced;
  a `..` in an app id or key is refused (the `mini_app.dart:130` lesson —
  reject the namespace separator in ids — applies here too).
- **Access control**: `authenticated` denies an anonymous call before any guest
  runs; `role:admin` denies a token without the role; a forged `ctx.user` in the
  request body is ignored.
- **Suspension**: a suspended app 403s, its instances are evicted, and its
  blobs remain for re-enable.
- **Admin auth**: every `/admin` route 401s without a token; each mutation
  appears in the audit log.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Two policy implementations drift | The shared corpus is the mechanism; make it a CI gate in both suites |
| A JSON-file registry hits a scaling wall | `RegistryStore` trait from day one; the index holds metadata only, blobs are files |
| Operator grants everything because narrow grants are tedious | `elpian inspect` (S6) prints exactly what a package requests and why; ship `MiniAppGrant::untrusted` as the default posture, as the Dart side already does (`mini_app.dart:168`) |
| Identity spoofing via a forwarded header | `forward-header` requires a peer allowlist; documented as unsafe otherwise |
