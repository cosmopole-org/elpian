# 22 — Packaging: `.elpianpkg`

One signed file carrying a mini app's whole deployable form — client bytecode,
one module per server function, and the manifest.

```bash
elpian-pkg package <project-dir> <out.elpianpkg> [--key K]
elpian-pkg inspect <package>                       # no key needed
elpian-pkg verify  <package> --key K
elpian-pkg install <package> --registry DIR --key K
```

`--key` may also be `ELPIAN_SIGNING_KEY` in the environment.

---

## 1. Why a custom container

**Determinism.** The same source must build the same bytes, or a signature says
nothing useful and two people cannot check they have the same artifact. Tar
carries mtimes, uids and ordering freedom; zip carries timestamps and several
ways to spell one archive. Both would have to be normalised into submission, and
the normalising is where the bug lives.

**Surface.** A decompressor is a parser of hostile input, and this container
needs none: bytecode is compact and a mini app is small. Not having one is a
smaller attack surface than having a careful one.

## 2. The layout

```text
"EPKG1"        magic
u32            index length, big-endian
<index>        JSON: manifest + entry table (name, offset, length, hash)
<blobs>        entry payloads, back to back, in index order
u32            signature length
<signature>    HMAC-SHA256 over everything before this field
```

The index is JSON because an operator has to be able to read it — and because
`inspect` on an *untrusted* package must be able to say what is inside without
trusting it.

## 3. Determinism, concretely

Entries are sorted by name and the index is rendered with sorted keys, so
neither entry order in the project nor key order in the manifest changes the
bytes. Nothing carries a timestamp. Packaging twice and comparing is part of the
end-to-end script.

## 4. Verification refuses before it yields

The signature is checked **before** any entry is handed back, and each entry is
checked against its recorded hash as it is extracted. There is no partial
success — a partially-trusted package is an untrusted one that got further than
it should have.

Per-entry hashes are not redundant with the signature. The signature says the
file is intact as a whole; the hashes say *which* entry is wrong when it is not,
which is what an operator needs when something fails to verify.

## 5. `inspect` is deliberately separate

An operator must be able to ask "what is in this file" before deciding whether
to trust it. That answer must not come from something mistakable for a verifying
read, so `inspect` is its own command, prints a warning, and returns the index
only — never entry data.

## 6. What packaging refuses

* A **declared function with no module** — a manifest must not promise a route
  that does not exist.
* A **module the manifest does not declare** — a function nobody declared is a
  function nobody reviewed, which is the worse of the two.

## 7. Installing

`install` verifies before writing anything. Unpacking first and checking after
would leave a rejected package's bytes in the registry.

`app.json` is written **verbatim** from the package, so the file the server
reads is the file that was signed.

## 8. Signing, and its limit

HMAC-SHA256 with a shared secret, using the scheme already in the tree
(`elpian-crypto`, also used by the bundle verifier).

That proves a package came from someone holding the key. It is enough for an
operator packaging their own apps. **It is not enough for third-party
publishing**: a verifying host would need every publisher's signing key, which
is the same as every publisher being able to sign as every other.

ed25519 is the upgrade path — the verifier is written against a trait so the
scheme can change without touching the load path — and whether third-party
publishing is in scope is still an open question for the maintainer.

A build with no key configured uses a well-known development key and says so.
"No signature" is deliberately not representable: making it so would mean every
verifier needed a branch for it, and that branch is the one reached by accident
in production.

## 9. End to end

`scripts/e2e-fullstack.sh` runs the whole chain through the real binaries:
source → bytecode → package (twice, compared) → inspect → verify → wrong key →
tampered byte → install → serve → manifest → client bytecode → action →
component → warm render → closed-mode egress → wrong-door status codes.

It exists because it catches the class of break no library test can see: a CLI
that builds a package the server cannot read, where both sides pass their own
tests while disagreeing with each other.
