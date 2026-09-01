import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'visual_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvas2d: alpha / gradient / clearRect / text', () async {
    final exec = CanvasAPIExecutor()
      ..gradients['grad'] = CanvasGradient(
        id: 'grad',
        colors: [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
        stops: const [0.0, 1.0],
        start: const Offset(0, 0),
        end: const Offset(300, 0),
      )
      ..addCommands([
        // opaque white background
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#ffffff'}),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 0,
          'y': 0,
          'width': 300,
          'height': 200
        }),
        // two overlapping 50%-alpha red squares: each must be a uniform 50%
        // over white (no compounding); the overlap is 50% over (50% over white)
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#ff0000'}),
        const CanvasCommand(
            type: CanvasCommandType.setGlobalAlpha, params: {'alpha': 0.5}),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 20,
          'y': 20,
          'width': 100,
          'height': 100
        }),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 80,
          'y': 20,
          'width': 100,
          'height': 100
        }),
        // gradient bar (full alpha again)
        const CanvasCommand(
            type: CanvasCommandType.setGlobalAlpha, params: {'alpha': 1.0}),
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'gradientId': 'grad'}),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 20,
          'y': 140,
          'width': 260,
          'height': 30
        }),
        // clearRect punches a transparent hole through everything
        const CanvasCommand(type: CanvasCommandType.clearRect, params: {
          'x': 130,
          'y': 40,
          'width': 40,
          'height': 40
        }),
        // text on top, solid color after a gradient (shader must be cleared)
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#003366'}),
        const CanvasCommand(type: CanvasCommandType.setFont, params: {
          'font': '20px sans-serif'
        }),
        const CanvasCommand(type: CanvasCommandType.fillText, params: {
          'text': 'Elpian',
          'x': 24,
          'y': 195
        }),
      ]);

    final file = await renderCanvasToPng(
      'canvas2d_scene',
      const Size(300, 200),
      (canvas, size) => exec.execute(canvas, size),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
  });

  test('canvas2d: shadows + font sizing (now-handled commands)', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#f5f5f5'}),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 0,
          'y': 0,
          'width': 320,
          'height': 220
        }),
        // Drop shadow on a filled rounded shape.
        const CanvasCommand(
            type: CanvasCommandType.setShadowColor,
            params: {'color': 'rgba(0,0,0,0.5)'}),
        const CanvasCommand(
            type: CanvasCommandType.setShadowBlur, params: {'blur': 16}),
        const CanvasCommand(
            type: CanvasCommandType.setShadowOffsetX, params: {'offset': 8}),
        const CanvasCommand(
            type: CanvasCommandType.setShadowOffsetY, params: {'offset': 10}),
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#e74c3c'}),
        const CanvasCommand(type: CanvasCommandType.fillCircle, params: {
          'x': 90,
          'y': 90,
          'radius': 45
        }),
        const CanvasCommand(type: CanvasCommandType.fillRect, params: {
          'x': 170,
          'y': 50,
          'width': 90,
          'height': 80
        }),
        // Large text via setFont (previously dropped -> defaulted to 10px).
        const CanvasCommand(
            type: CanvasCommandType.setShadowColor,
            params: {'color': 'rgba(0,0,0,0)'}), // clear shadow
        const CanvasCommand(
            type: CanvasCommandType.setShadowBlur, params: {'blur': 0}),
        const CanvasCommand(
            type: CanvasCommandType.setShadowOffsetX, params: {'offset': 0}),
        const CanvasCommand(
            type: CanvasCommandType.setShadowOffsetY, params: {'offset': 0}),
        const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#2c3e50'}),
        const CanvasCommand(type: CanvasCommandType.setFont, params: {
          'font': 'bold 36px sans-serif'
        }),
        const CanvasCommand(type: CanvasCommandType.fillText, params: {
          'text': 'Shadow',
          'x': 30,
          'y': 175
        }),
      ]);

    final file = await renderCanvasToPng(
      'canvas2d_shadows',
      const Size(320, 220),
      (canvas, size) => exec.execute(canvas, size),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
  });

}
