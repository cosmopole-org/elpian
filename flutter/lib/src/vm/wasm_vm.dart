export 'wasm_vm_stub.dart'
    if (dart.library.io) 'wasm_vm_runtime.dart'
    if (dart.library.js_interop) 'wasm_vm_runtime.dart';
