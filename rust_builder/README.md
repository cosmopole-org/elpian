# rust_builder

The Flutter plugin that builds and links the Elpian VM native library. It ships
no Dart and no platform code — `ffiPlugin: true` on every platform — its only
job is to put `libelpian_vm` where the app can load it.

## What each platform does

| Platform | Wiring | Produces |
|---|---|---|
| Linux | `linux/CMakeLists.txt` → `cargo build --release -p elpian-ffi` | `rust/target/release/libelpian_vm.so`, bundled |
| Windows | `windows/CMakeLists.txt` → same | `rust/target/release/elpian_vm.dll`, bundled |
| Android | `android/build.gradle` → `cargo ndk` per ABI | `build/jniLibs/<abi>/libelpian_vm.so` |
| iOS | `ios/*.podspec` → `tool/build_apple.sh ios` | a universal `libelpian_vm.a`, linked |
| macOS | `macos/*.podspec` → `tool/build_apple.sh macos` | a universal `libelpian_vm.a`, linked |
| Web | not here — `wasm-pack` builds `assets/web_runtime/wasm/` | see `rust/README.md` |

## History

Three of these did not work. The iOS and macOS podspecs invoked
`../cargokit/build_pod.sh` — cargokit has never been in this repository — and
declared `source_files = 'Classes/**/*'` against a directory that does not
exist. `android/build.gradle` was a bare AGP library stanza that never invoked
cargo at all.

The failure was silent by design: `ElpianVmApi` catches the
`DynamicLibrary.open` failure into `lastError`, so VM creation returned `false`
and the app rendered nothing rather than reporting a missing engine. Only Linux
and Windows ever built the library, against a README claiming six platforms.

`ElpianVm.isRuntimeAvailable` now exists so a host can tell the difference
between "the runtime is missing" and "the program failed".

## Extra toolchain

Desktop needs only a Rust toolchain. The mobile targets need cross-compilers:

```bash
# Android
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
# and ANDROID_NDK_HOME pointing at an installed NDK

# iOS / macOS (added automatically by build_apple.sh when rustup is present)
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

## Verification status

The Linux path is exercised on every CI run and locally. The Windows CMake is
the same shape and differs only in artifact name. **The Android, iOS and macOS
wiring has not been executed** — it needs an NDK and Xcode respectively, which
no CI job here has yet. Treat it as reviewed but unproven, and add a
build-only CI job per platform before relying on it.
