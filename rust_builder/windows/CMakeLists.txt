cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust_lib_elpian_vm")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared library
add_custom_command(
    OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/release/elpian_vm.dll"
    COMMAND cargo build --manifest-path "${CMAKE_CURRENT_SOURCE_DIR}/../rust/Cargo.toml" --release
    USES_TERMINAL
)

add_custom_target(${PROJECT_NAME}_target
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/release/elpian_vm.dll"
)

set(elpian_vm_bundled_libraries
    "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/release/elpian_vm.dll"
    PARENT_SCOPE
)
