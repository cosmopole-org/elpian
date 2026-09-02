// The Elpian VM across the real native FFI boundary: create from AST, run,
// service a host call, tear down.
//
// Was `victor_vm_native_compatibility_test.dart`, named for a predecessor
// project rather than for what it checks.
import 'dart:convert';

import 'package:elpian_ui/src/vm/elpian_vm.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _stringValue(String value) => {
      'type': 'string',
      'data': {'value': value},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // This test exercises the real FFI boundary, so it needs the compiled native
  // library. Skip (rather than fail) when it is absent, so a checkout that has
  // not run the Rust build still reports a green suite — CI builds the library
  // first and therefore always runs the body.
  //
  //   cd rust && cargo build --release
  final skip = ElpianVm.isRuntimeAvailable
      ? null
      : 'Native VM library not built. Run: cd rust && cargo build --release '
          '(loader error: ${ElpianVm.lastApiError})';

  test('the VM crosses the native Dart FFI and host-call boundary', () async {
    await ElpianVm.initialize();
    final ast = jsonEncode({
      'type': 'program',
      'body': [
        {
          'type': 'host_call',
          'data': {
            'name': 'render',
            'args': [_stringValue('{"type":"text","text":"ready"}')],
          },
        },
      ],
    });

    final vm = await ElpianVm.fromAst('dart-native-compat', ast);
    expect(vm, isNotNull, reason: ElpianVm.lastApiError);

    String? payload;
    vm!.registerHostHandler('render', (_, value) {
      payload = value;
      return jsonEncode(_stringValue('rendered'));
    });

    expect(await vm.run(), isNotEmpty);
    expect(payload, isNotNull);
    await vm.dispose();
  }, skip: skip);
}
