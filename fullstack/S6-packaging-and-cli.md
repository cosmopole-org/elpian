# S6 — Packaging: one file, signed, installable

**Objective.** Let the CLI package an Elpian project's client bytecode, server
function modules, manifest and assets into a single file that can be verified,
inspected, published to a host, or installed offline into a registry — and then
served as a mini app.

**Delivers (P6).** `elpian package` → `elpian verify` → `elpian publish` /
`elpian install`, and `elpian serve` to run a host over a registry.

---

## 1. The format: `.elpianpkg`

A single deterministic file. Deliberately not tar or zip: those carry
timestamps, permission bits and ordering freedom that make byte-identical
rebuilds hard, and both bring a dependency and a decompression attack surface
for a container this simple.

```
┌────────────────────────────────────────────────────────────┐
│ magic      "EPKG1\0\0\0"                          8 bytes  │
│ index_len  u32 little-endian                      4 bytes  │
│ index      UTF-8 JSON, exactly index_len bytes             │
│ blobs      concatenated entry bytes, in index order        │
└────────────────────────────────────────────────────────────┘
```

```jsonc
{
  "spec": 1,
  "app": { "id": "notes", "version": 3, "name": "Notes", "publisher": "acme" },
  "manifest": { /* the S5 manifest: functions, requested caps/limits, network mode, secrets, access */ },
  "entries": [                                   // sorted by path — determinism
    { "path": "client.bc",            "kind": "clientBytecode", "offset": 0,     "len": 81234, "sha256": "…" },
    { "path": "server/createNote.bc", "kind": "serverModule",   "offset": 81234, "len": 12044, "sha256": "…" },
    { "path": "assets/icon.png",      "kind": "asset",          "offset": 93278, "len": 2048,  "sha256": "…" }
  ],
  "signature": { "scheme": "hmac-sha256", "keyId": "acme-2026", "sig": "hex…" }
}
```

**Determinism rules**, all testable: entries sorted by path; no timestamps, no
uids, no permission bits; the index is canonical JSON (sorted keys, no
insignificant whitespace); artifacts come from a build that is itself
deterministic. The test is: build twice from a clean tree, `sha256` the two
packages, assert equal.

### Signing

Reuse `rust/crates/elpian-dart-runtime/src/bundle.rs`, which already has the
whole shape: `SignatureScheme` is pluggable, HMAC-SHA256 is the default, the
signing input is **length-delimited so fields cannot be shifted across
boundaries**, and the load path is *fetch → verify → reject downgrade → run*.

Lift it into a shared `elpian-pkg` crate (or `elpian-vm::sdk::signing`) so the
CLI, the host and the Dart runtime all use one implementation.

The signature covers `magic || index_len || index-without-the-signature-field
|| all blob bytes`. Because every entry's `sha256` is in the index, signing the
index transitively covers the content — but sign the blob bytes too, so a
truncated file fails verification rather than half-loading.

**Ship HMAC, plan ed25519.** A shared secret is fine for an operator packaging
their own apps, and it is what exists today. It is *not* fine for third-party
publishing: a verifying host would need the signing secret. Add ed25519 before
opening the registry to publishers who are not the operator; the scheme field
and `keyId` are already there to carry it, so it is not a format change.

## 2. The CLI surface

Existing (`cli/rust/main.rs`): `create`, `run install`, `run build`, `run dev`.
Added:

```
elpian package  [--out <file>] [--sign-key <file>] [--key-id <id>]
elpian verify   <pkg> [--key <file>]
elpian inspect  <pkg> [--json]
elpian publish  <pkg> --host <url> --token <t> [--activate]
elpian install  <pkg> --registry <dir> [--activate]
elpian serve    [--registry <dir>] [-H <host>] [-p <port>]
elpian apps     list | show <id> | grant <id> --file <g.json> | suspend <id> | resume <id>
                                                     [--host <url> --token <t>]
```

| Command | Does |
|---|---|
| `package` | `run build`, collect artifacts + assets, derive the manifest from `elpian.config.json` + `elpian.app.json` + the discovered function tree, write and sign the package |
| `verify` | Magic, index parse, per-entry hashes, signature, manifest lint, capability sanity (warn on `other`, on `open` network mode, on `vm_manage`) |
| `inspect` | Human table: functions and kinds, artifact sizes, **exactly what it requests** — the operator's decision aid before granting |
| `publish` | `POST /admin/apps` with the package body |
| `install` | Unpack into a registry store directory offline: blobs by hash, record written, index swapped atomically |
| `serve` | Run `elpiand` over a registry directory |

`elpian run dev` keeps working by registering the current project into a
temporary in-memory registry as a single mini app — so the dev loop becomes a
degenerate case of the production path instead of a separate code path. That
also retires the `--server-bytecode` flag and the standalone `elpian-server`
binary (`00-current-state.md` §1).

## 3. The app manifest source

Today's `elpian.config.json` is a *build* config (out dir, mode, base path,
entries). App identity and policy requests are a different concern, so add
`elpian.app.json`:

```jsonc
{
  "spec": 1,
  "id": "notes", "name": "Notes", "version": 3, "publisher": "acme",
  "requestedCapabilities": ["logging", "state", "clock"],
  "requestedLimits": { "maxInstructionsPerTurn": 5000000, "maxMemoryBytes": 33554432 },
  "network": { "mode": "closed" },
  "secrets": ["STRIPE_KEY"],
  "access": { "default": "authenticated" },
  "functions": {                                  // overrides; the tree provides the defaults
    "createNote": { "timeoutMs": 3000, "maxConcurrency": 8 },
    "NoteList":   { "revalidateSeconds": 10 }
  },
  "assets": ["assets/**"]
}
```

`elpian.config.json` gains only what packaging needs:

```jsonc
{ "server": { "functionsDir": "src/server" }, "client": { "islandsDir": "src/client/islands" } }
```

Everything else in the manifest is **derived** by the CLI from the source tree,
so the two cannot disagree: function names and kinds come from the directory
layout (S1 §5), island names from the islands directory, hashes from the build.

## 4. Templates

`elpian create --template fullstack` is updated to the new layout, and the
existing `CLIENT_TEMPLATE` / `SERVER_TEMPLATE` / `SDK_TEMPLATE`
(`cli/rust/main.rs:801`, `:849`, `:854`) grow accordingly:

```
my-app/
├── elpian.app.json
├── elpian.config.json
├── src/
│   ├── client/
│   │   ├── main.ts
│   │   └── islands/LikeButton.ts
│   └── server/
│       ├── actions/createNote.ts
│       ├── components/NoteList.ts
│       └── shared/store.ts
└── packages/{elpian-sdk,elpian-server}/
```

Add `--template closed-fullstack` (a `closed`-mode app: client + actions +
one server component, no egress) as the recommended starting point, because it
is the posture most apps should ship in and the one the plan is built around.

## 5. Files

| File | Change |
|---|---|
| `cli/rust/main.rs` | New subcommands; `elpian.app.json`; manifest derivation; templates. **Split the file** — it is 1301 lines and this roughly doubles it: `cli/rust/{main,build,package,publish,serve,templates}.rs` |
| `rust/crates/elpian-pkg/**` | **New** — the container format, reader/writer, signing (shared by CLI + host) |
| `rust/crates/elpian-dart-runtime/src/bundle.rs` | Delegate to `elpian-pkg`'s signing rather than keeping a second copy |
| `elpian-host/src/registry/install.rs` | Accept a package on `/admin/apps`; unpack, verify, store |
| `rust/crates/elpian-vm/src/bin/elpian-server.rs` | **Delete** — superseded by `elpian serve` |

## 6. Verification

- **Determinism**: two clean builds of the same commit produce byte-identical
  packages.
- **Tamper detection**: flip one byte in a blob → verify fails on that entry's
  hash; flip one byte in the index → signature fails; truncate the file →
  fails; re-sign with the wrong key → fails.
- **Downgrade refusal**: installing version 2 over an active version 3 is
  refused unless `--allow-downgrade`.
- **Round-trip**: `package` → `install` → `serve` → fetch the client bytecode →
  invoke an action → the same result the dev server gives.
- **`publish` == `install`**: the registry record from either path is identical.
- **`inspect`** output lists every requested capability, and its exit code is
  non-zero when `verify` would fail — so CI can gate on it.
- **Manifest/tree agreement**: a function declared in `elpian.app.json` with no
  file, or a file with no entry, is a build error, not a silent drop.

## 7. Risks

| Risk | Mitigation |
|---|---|
| A custom container format is one more thing to maintain | It is ~200 lines of framing; the alternative dependencies cost more and give up determinism |
| HMAC signing cannot support third-party publishers | Documented limit; ed25519 before the registry accepts non-operator publishers; `scheme`/`keyId` already in the format |
| `main.rs` becomes unmaintainable | The split is part of this workstream, not a follow-up |
| Deriving the manifest from the tree surprises authors | `elpian inspect` prints the derived manifest; a mismatch with `elpian.app.json` is an error, never a silent override |
