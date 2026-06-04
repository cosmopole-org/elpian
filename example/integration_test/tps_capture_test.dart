// Captures a real in-game frame to a PNG for visual inspection of the city.
//
// Boots the actual QuickJS program, enters the playing state, grabs the scene
// JSON it emits (the spliced staticWorld + dynamic world), renders it through
// the real GameSceneWidget at a fixed size and writes the result to
// /tmp/tps_city.png. Streamed glTF characters appear as placeholders (no
// network wait); the point is to judge the static city's composition.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/vm/quickjs_vm_native.dart';
import 'package:elpian_ui_example/examples/tps_game_program.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Map<String, dynamic>? _findScene(dynamic node) {
  if (node is Map) {
    if (node['type'] == 'GameScene') {
      final props = node['props'];
      if (props is Map && props['scene'] is Map) {
        return (props['scene'] as Map).cast<String, dynamic>();
      }
    }
    for (final v in node.values) {
      final r = _findScene(v);
      if (r != null) return r;
    }
  } else if (node is List) {
    for (final v in node) {
      final r = _findScene(v);
      if (r != null) return r;
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture a TPS city frame to PNG', (tester) async {
    String? lastRender;
    final vm = await QuickJsVm.fromCode('tps-capture', tpsGameProgram);
    vm.setDefaultHostHandler((api, payload) {
      if (api == 'render') lastRender = payload;
      return '{"type":"i16","data":{"value":0}}';
    });
    await vm.setGlobalHostData({
      'viewport': {'width': 900, 'height': 1600},
    });
    await vm.run();
    await vm.runCode('onStart()');
    for (var i = 0; i < 24; i++) {
      await vm.runCode('gameTick()');
    }

    expect(lastRender, isNotNull);
    final tree = jsonDecode(lastRender!);
    final scene = _findScene(tree);
    expect(scene, isNotNull, reason: 'GameScene node with scene not found');
    expect(scene!['staticWorld'], isA<List>(),
        reason: 'scene should carry a staticWorld array');
    await vm.dispose();

    Future<int> capture(String path, Map<String, dynamic> s) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Container(
          color: const Color(0xFF05070D),
          alignment: Alignment.center,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 900,
              height: 1600,
              child: GameSceneWidget(
                sceneMap: s,
                interactive: false,
                autoStart: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = bytes!.buffer.asUint8List();
      await File(path).writeAsBytes(png);
      // ignore: avoid_print
      print('WROTE $path (${png.length} bytes)');
      return png.length;
    }

    final outDir = Directory.systemTemp.path;

    // 1) The actual in-game (third-person) view.
    final n1 = await capture('$outDir/tps_city.png', scene);

    // 2) An elevated establishing shot of the whole block (camera overridden to
    //    look at the plaza), to check the skyline/composition for artifacts.
    final overhead = <String, dynamic>{
      ...scene,
      'world': [
        for (final item in scene['world'] as List)
          if (item is Map && item['type'] == 'camera')
            _lookAtCamera(const _V(30, 26, 34))
          else
            item,
      ],
    };
    final n2 = await capture('$outDir/tps_city_overhead.png', overhead);

    expect(n1, greaterThan(1000));
    expect(n2, greaterThan(1000));
  });
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
}

Map<String, dynamic> _lookAtCamera(_V p) {
  final len = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z);
  final dx = -p.x / len, dy = -p.y / len, dz = -p.z / len;
  final rx = math.asin(dy) * 180 / math.pi; // pitch
  final ry = math.atan2(dx, -dz) * 180 / math.pi; // yaw
  return {
    'type': 'camera',
    'camera_type': 'Perspective',
    'fov': 58,
    'near': 0.1,
    'far': 260,
    'transform': {
      'position': {'x': p.x, 'y': p.y, 'z': p.z},
      'rotation': {'x': rx, 'y': ry, 'z': 0},
    },
  };
}
