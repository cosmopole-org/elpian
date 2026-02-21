export 'quickjs_vm_stub.dart'
    if (dart.library.io) 'quickjs_vm_native.dart'
    if (dart.library.js_interop) 'quickjs_vm_web.dart';
