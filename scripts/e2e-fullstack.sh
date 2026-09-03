#!/usr/bin/env bash
#
# The fullstack end-to-end path, through the real binaries.
#
# Unit and integration tests exercise the libraries; this exercises the things
# an operator actually runs. It is the test that would catch a CLI that builds a
# package the server cannot read, or a registry layout the two halves disagree
# about — a class of break no library test can see, because both sides pass
# their own tests while disagreeing with each other.
#
#   source .js  →  bytecode  →  signed package  →  verify  →  install
#                →  serve  →  invoke an action  →  render a component
#
# Usage: scripts/e2e-fullstack.sh [--release]
set -euo pipefail

PROFILE_DIR=debug
CARGO_FLAGS=()
if [[ "${1:-}" == "--release" ]]; then
  PROFILE_DIR=release
  CARGO_FLAGS=(--release)
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/rust/target/$PROFILE_DIR"
WORK="$(mktemp -d)"
PORT="${ELPIAN_E2E_PORT:-4199}"
DAEMON_PID=""

cleanup() {
  [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAIL: %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '  ok: %s\n' "$1"; }

step "build the toolchain"
(cd "$ROOT/rust" && cargo build "${CARGO_FLAGS[@]}" \
  -p js2elpian --bin elpian-compile \
  -p elpian-pkg --bin elpian-pkg \
  -p elpian-host --bin elpiand >/dev/null)
ok "elpian-compile, elpian-pkg, elpiand"

step "a project"
mkdir -p "$WORK/proj/src" "$WORK/proj/build/fn" "$WORK/registry"
cat > "$WORK/proj/src/client.js" <<'EOF'
function view() { return "notes client"; }
EOF
cat > "$WORK/proj/src/save.js" <<'EOF'
function save(v) { return askHost("kv.set", ["note", v]); }
EOF
cat > "$WORK/proj/src/NoteList.js" <<'EOF'
function NoteList() {
  var text = askHost("kv.get", ["note"]);
  return { component: { type: "text", text: text }, revalidate: { tags: ["notes"] } };
}
EOF
cat > "$WORK/proj/elpian.app.json" <<'EOF'
{
  "id": "notes",
  "version": "1.2.0",
  "capabilities": ["state", "logging"],
  "network": "closed",
  "limits": { "instructions": 50000000, "memoryBytes": 33554432 },
  "functions": [
    { "name": "save", "kind": "action" },
    { "name": "NoteList", "kind": "component" }
  ]
}
EOF

step "compile"
"$BIN/elpian-compile" bytecode "$WORK/proj/src/client.js"   "$WORK/proj/build/client.bc"
"$BIN/elpian-compile" bytecode "$WORK/proj/src/save.js"     "$WORK/proj/build/fn/save.bc"
"$BIN/elpian-compile" bytecode "$WORK/proj/src/NoteList.js" "$WORK/proj/build/fn/NoteList.bc"
ok "three modules — one per function, plus the client half"

step "package, twice"
export ELPIAN_SIGNING_KEY="e2e-signing-key"
"$BIN/elpian-pkg" package "$WORK/proj" "$WORK/a.elpianpkg" >/dev/null
"$BIN/elpian-pkg" package "$WORK/proj" "$WORK/b.elpianpkg" >/dev/null
cmp -s "$WORK/a.elpianpkg" "$WORK/b.elpianpkg" \
  || fail "two builds of the same project produced different bytes"
ok "byte-identical rebuild"

step "inspect without a key"
env -u ELPIAN_SIGNING_KEY "$BIN/elpian-pkg" inspect "$WORK/a.elpianpkg" 2>/dev/null \
  | grep -q '"id": "notes"' || fail "inspect did not read the manifest"
ok "an unverified index is readable, as it must be before you decide to trust it"

step "verify"
"$BIN/elpian-pkg" verify "$WORK/a.elpianpkg" >/dev/null || fail "a good package did not verify"
ok "correct key verifies"
if ELPIAN_SIGNING_KEY="the-wrong-key" "$BIN/elpian-pkg" verify "$WORK/a.elpianpkg" >/dev/null 2>&1; then
  fail "a package verified under the wrong key"
fi
ok "wrong key is refused"

step "tamper"
cp "$WORK/a.elpianpkg" "$WORK/tampered.elpianpkg"
# Flip a byte in the blob region.
printf '\xff' | dd of="$WORK/tampered.elpianpkg" bs=1 seek=2000 count=1 conv=notrunc 2>/dev/null
if "$BIN/elpian-pkg" verify "$WORK/tampered.elpianpkg" >/dev/null 2>&1; then
  fail "a tampered package verified"
fi
ok "a flipped byte is caught"

step "install"
"$BIN/elpian-pkg" install "$WORK/a.elpianpkg" --registry "$WORK/registry" >/dev/null
[[ -f "$WORK/registry/notes/app.json" ]]        || fail "no app.json was written"
[[ -f "$WORK/registry/notes/client.bc" ]]       || fail "no client bytecode"
[[ -f "$WORK/registry/notes/fn/save.bc" ]]      || fail "no save module"
[[ -f "$WORK/registry/notes/fn/NoteList.bc" ]]  || fail "no NoteList module"
ok "the registry layout the server reads"

step "serve"
"$BIN/elpiand" --registry "$WORK/registry" --port "$PORT" > "$WORK/daemon.log" 2>&1 &
DAEMON_PID=$!
for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 0.1
done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || fail "the host did not come up"
ok "listening on $PORT"

step "what a device fetches"
MANIFEST=$(curl -s "http://127.0.0.1:$PORT/apps/notes/manifest.json")
echo "$MANIFEST" | grep -q '"network":"closed"'  || fail "the manifest lost its network posture"
echo "$MANIFEST" | grep -q '"kind":"component"'  || fail "the function table lost its kinds"
ok "manifest names the client, the functions and the posture"
CLIENT_BYTES=$(curl -s "http://127.0.0.1:$PORT/apps/notes/client.bc" | wc -c)
[[ "$CLIENT_BYTES" -gt 100 ]] || fail "client bytecode was not served"
ok "client bytecode served ($CLIENT_BYTES bytes)"

step "invoke an action"
SAVED=$(curl -s -X POST -d '"through the whole chain"' "http://127.0.0.1:$PORT/apps/notes/fn/save")
echo "$SAVED" | grep -q '"ok":true' || fail "the action failed: $SAVED"
ok "action returned"

step "render a server component"
FIRST=$(curl -s -X POST "http://127.0.0.1:$PORT/apps/notes/render/NoteList")
echo "$FIRST" | grep -q 'through the whole chain' \
  || fail "the component did not see the state the action wrote: $FIRST"
echo "$FIRST" | grep -q '"coldStart":true' || fail "the first render should be cold"
ok "component rendered the action's state"

SECOND=$(curl -s -X POST "http://127.0.0.1:$PORT/apps/notes/render/NoteList")
echo "$SECOND" | grep -q '"coldStart":false' \
  || fail "the second render did not reuse a warm instance or the cache: $SECOND"
ok "second render did not pay a cold start"

step "the closed posture"
NET=$(curl -s -X POST "http://127.0.0.1:$PORT/apps/notes/fn/save" -d '"x"')
echo "$NET" | grep -q '"ok":true' || fail "the app stopped working"
grep -qi 'net\.fetch' "$WORK/daemon.log" && fail "an outbound call was attempted"
ok "no egress from a closed app"

step "wrong doors"
[[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/apps/notes/fn/NoteList")" == "400" ]] \
  || fail "a component invoked as an action should be 400"
[[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/apps/ghost/fn/save")" == "404" ]] \
  || fail "an unknown app should be 404"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/admin/apps")" == "401" ]] \
  || fail "the admin surface should be closed by default"
ok "kind mismatch 400, unknown app 404, admin 401"

printf '\n\033[32mall end-to-end checks passed\033[0m\n'
