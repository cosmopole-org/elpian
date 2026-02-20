import initWasm, * as wasmApi from './wasm/elpian_vm/elpian_vm.js';

async function loadElpianWasm() {
  try {
    await initWasm();

    // Expose wasm-bindgen exports on the global object for Dart `dart:js_interop`
    // bindings that use @JS('...') top-level symbol lookups.
    globalThis.elpian_wasm_init = wasmApi.elpian_wasm_init;
    globalThis.elpian_wasm_create_vm_from_ast = wasmApi.elpian_wasm_create_vm_from_ast;
    globalThis.elpian_wasm_create_vm_from_code = wasmApi.elpian_wasm_create_vm_from_code;
    globalThis.elpian_wasm_validate_ast = wasmApi.elpian_wasm_validate_ast;
    globalThis.elpian_wasm_execute = wasmApi.elpian_wasm_execute;
    globalThis.elpian_wasm_execute_func = wasmApi.elpian_wasm_execute_func;
    globalThis.elpian_wasm_execute_func_with_input = wasmApi.elpian_wasm_execute_func_with_input;
    globalThis.elpian_wasm_continue_execution = wasmApi.elpian_wasm_continue_execution;
    globalThis.elpian_wasm_destroy_vm = wasmApi.elpian_wasm_destroy_vm;
    globalThis.elpian_wasm_vm_exists = wasmApi.elpian_wasm_vm_exists;

    globalThis.elpian_bevy_wasm_init = wasmApi.elpian_bevy_wasm_init;
    globalThis.elpian_bevy_wasm_create_scene = wasmApi.elpian_bevy_wasm_create_scene;
    globalThis.elpian_bevy_wasm_update_scene = wasmApi.elpian_bevy_wasm_update_scene;
    globalThis.elpian_bevy_wasm_render_frame = wasmApi.elpian_bevy_wasm_render_frame;
    globalThis.elpian_bevy_wasm_resize_scene = wasmApi.elpian_bevy_wasm_resize_scene;
    globalThis.elpian_bevy_wasm_get_frame = wasmApi.elpian_bevy_wasm_get_frame;
    globalThis.elpian_bevy_wasm_get_frame_bytes = wasmApi.elpian_bevy_wasm_get_frame_bytes;
    globalThis.elpian_bevy_wasm_send_input = wasmApi.elpian_bevy_wasm_send_input;
    globalThis.elpian_bevy_wasm_destroy_scene = wasmApi.elpian_bevy_wasm_destroy_scene;
    globalThis.elpian_bevy_wasm_scene_exists = wasmApi.elpian_bevy_wasm_scene_exists;
    globalThis.elpian_bevy_wasm_get_elapsed_time = wasmApi.elpian_bevy_wasm_get_elapsed_time;
    globalThis.elpian_bevy_wasm_get_frame_count = wasmApi.elpian_bevy_wasm_get_frame_count;

    globalThis.elpianWasmLoaded = true;
  } catch (error) {
    globalThis.elpianWasmLoaded = false;
    console.error('Failed to load Elpian WASM module:', error);
  }
}

loadElpianWasm();
