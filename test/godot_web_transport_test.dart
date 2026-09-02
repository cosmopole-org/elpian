@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web half of the embedded-Godot seam, tested against a real browser with
/// no Godot export present.
///
/// The contract between Dart, the page glue (`godot/web/elpian_godot_web.js`)
/// and `OpSink.gd` is three `window` properties, so all of it can be exercised
/// by standing in for the engine: push ops and read the queue, park a reply and
/// watch the future complete. Only the engine itself needs CI.
@JS('eval')
external JSAny? _eval(JSString code);

String _evalString(String code) =>
    (_eval(code.toJS) as JSString?)?.toDart ?? '';

int _evalInt(String code) =>
    ((_eval(code.toJS) as JSNumber?)?.toDartInt) ?? -1;

void _resetPage() {
  _eval('''
    delete window.__elpianGodotDrain;
    delete window.__elpianGodotSurface;
    window.__elpianGodotQueue = [];
    window.__elpianGodotReplies = { pending: null };
  '''
      .toJS);
}

/// The drain half of the glue, which is all the engine side needs.
void _installDrainHook() {
  _eval('''
    window.__elpianGodotDrain = function () {
      var q = window.__elpianGodotQueue;
      if (!q.length) return '';
      var batch = '[' + q.join(',') + ']';
      q.length = 0;
      return batch;
    };
  '''
      .toJS);
}

void main() {
  setUp(() {
    _resetPage();
    resetGodotBinding();
  });

  tearDown(() {
    resetGodotBinding();
    _resetPage();
  });

  test('the web transport is resolved on the web, not the mock', () {
    // The binding used to be unreachable: nothing imported the web file, so
    // every web page silently got the mock and a permanent placeholder.
    expect(resolveGodotBinding(), isNot(isA<MockGodotBinding>()));
  });

  test('it is not live until the page installs the drain hook', () {
    final binding = resolveGodotBinding();
    expect(binding.isLive, isFalse,
        reason: 'no engine on the page yet, so Scene3D must draw a placeholder');

    _installDrainHook();
    expect(binding.isLive, isTrue,
        reason: 'a late-booting engine must light the surface up');
  });

  test('posted ops reach the page queue as one drainable batch', () {
    _installDrainHook();
    resolveGodotBinding().post([
      {'new': 'Node3D', 'def': 7},
      {'ref': 7, 'set': 'name', 'value': 'stage'},
    ]);

    // Dart pushes one JSON object per message; the glue hands Godot one JSON
    // array per drain. OpSink.gd parses exactly that and ignores anything else.
    final batch = _evalString('window.__elpianGodotDrain()');
    final decoded = jsonDecode(batch);
    expect(decoded, isA<List>());
    expect((decoded as List).single['ops'], hasLength(2));
    expect(decoded.single['ops'][0]['new'], 'Node3D');

    expect(_evalInt('window.__elpianGodotQueue.length'), 0,
        reason: 'a drained batch must not be delivered twice');
  });

  test('an awaited batch completes when the engine parks its reply', () async {
    _installDrainHook();
    final binding = resolveGodotBinding();

    final pending = binding.send([
      {'ref': 1, 'method': 'get_child_count', 'args': const []},
    ]);

    // Read the request id the way OpSink.gd does, then reply as its _reply()
    // does on the web transport.
    final batch = jsonDecode(_evalString('window.__elpianGodotDrain()')) as List;
    final req = batch.single['req'] as int;
    // `pending` carries a JSON *string*, exactly as the glue's
    // __elpianGodotReply writes it with JSON.stringify — parking a bare JS array
    // here would pass through jsonEncode and still be wrong.
    final parked = jsonEncode([
      {'req': req, 'values': [4]}
    ]);
    _eval('window.__elpianGodotReplies.pending = ${jsonEncode(parked)};'.toJS);

    expect(await pending, [4]);
  });

  test('a send with no reply resolves to nulls rather than hanging', () async {
    _installDrainHook();
    // No engine will ever answer. A caller must not be wedged by that — the
    // page may have the glue and no working export.
    final values = await resolveGodotBinding().send([
      {'ref': 1, 'method': 'get_child_count', 'args': const []},
    ]);
    expect(values, [null]);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
