import 'elpian_vm.dart';
import 'vm_runtime_client.dart';

class WasmVm implements VmRuntimeClient {
  WasmVm({required this.machineId});

  final String machineId;

  static Future<void> initialize() async {}

  static Future<WasmVm> fromCode(String machineId, String code) async {
    throw UnsupportedError('WASM runtime is not supported on this platform.');
  }

  static Future<WasmVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError('WASM runtime expects a JSON runtime config in `code`.');
  }

  @override
  void registerHostHandler(String apiName, HostCallHandler handler) {}

  @override
  void registerHostHandlers(Map<String, HostCallHandler> handlers) {}

  @override
  void setDefaultHostHandler(HostCallHandler handler) {}

  @override
  Future<String> run() async => '';

  @override
  Future<String> callFunction(String funcName) async => '';

  @override
  Future<String> callFunctionWithInput(String funcName, String inputJson) async => '';

  @override
  Future<void> dispose() async {}
}
