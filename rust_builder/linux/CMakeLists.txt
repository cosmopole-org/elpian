cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "rust_lib_elpian_vm")
project(${PROJECT_NAME} LANGUAGES CXX)

# Flutter consumes this plugin through an ephemeral symlink. Resolve the real
# package location before walking to the sibling Rust crate.
get_filename_component(PLUGIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
get_filename_component(ELPIAN_RUST_ROOT "${PLUGIN_ROOT}/../rust" REALPATH)

# Invoke the build for native code shared library
add_custom_command(
    OUTPUT "${ELPIAN_RUST_ROOT}/target/release/libelpian_vm.so"
    COMMAND cargo build --manifest-path "${ELPIAN_RUST_ROOT}/Cargo.toml" --release
    USES_TERMINAL
)

add_custom_target(${PROJECT_NAME}_target
    DEPENDS "${ELPIAN_RUST_ROOT}/target/release/libelpian_vm.so"
)

set(rust_lib_elpian_vm_bundled_libraries
    "${ELPIAN_RUST_ROOT}/target/release/libelpian_vm.so"
    PARENT_SCOPE
)
