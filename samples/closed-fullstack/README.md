# closed-fullstack — the reference sample

A mini app with both halves, in a **closed** network posture: its client VM can
reach its own server functions and nothing else, and its server functions can
reach nothing at all.

```text
elpian.app.json                     the manifest — id, grants, posture, functions
src/client.js                       the client half
src/server/actions/createNote.js    returns JSON, writes state, revalidates
src/server/actions/deleteNote.js
src/server/components/NoteList.js   returns a UI payload; never renders
```

## Build, package, install, serve

```bash
cd rust && cargo build -p js2elpian --bin elpian-compile \
                       -p elpian-pkg  --bin elpian-pkg \
                       -p elpian-host --bin elpiand && cd ..

S=samples/closed-fullstack
mkdir -p $S/build/fn
rust/target/debug/elpian-compile bytecode $S/src/client.js                        $S/build/client.bc
rust/target/debug/elpian-compile bytecode $S/src/server/actions/createNote.js     $S/build/fn/createNote.bc
rust/target/debug/elpian-compile bytecode $S/src/server/actions/deleteNote.js     $S/build/fn/deleteNote.bc
rust/target/debug/elpian-compile bytecode $S/src/server/components/NoteList.js    $S/build/fn/NoteList.bc

export ELPIAN_SIGNING_KEY=dev-key
rust/target/debug/elpian-pkg package $S /tmp/notes.elpianpkg
rust/target/debug/elpian-pkg verify  /tmp/notes.elpianpkg
rust/target/debug/elpian-pkg install /tmp/notes.elpianpkg --registry /tmp/registry
rust/target/debug/elpiand --registry /tmp/registry --port 4180
```

> The server modules are compiled with the SDK concatenated in a real build.
> `scripts/e2e-fullstack.sh` does the whole chain end to end with self-contained
> sources, and is the version that runs in CI.

## Try it

```bash
curl -s localhost:4180/apps/notes/manifest.json
curl -s -X POST -d '{"text":"first note"}'  localhost:4180/apps/notes/fn/createNote
curl -s -X POST localhost:4180/apps/notes/render/NoteList
curl -s -X POST localhost:4180/apps/notes/render/NoteList   # coldStart:false — cached
```

## What to look at

* **`createNote.js`** — the failure path is a returned value, not a throw. The
  subset has no `try`/`catch`, so it could not be anything else.
* **`NoteList.js`** — a `while` loop, not `for…of`; `!= null` rather than
  truthiness, because `x == null` is true for `0`. Both are subset constraints,
  not style.
* **`ui(tree, ["notes"], 60)`** — caching is opt-in. The tag lets the actions
  invalidate it; the TTL means a missed revalidation self-corrects rather than
  serving a stale page forever.
* **`"network": "closed"`** — the app does not hold `Capability::Network` at
  all. Its egress is *absent*, not blocked downstream.

See [wiki/18-fullstack.md](../../wiki/18-fullstack.md).
