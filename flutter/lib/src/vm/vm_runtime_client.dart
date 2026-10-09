import 'elpian_vm.dart';
import 'governance/governor.dart';

/// Common contract for runtime backends used by [ElpianVmWidget].
///
/// Every backend must answer for how a mini app running on it is governed. The
/// framework offers three — the Elpian VM, QuickJS and WASM — and before
/// [governor] existed only the first enforced anything, with nothing in the
/// contract to say so. A mini app could select a runtime and escape governance
/// entirely just by choosing.
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

  /// Governs this instance: its budgets, capabilities and lifecycle.
  ///
  /// Read [VmGovernor.governanceSupport] before trusting it with third-party
  /// code — a backend reports honestly which axes it can actually enforce, and
  /// one that cannot bound instructions cannot stop an infinite loop whatever
  /// limits are set on it.
  VmGovernor get governor;
}
