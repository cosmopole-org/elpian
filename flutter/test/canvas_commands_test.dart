// Canvas commands the Flutter painter used to drop: images (all drawImage
// forms), polygons, transform/setTransform/resetTransform, patterns,
// getImageData/putImageData/createImageData, arcTo, addColorStop, line dashes,
// text alignment / baselines and custom painters. Checked on real pixels.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

CanvasCommand cmd(CanvasCommandType type,
        [Map<String, dynamic> p = const {}]) =>
    CanvasCommand(type: type, params: p);

/// Rendered pixels of [exec] on a [w]×[h] canvas.
class Pixels {
  Pixels(this.bytes, this.width);
  final Uint8List bytes;
  final int width;

  /// ARGB at (x, y).
  int at(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i + 3] << 24) |
        (bytes[i] << 16) |
        (bytes[i + 1] << 8) |
        bytes[i + 2];
  }
}

Future<Pixels> render(CanvasAPIExecutor exec, {int w = 40, int h = 40}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  exec.execute(canvas, Size(w.toDouble(), h.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return Pixels(data!.buffer.asUint8List(), w);
}

/// A [w]×[h] image: left half red, right half blue.
Future<ui.Image> twoToneImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h.toDouble()),
      Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
      Paint()..color = const Color(0xFF0000FF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

const red = 0xFFFF0000;
const green = 0xFF00FF00;
const blue = 0xFF0000FF;
const clear = 0x00000000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fillPolygon / strokePolygon accept every point format', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.fillPolygon, {
          'points': [
            [0, 0],
            [20, 0],
            [0, 20],
          ]
        }),
        cmd(CanvasCommandType.setFillStyle, {'color': '#0000ff'}),
        cmd(CanvasCommandType.fillPolygon, {
          'points': [20, 20, 40, 20, 40, 40, 20, 40]
        }),
        cmd(CanvasCommandType.setStrokeStyle, {'color': '#00ff00'}),
        cmd(CanvasCommandType.setLineWidth, {'width': 2}),
        cmd(CanvasCommandType.strokePolygon, {
          'points': [
            {'x': 2, 'y': 30},
            {'x': 15, 'y': 30},
          ],
          'closed': false,
        }),
      ]);
    final px = await render(exec);
    expect(px.at(3, 3), red);
    expect(px.at(18, 18), clear); // outside the triangle
    expect(px.at(30, 30), blue);
    expect(px.at(8, 30), green);
  });

  test('drawImage: 3-, 5- and 9-argument forms, and drawImageRect', () async {
    final image = await twoToneImage(10, 10);
    final exec = CanvasAPIExecutor()
      ..images['tile'] = image
      ..addCommands([
        // 3-arg: natural size at (0, 0).
        cmd(CanvasCommandType.drawImage, {'imageId': 'tile', 'x': 0, 'y': 0}),
        // 5-arg: scaled to 20×10 at (0, 20).
        cmd(CanvasCommandType.drawImage, {
          'src': 'tile',
          'x': 0,
          'y': 20,
          'width': 20,
          'height': 10,
        }),
        // 9-arg: only the blue half, stretched over (20, 0, 20, 10).
        cmd(CanvasCommandType.drawImage, {
          'src': 'tile',
          'sx': 5,
          'sy': 0,
          'sw': 5,
          'sh': 10,
          'dx': 20,
          'dy': 0,
          'dw': 20,
          'dh': 10,
        }),
        cmd(CanvasCommandType.drawImageRect, {
          'src': 'tile',
          'sx': 0,
          'sy': 0,
          'sw': 5,
          'sh': 10,
          'dx': 30,
          'dy': 30,
          'dw': 10,
          'dh': 10,
        }),
      ]);
    final px = await render(exec);
    expect(px.at(2, 5), red);
    expect(px.at(8, 5), blue);
    expect(px.at(12, 5), clear); // the 3-arg draw is only 10px wide
    expect(px.at(4, 25), red);
    expect(px.at(16, 25), blue); // 5-arg form scaled to 20px wide
    expect(px.at(22, 5), blue);
    expect(px.at(38, 5), blue); // 9-arg form: blue half only
    expect(px.at(35, 35), red);
    image.dispose();
  });

  test('drawImage from the image cache repaints once the image arrives',
      () async {
    final cache = CanvasImageCache();
    final exec = CanvasAPIExecutor(imageCache: cache)
      ..addCommand(
          cmd(CanvasCommandType.drawImage, {'src': 'sprite', 'x': 0, 'y': 0}));
    var px = await render(exec);
    expect(px.at(2, 2), clear);

    var notified = false;
    cache.addListener(() => notified = true);
    cache.put('sprite', await twoToneImage(10, 10));
    await Future<void>.delayed(Duration.zero);
    expect(notified, isTrue);
    px = await render(exec);
    expect(px.at(2, 2), red);
    cache.clear();
  });

  test('transform, setTransform and resetTransform', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.translate, {'x': 100, 'y': 100}),
        // Replaces the translation: a 2× scale + (10, 0) offset.
        cmd(CanvasCommandType.setTransform,
            {'a': 2, 'b': 0, 'c': 0, 'd': 2, 'e': 10, 'f': 0}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 5, 'height': 5}), // → (10,0)-(20,10)
        // Multiplies: + (0, 5) in the scaled space → +10px down.
        cmd(CanvasCommandType.transform,
            {'a': 1, 'b': 0, 'c': 0, 'd': 1, 'e': 0, 'f': 5}),
        cmd(CanvasCommandType.setFillStyle, {'color': '#0000ff'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 5, 'height': 5}), // → (10,10)-(20,20)
        cmd(CanvasCommandType.resetTransform),
        cmd(CanvasCommandType.setFillStyle, {'color': '#00ff00'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 30, 'width': 5, 'height': 5}),
      ]);
    final px = await render(exec);
    expect(px.at(15, 5), red);
    expect(px.at(5, 5), clear);
    expect(px.at(15, 15), blue);
    expect(px.at(2, 32), green);
    expect(exec.currentState.transform.isIdentity(), isTrue);
  });

  test('createPattern tiles an image as the fill style', () async {
    final exec = CanvasAPIExecutor()
      ..images['tile'] = await twoToneImage(10, 10)
      ..addCommands([
        cmd(CanvasCommandType.createPattern,
            {'id': 'p', 'imageId': 'tile', 'repetition': 'repeat-x'}),
        cmd(CanvasCommandType.setFillStyle, {'patternId': 'p'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 40, 'height': 40}),
      ]);
    final px = await render(exec);
    expect(px.at(2, 2), red);
    expect(px.at(7, 2), blue);
    expect(px.at(12, 2), red); // repeated horizontally
    expect(px.at(2, 25), clear); // not vertically (repeat-x)
  });

  test('putImageData writes raw pixels, ignoring the transform', () async {
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 255, //
      0, 0, 255, 255, 0, 0, 0, 0,
    ]);
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ffffff'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 40, 'height': 40}),
        cmd(CanvasCommandType.scale, {'x': 3, 'y': 3}),
        cmd(CanvasCommandType.putImageData, {
          'id': 'px',
          'x': 4,
          'y': 6,
          'width': 2,
          'height': 2,
          'data': rgba.toList(),
        }),
      ]);
    final px = await render(exec);
    expect(px.at(4, 6), red);
    expect(px.at(5, 6), green);
    expect(px.at(4, 7), blue);
    // A transparent pixel replaces (does not blend with) the white below.
    expect(px.at(5, 7), clear);
    expect(px.at(6, 6), 0xFFFFFFFF);
    expect(await exec.readImageData('px'), rgba);
  });

  test('createImageData is transparent black of the given size', () async {
    final exec = CanvasAPIExecutor()
      ..addCommand(cmd(CanvasCommandType.createImageData,
          {'id': 'blank', 'width': 3, 'height': 2}));
    await render(exec);
    final data = exec.imageData['blank']!;
    expect(data.width, 3);
    expect(data.height, 2);
    expect(await exec.readImageData('blank'), Uint8List(3 * 2 * 4));
  });

  test('getImageData snapshots what was drawn; putImageData copies it',
      () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 5, 'height': 5}),
        cmd(CanvasCommandType.getImageData,
            {'id': 'snap', 'x': 0, 'y': 0, 'width': 10, 'height': 10}),
        cmd(CanvasCommandType.setFillStyle, {'color': '#0000ff'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 5, 'height': 5}),
        cmd(CanvasCommandType.putImageData, {'id': 'snap', 'x': 20, 'y': 20}),
      ]);
    final px = await render(exec);
    expect(px.at(2, 2), blue); // drawn after the snapshot
    expect(px.at(22, 22), red); // the snapshot, copied
    expect(px.at(27, 27), clear);
    final bytes = (await exec.readImageData('snap'))!;
    expect(bytes.sublist(0, 4), [255, 0, 0, 255]);
  });

  test('arcTo rounds a corner tangent to both lines', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.beginPath),
        cmd(CanvasCommandType.moveTo, {'x': 0, 'y': 0}),
        cmd(CanvasCommandType.arcTo,
            {'x1': 30, 'y1': 0, 'x2': 30, 'y2': 30, 'radius': 20}),
        cmd(CanvasCommandType.lineTo, {'x': 30, 'y': 30}),
        cmd(CanvasCommandType.lineTo, {'x': 0, 'y': 30}),
        cmd(CanvasCommandType.closePath),
        cmd(CanvasCommandType.fill),
      ]);
    final px = await render(exec);
    expect(px.at(5, 5), red);
    expect(px.at(15, 15), red);
    // The square's top-right corner is cut off by the arc.
    expect(px.at(29, 1), clear);
    expect(px.at(28, 25), red);
  });

  test('addColorStop builds the gradient used by the fill style', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.createLinearGradient,
            {'id': 'g', 'x0': 0, 'y0': 0, 'x1': 40, 'y1': 0, 'colors': []}),
        cmd(CanvasCommandType.setFillStyle, {'gradientId': 'g'}),
        // Stops added after the style is set still apply (live gradient).
        cmd(CanvasCommandType.addColorStop,
            {'gradientId': 'g', 'offset': 0, 'color': '#ff0000'}),
        cmd(CanvasCommandType.addColorStop,
            {'gradientId': 'g', 'offset': 0.5, 'color': '#ff0000'}),
        cmd(CanvasCommandType.addColorStop,
            {'gradientId': 'g', 'offset': 0.5, 'color': '#0000ff'}),
        cmd(CanvasCommandType.addColorStop,
            {'gradientId': 'g', 'offset': 1, 'color': '#0000ff'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 40, 'height': 10}),
      ]);
    final px = await render(exec);
    expect(px.at(5, 5), red);
    expect(px.at(35, 5), blue);
    // Replaying (a repaint) does not accumulate the stops twice.
    await render(exec);
    expect(exec.gradients['g']!.stops, [0.0, 0.5, 0.5, 1.0]);
  });

  test('setLineDash leaves gaps; lineDashOffset shifts them', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setStrokeStyle, {'color': '#00ff00'}),
        cmd(CanvasCommandType.setLineWidth, {'width': 4}),
        cmd(CanvasCommandType.setLineDash, {
          'segments': [10, 10]
        }),
        cmd(CanvasCommandType.beginPath),
        cmd(CanvasCommandType.moveTo, {'x': 0, 'y': 10}),
        cmd(CanvasCommandType.lineTo, {'x': 40, 'y': 10}),
        cmd(CanvasCommandType.stroke),
        cmd(CanvasCommandType.setLineDashOffset, {'offset': 10}),
        cmd(CanvasCommandType.beginPath),
        cmd(CanvasCommandType.moveTo, {'x': 0, 'y': 30}),
        cmd(CanvasCommandType.lineTo, {'x': 40, 'y': 30}),
        cmd(CanvasCommandType.stroke),
      ]);
    final px = await render(exec);
    expect(px.at(5, 10), green);
    expect(px.at(15, 10), clear);
    expect(px.at(25, 10), green);
    expect(px.at(5, 30), clear);
    expect(px.at(15, 30), green);
  });

  test('arc honours counterclockwise and full turns', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.beginPath),
        cmd(CanvasCommandType.moveTo, {'x': 20, 'y': 20}),
        // Counter-clockwise from 0 to π/2 is the long way round: 3/4 circle.
        cmd(CanvasCommandType.arc, {
          'x': 20,
          'y': 20,
          'radius': 15,
          'startAngle': 0,
          'endAngle': 1.5707963,
          'counterclockwise': true,
        }),
        cmd(CanvasCommandType.closePath),
        cmd(CanvasCommandType.fill),
      ]);
    final px = await render(exec);
    expect(px.at(10, 10), red); // top-left quadrant: inside
    expect(px.at(28, 28), clear); // bottom-right quadrant: the missing quarter
  });

  test('textAlign / textBaseline position the text anchor', () async {
    Future<Rect> inkOf(String align, String baseline) async {
      final exec = CanvasAPIExecutor()
        ..addCommands([
          cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
          cmd(CanvasCommandType.setFont, {'font': '20px sans-serif'}),
          cmd(CanvasCommandType.setTextAlign, {'align': align}),
          cmd(CanvasCommandType.setTextBaseline, {'baseline': baseline}),
          cmd(CanvasCommandType.fillText, {'text': 'MM', 'x': 50, 'y': 50}),
        ]);
      final px = await render(exec, w: 100, h: 100);
      var l = 100, t = 100, r = -1, b = -1;
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          if ((px.at(x, y) >> 24) > 0x80) {
            if (x < l) l = x;
            if (x > r) r = x;
            if (y < t) t = y;
            if (y > b) b = y;
          }
        }
      }
      return Rect.fromLTRB(
          l.toDouble(), t.toDouble(), r.toDouble(), b.toDouble());
    }

    final start = await inkOf('start', 'top');
    expect(start.left, greaterThanOrEqualTo(49));
    expect(start.top, greaterThanOrEqualTo(49));
    final end = await inkOf('right', 'bottom');
    expect(end.right, lessThanOrEqualTo(51));
    expect(end.bottom, lessThanOrEqualTo(51));
    final centred = await inkOf('center', 'alphabetic');
    expect(centred.left, lessThan(50));
    expect(centred.right, greaterThan(50));
    // Glyphs stand on the baseline: their ink is mostly above y = 50 (the
    // test font's boxes reach only a descent's depth below it).
    expect(centred.top, lessThan(40));
    expect(centred.bottom, lessThan(56));
  });

  test('custom commands run registered painters', () async {
    CanvasAPIExecutor.registerPainter('dot', (canvas, size, params) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10),
          Paint()..color = const Color(0xFF00FF00));
    });
    final exec = CanvasAPIExecutor()
      ..addCommand(cmd(CanvasCommandType.custom, {'name': 'dot'}));
    final px = await render(exec);
    expect(px.at(5, 5), green);
    CanvasAPIExecutor.unregisterPainter('dot');
  });

  test('a repaint starts from a fresh state', () async {
    final exec = CanvasAPIExecutor()
      ..addCommands([
        cmd(CanvasCommandType.translate, {'x': 10, 'y': 0}),
        cmd(CanvasCommandType.setFillStyle, {'color': '#ff0000'}),
        cmd(CanvasCommandType.fillRect,
            {'x': 0, 'y': 0, 'width': 5, 'height': 5}),
      ]);
    await render(exec);
    final px = await render(exec);
    // Not translated twice.
    expect(px.at(12, 2), red);
    expect(px.at(22, 2), clear);
  });
}
