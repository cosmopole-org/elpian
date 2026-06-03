import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Output directory for rendered PNGs (git-ignored build artifacts).
final Directory outDir = Directory('build/visual')..createSync(recursive: true);

/// Rasterize a [draw] callback to a PNG on disk and return the file.
Future<File> renderCanvasToPng(
  String name,
  Size size,
  void Function(Canvas canvas, Size size) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.width, size.height),
  );
  draw(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${outDir.path}/$name.png');
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  picture.dispose();
  image.dispose();
  return file;
}
