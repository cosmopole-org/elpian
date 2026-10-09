/*
 * CElpianVM only declares the C ABI of libelpian_vm (include/elpian_vm.h,
 * copied from rust/crates/elpian-ffi/include by scripts/sync-assets.sh).
 * SwiftPM needs one source file per C target; the library itself is linked
 * by the Elpian target (see Package.swift).
 */
#include "elpian_vm.h"
