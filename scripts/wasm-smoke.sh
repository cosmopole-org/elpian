#!/usr/bin/env bash
#
# Build the Elpian VM for the browser target and actually run it.
#
# `cargo build --target wasm32-unknown-unknown` proves only that the code
# compiles, and the failure this guards against compiles perfectly: std's
# `Instant::now()` on that target is an `unreachable`, so a clock read on the
# per-turn path killed the VM on its first turn and put a blank page on
# GitHub Pages. Building is not running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

command -v wasm-pack >/dev/null || {
  echo "wasm-pack is required: cargo install wasm-pack" >&2
  exit 2
}

echo "== building elpian-wasm for wasm32-unknown-unknown =="
(cd "$ROOT/rust/crates/elpian-wasm" && wasm-pack build --target nodejs --out-dir "$OUT" >/dev/null 2>&1)

echo "== running it =="
node "$ROOT/scripts/wasm-smoke.cjs" "$OUT"
