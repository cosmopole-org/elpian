// Runtime smoke test for the third-person shooter QuickJS program.
//
// Runs in the real app binary (so flutter_js's native QuickJS engine is
// available) and drives [tpsGameProgram] directly through [QuickJsVm]:
// it boots the program, then exercises every gameplay code path — the menu
// loop, starting a mission, the joystick / look / fire / reload / jump
// handlers, a few hundred frames of the full game loop, and the restart path.
//
// Every JS call is wrapped in a try/catch *inside* the runtime so thrown
// errors are surfaced (the widget normally swallows boot/eval errors), and all
// `println` output is captured — the game's own render()/gameTick() try/catch
// blocks report failures via `askHost('println', '... error: ...')`, so a clean
// log proves the frame loop ran without runtime errors.

// Import the native QuickJS implementation directly: this test is desktop-only
// (the conditional `quickjs_vm.dart` export resolves to the no-op stub under
// static analysis, which lacks the raw-eval `runCode` used below).
import 'package:elpian_ui/src/vm/quickjs_vm_native.dart';
import 'package:elpian_ui_example/examples/tps_game_program.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TPS QuickJS program boots and runs without runtime errors',
    (WidgetTester tester) async {
      final logs = <String>[];
      var renderCount = 0;
      String? intervalHandler;

      final vm = await QuickJsVm.fromCode('tps-smoke', tpsGameProgram);
      vm.setDefaultHostHandler((api, payload) {
        switch (api) {
          case 'println':
            logs.add(payload);
            break;
          case 'render':
            renderCount++;
            break;
          case 'setInterval':
            intervalHandler = payload;
            break;
        }
        return '{"type":"i16","data":{"value":0}}';
      });
      await vm.setGlobalHostData({
        'viewport': {'width': 1080, 'height': 1920},
      });

      // Boot the program (defines everything + runs newGame/render/setInterval).
      // Evaluated raw so a top-level throw surfaces in the result string.
      final bootRes = await vm.runCode(tpsGameProgram);
      expect(bootRes.contains('TypeError'), isFalse,
          reason: 'boot threw: $bootRes');
      expect(await vm.runCode('String(G===null)'), isNot('true'),
          reason: 'game state G is null after boot (newGame failed)');

      // Drive a JS expression with an in-runtime try/catch so thrown errors are
      // returned instead of being swallowed by evaluate().
      final driveErrors = <String>[];
      Future<void> step(String label, String expr) async {
        final r = await vm.runCode(
          "(function(){try{$expr;return 'OK';}"
          "catch(e){return 'ERR:'+e+' || '+((e&&e.stack)?e.stack:'');}})()",
        );
        if (r.startsWith('ERR:')) driveErrors.add('$label -> $r');
      }

      // Menu state ticks (camera orbit + fx + render).
      for (var i = 0; i < 10; i++) {
        await step('menu tick $i', 'gameTick()');
      }

      // Start the mission -> 'playing'.
      await step('onStart', 'onStart()');

      // Touch input: joystick, free-look, hold fire.
      await step('onMoveStart',
          'onMoveStart({localPosition:{x:120,y:18},pointerId:1})');
      await step(
          'onMove', 'onMove({localPosition:{x:118,y:30},pointerId:1})');
      await step('onLook', 'onLook({delta:{x:14,y:-6}})');
      await step('onFireDown', 'onFireDown()');

      // Run the full game loop for many frames (enemy spawning/AI/shooting,
      // bullets, pickups, fx, ambient city) while firing + steering, and fire
      // the remaining handlers along the way.
      for (var i = 0; i < 200; i++) {
        await step('play tick $i', 'gameTick()');
        if (i == 40) await step('onReload', 'onReload()');
        if (i == 60) await step('onJump', 'onJump()');
        if (i == 80) {
          await step('onMove2',
              'onMove({localPosition:{x:12,y:120},pointerId:1})');
        }
        if (i == 120) await step('onMoveEnd', 'onMoveEnd({pointerId:1})');
        if (i == 150) await step('onFireUp', 'onFireUp()');
      }

      // Restart path (back to a fresh game) + a few more frames.
      await step('onRestart', 'onRestart()');
      for (var i = 0; i < 30; i++) {
        await step('restart tick $i', 'gameTick()');
      }

      await vm.dispose();

      // The program must have booted, rendered, and registered its loop.
      expect(logs.any((l) => l.contains('booted')), isTrue,
          reason: 'boot println missing; logs=$logs');
      expect(renderCount, greaterThan(0), reason: 'render() was never called');
      expect(intervalHandler, isNotNull,
          reason: 'setInterval game loop was not registered');

      // No JS-reported errors (render/tick try/catch funnel here) ...
      final jsErrors =
          logs.where((l) => l.toLowerCase().contains('error')).toList();
      expect(jsErrors, isEmpty,
          reason: 'JS reported errors via println: $jsErrors');
      // ... and no thrown errors from any driven call.
      expect(driveErrors, isEmpty,
          reason:
              'Runtime errors while driving the game:\n${driveErrors.join('\n')}');
    },
  );
}
