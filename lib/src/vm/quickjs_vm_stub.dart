import 'elpian_vm.dart';
import 'governance/host_side_governor.dart';
import 'vm_runtime_client.dart';

class QuickJsVm implements VmRuntimeClient {
  QuickJsVm({required this.machineId});

  final String machineId;

  /// Nothing runs here, so nothing is governed. Reporting
  /// `GovernanceSupport.none` keeps a host from believing a mini app on this
  /// platform is sandboxed when the runtime is not even present.
  @override
  final UnenforcedGovernor governor = const UnenforcedGovernor(
    'the QuickJS runtime is not available on this platform',
  );

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
