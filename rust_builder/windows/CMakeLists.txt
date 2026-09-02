cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust_lib_elpian_vm")
project(${PROJECT_NAME} LANGUAGES CXX)

get_filename_component(PLUGIN_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
get_filename_component(ELPIAN_RUST_ROOT "${PLUGIN_ROOT}/../rust" REALPATH)

# Invoke the build for native code shared library
add_custom_command(
    OUTPUT "${ELPIAN_RUST_ROOT}/target/release/elpian_vm.dll"
    # Build the VM package specifically: the workspace root is virtual, and
    # building every member here would also compile the Godot C ABI and the
    # compiler front-ends, which the Flutter desktop host does not link.
    COMMAND cargo build --release -p elpian-vm
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
