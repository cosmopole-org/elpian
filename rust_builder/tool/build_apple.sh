#!/usr/bin/env bash
# Build libelpian_vm as a static library for an Apple platform and stage it
# where the CocoaPods target can link it.
#
# Replaces a `cargokit/build_pod.sh` invocation that pointed at a directory
# never present in this repository, so the iOS and macOS builds could not
# succeed at all.
#
# Usage: build_apple.sh <ios|macos> <output-dir>
set -euo pipefail

PLATFORM="${1:?usage: build_apple.sh <ios|macos> <output-dir>}"
OUT_DIR="${2:?usage: build_apple.sh <ios|macos> <output-dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/../../rust/crates/elpian-vm/Cargo.toml"
TARGET_DIR="$SCRIPT_DIR/../../rust/target"

if ! command -v cargo >/dev/null 2>&1; then
  echo "build_apple.sh: cargo not found. Install Rust: https://rustup.rs" >&2
  exit 1
fi

# Xcode passes the architectures it wants; fall back to both when run by hand.
ARCHS="${ARCHS:-arm64 x86_64}"
CONFIG="${CONFIGURATION:-Release}"
PROFILE_FLAG=""
PROFILE_DIR="debug"
if [ "$CONFIG" != "Debug" ]; then
  PROFILE_FLAG="--release"
  PROFILE_DIR="release"
fi

triple_for() {
  case "$PLATFORM:$1" in
    ios:arm64)   [ "${PLATFORM_NAME:-iphoneos}" = "iphonesimulator" ] \
                   && echo "aarch64-apple-ios-sim" || echo "aarch64-apple-ios" ;;
    ios:x86_64)  echo "x86_64-apple-ios" ;;
    macos:arm64) echo "aarch64-apple-darwin" ;;
    macos:x86_64) echo "x86_64-apple-darwin" ;;
    *) echo "build_apple.sh: unsupported $PLATFORM/$1" >&2; exit 1 ;;
  esac
}

BUILT=()
for arch in $ARCHS; do
  triple="$(triple_for "$arch")"
  rustup target add "$triple" >/dev/null 2>&1 || true
  echo "build_apple.sh: cargo build --target $triple $PROFILE_FLAG"
  cargo build --manifest-path "$MANIFEST" --target "$triple" $PROFILE_FLAG
  BUILT+=("$TARGET_DIR/$triple/$PROFILE_DIR/libelpian_vm.a")
done

mkdir -p "$OUT_DIR"
if [ "${#BUILT[@]}" -gt 1 ]; then
  # Xcode links one library per target, so several architectures are fattened
  # into a single universal binary rather than left as separate files.
  lipo -create "${BUILT[@]}" -output "$OUT_DIR/libelpian_vm.a"
else
  cp "${BUILT[0]}" "$OUT_DIR/libelpian_vm.a"
fi
echo "build_apple.sh: staged $OUT_DIR/libelpian_vm.a"
