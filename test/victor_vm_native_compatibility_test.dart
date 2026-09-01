import 'dart:convert';

import 'package:elpian_ui/src/vm/elpian_vm.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _stringValue(String value) => {
      'type': 'string',
      'data': {'value': value},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Victor VM crosses the native Dart FFI and legacy host-call boundary',
      () async {
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
  });
}
