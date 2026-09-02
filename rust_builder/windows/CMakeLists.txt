cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust_lib_elpian_vm")
project(${PROJECT_NAME} LANGUAGES CXX)

get_filename_component(PLUGIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
get_filename_component(ELPIAN_RUST_ROOT "${PLUGIN_ROOT}/../rust" REALPATH)

# Invoke the build for native code shared library
add_custom_command(
    OUTPUT "${ELPIAN_RUST_ROOT}/target/release/elpian_vm.dll"
    # Build the C ABI package specifically. It produces the artifact named
    # `elpian_vm` that the Dart bindings open, and pulls in the VM and the
    # multi-VM runtime; the workspace root is virtual, and building every
    # member would also compile the Godot C ABI, which Flutter does not link.
    COMMAND cargo build --release -p elpian-ffi
            --manifest-path "${ELPIAN_RUST_ROOT}/Cargo.toml"
    USES_TERMINAL
)

add_custom_target(${PROJECT_NAME}_target
    DEPENDS "${ELPIAN_RUST_ROOT}/target/release/elpian_vm.dll"
)

set(rust_lib_elpian_vm_bundled_libraries
    "${ELPIAN_RUST_ROOT}/target/release/elpian_vm.dll"
    PARENT_SCOPE
)
