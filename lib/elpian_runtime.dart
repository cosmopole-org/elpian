/// The Elpian runtimes: the VM instances a mini app's code runs on.
///
/// Import this on its own when you are embedding or driving a runtime without
/// rendering — a server-side host, a test harness, a tool.
///
/// Everything here is also exported from `elpian_ui.dart`.
library;

export 'src/vm/elpian_vm.dart';
export 'src/vm/runtime_kind.dart';
export 'src/vm/vm_runtime_client.dart';
export 'src/vm/host_handler.dart';
export 'src/vm/wasm_vm.dart';
export 'src/vm/ffi/vm_types.dart';
export 'src/vm/ffi/api.dart'
    if (dart.library.js_interop) 'src/vm/ffi/api_web.dart' show ElpianVmApi;

// Governance travels with the runtime: an embedder that can start a mini app
// should always be able to bound it.
export 'elpian_governance.dart';
