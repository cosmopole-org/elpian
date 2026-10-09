#!/usr/bin/env bash
# Build libelpian_vm.so (the Elpian VM, with its JNI exports) for every Android
# ABI into elpian/src/main/jniLibs. Needs the Android NDK (ANDROID_NDK_HOME)
# and cargo-ndk (`cargo install cargo-ndk`); the rustup targets are added here.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
rust="$here/../../rust"
targets=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android)
rustup target add "${targets[@]}" >/dev/null
cd "$rust"
cargo ndk \
  -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 \
  -P 24 \
  -o "$here/elpian/src/main/jniLibs" \
  build --release -p elpian-ffi --features jni
echo "libelpian_vm.so written to $here/elpian/src/main/jniLibs"
