import 'elpian_vm.dart';

/// Common contract for runtime backends used by [ElpianVmWidget].
abstract class VmRuntimeClient {
  void registerHostHandler(String apiName, HostCallHandler handler);

  void registerHostHandlers(Map<String, HostCallHandler> handlers);

  void setDefaultHostHandler(HostCallHandler handler);

  /// Inject host-side global metadata (environment, viewport, page info, etc.)
  /// into the runtime, when supported.
  Future<void> setGlobalHostData(Map<String, dynamic> data);

  Future<String> run();

  Future<String> callFunction(String funcName);

  Future<String> callFunctionWithInput(String funcName, String inputJson);

  Future<void> dispose();
}
