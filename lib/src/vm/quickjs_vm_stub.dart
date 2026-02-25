import 'elpian_vm.dart';
import 'vm_runtime_client.dart';

class QuickJsVm implements VmRuntimeClient {
  QuickJsVm({required this.machineId});

  final String machineId;

  static Future<void> initialize() async {}

  static Future<QuickJsVm> fromCode(String machineId, String code) async {
    throw UnsupportedError(
        'QuickJS runtime is not available on this platform.');
  }

  static Future<QuickJsVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError('QuickJS runtime expects JavaScript source code.');
  }

  @override
  void registerHostHandler(String apiName, HostCallHandler handler) {}

  @override
  void registerHostHandlers(Map<String, HostCallHandler> handlers) {}

  @override
  void setDefaultHostHandler(HostCallHandler handler) {}

  @override
  Future<void> setGlobalHostData(Map<String, dynamic> data) async {}

  @override
  Future<String> run() async => '';

  @override
  Future<String> callFunction(String funcName) async => '';

  @override
  Future<String> callFunctionWithInput(
          String funcName, String inputJson) async =>
      '';

  @override
  Future<void> dispose() async {}
}
