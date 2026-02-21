import 'elpian_vm.dart';

/// Common contract for runtime backends used by [ElpianVmWidget].
abstract class VmRuntimeClient {
  void registerHostHandler(String apiName, HostCallHandler handler);

  void setDefaultHostHandler(HostCallHandler handler);

  Future<String> run();

  Future<String> callFunction(String funcName);

  Future<String> callFunctionWithInput(String funcName, String inputJson);

  Future<void> dispose();
}
