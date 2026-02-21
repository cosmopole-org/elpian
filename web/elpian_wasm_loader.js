async function loadElpianWasm() {
  try {
    const modulePath = './wasm/elpian_vm/elpian_vm.js';

    // If the wasm bundle is not present (e.g. local debug without prebuild),
    // skip loading without breaking Flutter bootstrap.
    const probe = await fetch(modulePath, { method: 'HEAD' });
    if (!probe.ok) {
      globalThis.elpianWasmLoaded = false;
      console.warn(`Elpian WASM module not found at ${modulePath}; continuing without WASM.`);
      return;
    }

    const wasmModule = await import(modulePath);
    const initWasm = wasmModule.default;

    await initWasm();

    // Expose wasm-bindgen exports on the global object for Dart `dart:js_interop`
    // bindings that use @JS('...') top-level symbol lookups.
    globalThis.elpian_wasm_init = wasmModule.elpian_wasm_init;
    globalThis.elpian_wasm_create_vm_from_ast = wasmModule.elpian_wasm_create_vm_from_ast;
    globalThis.elpian_wasm_create_vm_from_code = wasmModule.elpian_wasm_create_vm_from_code;
    globalThis.elpian_wasm_validate_ast = wasmModule.elpian_wasm_validate_ast;
    globalThis.elpian_wasm_execute = wasmModule.elpian_wasm_execute;
    globalThis.elpian_wasm_execute_func = wasmModule.elpian_wasm_execute_func;
    globalThis.elpian_wasm_execute_func_with_input = wasmModule.elpian_wasm_execute_func_with_input;
    globalThis.elpian_wasm_continue_execution = wasmModule.elpian_wasm_continue_execution;
    globalThis.elpian_wasm_destroy_vm = wasmModule.elpian_wasm_destroy_vm;
    globalThis.elpian_wasm_vm_exists = wasmModule.elpian_wasm_vm_exists;

    globalThis.elpian_bevy_wasm_init = wasmModule.elpian_bevy_wasm_init;
    globalThis.elpian_bevy_wasm_create_scene = wasmModule.elpian_bevy_wasm_create_scene;
    globalThis.elpian_bevy_wasm_update_scene = wasmModule.elpian_bevy_wasm_update_scene;
    globalThis.elpian_bevy_wasm_render_frame = wasmModule.elpian_bevy_wasm_render_frame;
    globalThis.elpian_bevy_wasm_resize_scene = wasmModule.elpian_bevy_wasm_resize_scene;
    globalThis.elpian_bevy_wasm_get_frame = wasmModule.elpian_bevy_wasm_get_frame;
    globalThis.elpian_bevy_wasm_get_frame_bytes = wasmModule.elpian_bevy_wasm_get_frame_bytes;
    globalThis.elpian_bevy_wasm_send_input = wasmModule.elpian_bevy_wasm_send_input;
    globalThis.elpian_bevy_wasm_destroy_scene = wasmModule.elpian_bevy_wasm_destroy_scene;
    globalThis.elpian_bevy_wasm_scene_exists = wasmModule.elpian_bevy_wasm_scene_exists;
    globalThis.elpian_bevy_wasm_get_elapsed_time = wasmModule.elpian_bevy_wasm_get_elapsed_time;
    globalThis.elpian_bevy_wasm_get_frame_count = wasmModule.elpian_bevy_wasm_get_frame_count;

    globalThis.elpianWasmLoaded = true;
  } catch (error) {
    globalThis.elpianWasmLoaded = false;
    console.error('Failed to load Elpian WASM module:', error);
  }
}

loadElpianWasm();
