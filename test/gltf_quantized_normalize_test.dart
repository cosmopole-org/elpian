// Regression guard for the "giant building blocks the city" bug.
//
// `watch_tower.glb` (the City Wall / Watchtower model) stores POSITION as
// KHR_mesh_quantization-style normalized int16 (raw extents ±32767). An engine
// that reads those shorts raw renders the tower ~50,000 units tall: it pops in
// once the async load completes and fills the whole viewport. The loader must
// dequantize normalized integer accessors so rest bounds and rendered geometry
// agree, and `normalizeTransform` must then contain the model in its requested
// footprint.
//
// Also guards the unsupported-required-extension rejection: a model that
// REQUIRES e.g. EXT_meshopt_compression must fail loudly instead of decoding
// its compressed buffer views as garbage geometry.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/src/scene3d/gltf/gltf_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quantized (normalized int16) positions decode to sane rest bounds',
      () async {
    final bytes =
        File('test/assets/watch_tower.glb').readAsBytesSync();
    final model = await GltfBinaryLoader.parse(Uint8List.fromList(bytes));

    // Dequantized positions are in ±1 model space; with the node's dequant
    // scale the whole tower is a few units, NOT tens of thousands.
    final extentX = model.restMax.x - model.restMin.x;
    final extentY = model.restMax.y - model.restMin.y;
    final extentZ = model.restMax.z - model.restMin.z;
    for (final e in [extentX, extentY, extentZ]) {
      expect(e, greaterThan(0.01));
      expect(e, lessThan(100),
          reason: 'raw int16 read would put extents near 65534');
    }

    // The city scene's normalize request must contain the model: the scaled
    // footprint matches the requested cell, so the tower can never dwarf the
    // city again.
    const footprint = 4.8;
    const height = footprint / 0.75;
    final m = model.normalizeTransform(
        footprint: footprint, height: height, ground: true);
    final sx = m.m[0]; // uniform scale factor (column-major [0][0])
    final scaledXZ = (extentX > extentZ ? extentX : extentZ) * sx;
    final scaledY = extentY * sx;
    // Contain fit: both extents inside the footprint × height cell, with the
    // binding axis filling its target — never a tower dwarfing the city.
    expect(scaledXZ, lessThanOrEqualTo(footprint * 1.05));
    expect(scaledY, lessThanOrEqualTo(height * 1.05));
    final fill = [scaledXZ / footprint, scaledY / height]
        .reduce((a, b) => a > b ? a : b);
    expect(fill, closeTo(1.0, 0.05));
  });

  test('a model REQUIRING an undecodable extension is rejected loudly',
      () async {
    // Minimal GLB whose JSON requires EXT_meshopt_compression.
    final json = utf8.encode(jsonEncode({
      'asset': {'version': '2.0'},
      'extensionsRequired': ['EXT_meshopt_compression'],
      'extensionsUsed': ['EXT_meshopt_compression'],
    }));
    final pad = (4 - json.length % 4) % 4;
    final jsonChunk = [...json, ...List.filled(pad, 0x20)];
    final total = 12 + 8 + jsonChunk.length;
    final glb = BytesBuilder()
      ..add([0x67, 0x6C, 0x54, 0x46]) // 'glTF'
      ..add((ByteData(8)
            ..setUint32(0, 2, Endian.little)
            ..setUint32(4, total, Endian.little))
          .buffer
          .asUint8List())
      ..add((ByteData(8)
            ..setUint32(0, jsonChunk.length, Endian.little)
            ..setUint32(4, 0x4E4F534A, Endian.little)) // 'JSON'
          .buffer
          .asUint8List())
      ..add(jsonChunk);

    expect(
      () => GltfBinaryLoader.parse(glb.toBytes()),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('EXT_meshopt_compression'),
      )),
    );
  });
}
