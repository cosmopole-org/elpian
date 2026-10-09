#!/usr/bin/env bash
# Build libelpian_vm.a (the Elpian VM's C ABI, rust/crates/elpian-ffi) for iOS
# devices and simulators and package it as Frameworks/ElpianVM.xcframework,
# which Package.swift picks up as the `ElpianVM` binary target.
#
#   aarch64-apple-ios       → ios-arm64
#   aarch64-apple-ios-sim   ┐
#   x86_64-apple-ios        ┘ lipo → ios-arm64_x86_64-simulator
#
# Needs macOS with Xcode (xcodebuild, lipo) and rustup; the targets are added
# here. IPHONEOS_DEPLOYMENT_TARGET defaults to the package's iOS 15.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
rust="$(cd "$here/../../rust" && pwd)"
out="$here/Frameworks/ElpianVM.xcframework"
work="$here/.build/elpian-vm"
profile="${PROFILE:-release}"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
rustup target add "${targets[@]}" >/dev/null

# Keep the Swift module's copy of the header in step with the crate.
"$here/scripts/sync-assets.sh"

cd "$rust"
for t in "${targets[@]}"; do
  if [ "$profile" = "release" ]; then
    cargo build --release -p elpian-ffi --target "$t"
  else
    cargo build -p elpian-ffi --target "$t"
  fi
done

lib() { echo "$rust/target/$1/$profile/libelpian_vm.a"; }

rm -rf "$work" "$out"
mkdir -p "$work/ios" "$work/sim" "$work/include"
cp "$(lib aarch64-apple-ios)" "$work/ios/libelpian_vm.a"
lipo -create "$(lib aarch64-apple-ios-sim)" "$(lib x86_64-apple-ios)" -output "$work/sim/libelpian_vm.a"
# Headers only (no module map): the CElpianVM target declares the module.
cp "$rust/crates/elpian-ffi/include/elpian_vm.h" "$work/include/"

mkdir -p "$(dirname "$out")"
xcodebuild -create-xcframework \
  -library "$work/ios/libelpian_vm.a" -headers "$work/include" \
  -library "$work/sim/libelpian_vm.a" -headers "$work/include" \
  -output "$out"
echo "ElpianVM.xcframework written to $out"
