import 'dart:convert';

import 'package:elpian_ui/src/vm/host_api_catalog.dart';
import 'package:elpian_ui/src/vm/host_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The host-call dispatcher's contract for calls it cannot service.
///
/// The `default` branch used to return `i16 0`, which a guest cannot tell apart
/// from a successful call returning zero. It catches every API the VM
/// advertises but the Dart host does not implement — `fs.*`, `net.*`, `gpu.*`,
/// `time.*`, `random.*`, `task.*`, `host.*` — so a mini app calling
/// `time.now()` was quietly told the time was 0.
void main() {
  Map<String, dynamic> reply(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  group('unserviced host APIs', () {
    test('an advertised but unimplemented API replies with a typed null', () {
      final handler = HostHandler();

      for (final api in ['time.now', 'net.fetch', 'fs.read', 'random.next']) {
        final r = reply(handler.handleHostCall(api, '{}'));
        expect(r['type'], 'null',
            reason: '$api should report that nothing is listening');
        expect(r['data']['value'], isNull);
      }
    });

    test('an entirely unknown API also replies with a typed null', () {
      final handler = HostHandler();
      final r = reply(handler.handleHostCall('not.a.real.api', '{}'));
      expect(r['type'], 'null');
    });

    test('the host is told which surface a guest reached for', () {
      final seen = <String, bool>{};
      final handler = HostHandler(
        onUnservicedApi: (api, advertised) => seen[api] = advertised,
      );

      handler.handleHostCall('time.now', '{}');
      handler.handleHostCall('not.a.real.api', '{}');

      expect(seen['time.now'], isTrue,
          reason: 'time.now is advertised by the VM, just not wired up here');
      expect(seen['not.a.real.api'], isFalse,
          reason: 'nothing advertises this name');
    });

    test('serviced APIs are unaffected', () {
      var rendered = false;
      final handler = HostHandler(onRender: (_, __) => rendered = true);

      final r = reply(handler.handleHostCall(
        'render',
        jsonEncode({
          'type': 'array',
          'data': {
            'value': [
              {
                'type': 'string',
                'data': {'value': '{"type":"text","text":"hi"}'}
              }
            ]
          }
        }),
      ));

      expect(rendered, isTrue);
      expect(r['type'], isNot('null'));
    });
  });

  group('generated catalog', () {
    test('carries the capability gating each API', () {
      // Generated from Capability::for_api, so the Dart host can refuse a call
      // for the same reason the VM would.
      expect(VmHostApiCatalog.capabilityFor('dom.appendChild'), 'dom');
      expect(VmHostApiCatalog.capabilityFor('canvas.fillRect'), 'canvas');
      expect(VmHostApiCatalog.capabilityFor('render'), 'render');
      expect(VmHostApiCatalog.capabilityFor('setTimeout'), 'timers');
      expect(VmHostApiCatalog.capabilityFor('net.fetch'), 'network');
      expect(VmHostApiCatalog.capabilityFor('fs.read'), 'storage');
    });

    test('an unadvertised name falls back to the fail-safe gate', () {
      expect(VmHostApiCatalog.capabilityFor('not.a.real.api'), 'other');
    });

    test('covers the whole advertised surface the VM offers', () {
      // The drift this replaced: 34 advertised APIs had no Dart presence at
      // all. Spot-check one from each family that was missing.
      for (final api in [
        'fs.read',
        'net.fetch',
        'gpu.submit',
        'time.now',
        'random.next',
        'task.spawn',
        'host.send',
        'vm.import',
        'log',
      ]) {
        expect(VmHostApiCatalog.allHostApiNames, contains(api));
      }
    });
  });
}
