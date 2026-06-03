import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

Canvas _recordingCanvas() =>
    Canvas(ui.PictureRecorder(), const Rect.fromLTWH(0, 0, 100, 100));

void main() {
  group('C — globalAlpha does not compound across draws', () {
    test('repeated fillRect with alpha 0.5 keeps alpha 0.5 (no compounding)',
        () {
      final exec = CanvasAPIExecutor()
        ..addCommands([
          const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#ff0000'},
          ),
          const CanvasCommand(
            type: CanvasCommandType.setGlobalAlpha,
            params: {'alpha': 0.5},
          ),
          const CanvasCommand(
            type: CanvasCommandType.fillRect,
            params: {'x': 0, 'y': 0, 'width': 10, 'height': 10},
          ),
          const CanvasCommand(
            type: CanvasCommandType.fillRect,
            params: {'x': 0, 'y': 0, 'width': 10, 'height': 10},
          ),
        ]);

      exec.execute(_recordingCanvas(), const Size(100, 100));

      // Base color is untouched; the live paint reflects exactly one alpha
      // application (0x80 ≈ 0.5), not 0.25 from compounding.
      expect(exec.currentState.fillColor, const Color(0xFFFF0000));
      expect(exec.currentState.fillPaint.color.alpha, closeTo(128, 1));
    });

    test('fully opaque path skips alpha adjustment and uses the base color',
        () {
      final exec = CanvasAPIExecutor()
        ..addCommands([
          const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#3366cc'},
          ),
          const CanvasCommand(
            type: CanvasCommandType.fillRect,
            params: {'x': 0, 'y': 0, 'width': 10, 'height': 10},
          ),
        ]);

      exec.execute(_recordingCanvas(), const Size(100, 100));
      expect(exec.currentState.fillPaint.color.toARGB32(), 0xFF3366CC);
    });
  });

  group('C — setFillStyle(color) clears a previously set gradient shader', () {
    test('solid color after gradient removes the shader', () {
      final exec = CanvasAPIExecutor()
        ..gradients['g'] = CanvasGradient(
          id: 'g',
          colors: [Colors.red, Colors.blue],
          stops: [0.0, 1.0],
          start: Offset.zero,
          end: const Offset(10, 0),
        )
        ..addCommands([
          const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'gradientId': 'g'},
          ),
          const CanvasCommand(
            type: CanvasCommandType.setFillStyle,
            params: {'color': '#00ff00'},
          ),
        ]);

      exec.execute(_recordingCanvas(), const Size(100, 100));
      expect(exec.currentState.fillPaint.shader, isNull);
      expect(exec.currentState.fillColor, const Color(0xFF00FF00));
    });
  });
}
