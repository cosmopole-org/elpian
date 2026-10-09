#!/usr/bin/env bash
# Copy the shared inputs the Swift package bundles from elsewhere in the repo:
#  - the C ABI header of libelpian_vm (rust/crates/elpian-ffi/include) into the
#    CElpianVM module;
#  - the Material Icons font (native/assets/fonts) into the Elpian target's
#    resources.
# ElpianCoreTests/BundledCopiesTests fails when a copy drifts from its source.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
mkdir -p "$here/Sources/CElpianVM/include" "$here/Sources/Elpian/Resources/Fonts"
cp "$repo/rust/crates/elpian-ffi/include/elpian_vm.h" "$here/Sources/CElpianVM/include/elpian_vm.h"
cp "$repo/native/assets/fonts/MaterialIcons-Regular.ttf" "$here/Sources/Elpian/Resources/Fonts/MaterialIcons-Regular.ttf"
cp "$repo/native/assets/fonts/MaterialIcons-LICENSE.txt" "$here/Sources/Elpian/Resources/Fonts/MaterialIcons-LICENSE.txt"
echo "synced elpian_vm.h and MaterialIcons into $here/Sources"
