/// glTF 2.0 / GLB binary loader.
///
/// Parses a `.glb` container (or a self-contained `.gltf` JSON with embedded
/// base64 buffers) into a render-ready [GltfModel]: mesh primitives with
/// skinning attributes, the node hierarchy, skins with inverse-bind matrices,
/// materials, keyframe animations, and decoded base-colour textures.
///
/// Validated against the Khronos sample assets (`CesiumMan`, `RiggedFigure`,
/// `Fox`). Matrices are read directly in column-major order to match the
/// engine's [Mat4] storage.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core.dart';
import 'gltf_model.dart';

class GltfLoadException implements Exception {
  final String message;
  GltfLoadException(this.message);
  @override
  String toString() => 'GltfLoadException: $message';
}

class GltfBinaryLoader {
  static const int _glbMagic = 0x46546C67; // "glTF"
  static const int _chunkJson = 0x4E4F534A; // "JSON"
  static const int _chunkBin = 0x004E4942; // "BIN\0"

  /// Parse [bytes] into a [GltfModel], decoding embedded textures.
  static Future<GltfModel> parse(Uint8List bytes) async {
    final (json, binChunk) = _split(bytes);
    final buffers = _resolveBuffers(json, binChunk);
    final accessors = (json['accessors'] as List?) ?? const [];
    final bufferViews = (json['bufferViews'] as List?) ?? const [];

    Float32List readFloats(int accessorIndex) =>
        _readAccessorFloats(accessorIndex, accessors, bufferViews, buffers);
    Int32List readInts(int accessorIndex) =>
        _readAccessorInts(accessorIndex, accessors, bufferViews, buffers);

    // ── Materials ──────────────────────────────────────────────────────
    final materials = <GltfMaterial>[];
    for (final m in (json['materials'] as List? ?? const [])) {
      materials.add(_parseMaterial(m as Map));
    }

    // ── Meshes / primitives ────────────────────────────────────────────
    final meshes = <List<GltfPrimitive>>[];
    for (final mesh in (json['meshes'] as List? ?? const [])) {
      final prims = <GltfPrimitive>[];
      for (final prim in ((mesh as Map)['primitives'] as List? ?? const [])) {
        final p = prim as Map;
        final mode = (p['mode'] as num?)?.toInt() ?? 4;
        if (mode != 4) continue; // only triangle lists
        final attrs = p['attributes'] as Map;
        final posIdx = (attrs['POSITION'] as num).toInt();
        final positions = readFloats(posIdx);
        final vertexCount = positions.length ~/ 3;

        Float32List? normals;
        if (attrs['NORMAL'] != null) {
          normals = readFloats((attrs['NORMAL'] as num).toInt());
        }
        Float32List? uvs;
        if (attrs['TEXCOORD_0'] != null) {
          uvs = readFloats((attrs['TEXCOORD_0'] as num).toInt());
        }
        Uint16List? joints;
        Float32List? weights;
        if (attrs['JOINTS_0'] != null && attrs['WEIGHTS_0'] != null) {
          final ji = readInts((attrs['JOINTS_0'] as num).toInt());
          joints = Uint16List(ji.length);
          for (var i = 0; i < ji.length; i++) {
            joints[i] = ji[i] & 0xFFFF;
          }
          weights = readFloats((attrs['WEIGHTS_0'] as num).toInt());
        }
        Int32List? indices;
        if (p['indices'] != null) {
          indices = readInts((p['indices'] as num).toInt());
        }

        prims.add(GltfPrimitive(
          positions: positions,
          vertexCount: vertexCount,
          normals: normals,
          uvs: uvs,
          joints: joints,
          weights: weights,
          indices: indices,
          material: (p['material'] as num?)?.toInt(),
        ));
      }
      meshes.add(prims);
    }

    // ── Nodes ──────────────────────────────────────────────────────────
    final nodeDefs = <GltfNodeDef>[];
    for (final node in (json['nodes'] as List? ?? const [])) {
      nodeDefs.add(_parseNode(node as Map));
    }

    // ── Scene roots ────────────────────────────────────────────────────
    final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
    final scenes = json['scenes'] as List? ?? const [];
    final rootNodes = <int>[];
    if (sceneIndex < scenes.length) {
      for (final r in ((scenes[sceneIndex] as Map)['nodes'] as List? ?? const [])) {
        rootNodes.add((r as num).toInt());
      }
    } else if (nodeDefs.isNotEmpty) {
      // No scene declared: treat nodes without a parent as roots.
      final hasParent = List<bool>.filled(nodeDefs.length, false);
      for (final n in nodeDefs) {
        for (final c in n.children) {
          if (c < hasParent.length) hasParent[c] = true;
        }
      }
      for (var i = 0; i < nodeDefs.length; i++) {
        if (!hasParent[i]) rootNodes.add(i);
      }
    }

    // ── Skins ──────────────────────────────────────────────────────────
    final skins = <GltfSkin>[];
    for (final skin in (json['skins'] as List? ?? const [])) {
      final s = skin as Map;
      final joints = <int>[
        for (final j in (s['joints'] as List? ?? const [])) (j as num).toInt(),
      ];
      final ibm = <Mat4>[];
      if (s['inverseBindMatrices'] != null) {
        final flat = readFloats((s['inverseBindMatrices'] as num).toInt());
        for (var k = 0; k + 16 <= flat.length; k += 16) {
          ibm.add(Mat4.fromColumnMajor(flat.sublist(k, k + 16)));
        }
      } else {
        for (var k = 0; k < joints.length; k++) {
          ibm.add(Mat4.identity());
        }
      }
      skins.add(GltfSkin(joints, ibm));
    }

    // ── Animations ─────────────────────────────────────────────────────
    final animations = <GltfAnimation>[];
    final animationByName = <String, int>{};
    final animList = json['animations'] as List? ?? const [];
    for (var ai = 0; ai < animList.length; ai++) {
      final a = animList[ai] as Map;
      final samplers = <GltfSampler>[];
      for (final sm in (a['samplers'] as List? ?? const [])) {
        final s = sm as Map;
        final times = readFloats((s['input'] as num).toInt());
        final outIdx = (s['output'] as num).toInt();
        final values = readFloats(outIdx);
        final comps = _accessorComponentCount(accessors[outIdx] as Map);
        samplers.add(GltfSampler(
          times,
          values,
          comps,
          (s['interpolation'] as String?) ?? 'LINEAR',
        ));
      }
      final channels = <GltfChannel>[];
      var duration = 0.0;
      for (final ch in (a['channels'] as List? ?? const [])) {
        final c = ch as Map;
        final target = c['target'] as Map;
        final node = (target['node'] as num?)?.toInt();
        final path = target['path'] as String?;
        final samplerIdx = (c['sampler'] as num).toInt();
        if (node == null || path == null) continue;
        if (node >= 0 && node < nodeDefs.length) {
          nodeDefs[node].animated = true;
        }
        channels.add(GltfChannel(node, path, samplerIdx));
        final st = samplers[samplerIdx].times;
        if (st.isNotEmpty) duration = duration < st.last ? st.last : duration;
      }
      final name = (a['name'] as String?) ?? 'anim$ai';
      animations.add(GltfAnimation(name, channels, samplers, duration));
      animationByName[name] = ai;
    }

    // ── Textures (decode base-colour images) ───────────────────────────
    final textures = await _decodeTextures(json, bufferViews, buffers);

    // ── Rest-pose bounds (cheap sample for placeholder sizing) ─────────
    final bounds = _estimateBounds(nodeDefs, rootNodes, meshes, skins);

    return GltfModel(
      nodes: nodeDefs,
      rootNodes: rootNodes,
      meshes: meshes,
      materials: materials,
      skins: skins,
      animations: animations,
      textures: textures,
      animationByName: animationByName,
      restCenter: bounds.$1,
      restRadius: bounds.$2,
      restMin: bounds.$3,
      restMax: bounds.$4,
    );
  }

  // ── GLB container ────────────────────────────────────────────────────

  static (Map<String, dynamic>, Uint8List?) _split(Uint8List bytes) {
    if (bytes.length >= 12) {
      final bd = ByteData.sublistView(bytes);
      final magic = bd.getUint32(0, Endian.little);
      if (magic == _glbMagic) {
        final length = bd.getUint32(8, Endian.little);
        var off = 12;
        Map<String, dynamic>? json;
        Uint8List? bin;
        while (off + 8 <= length && off + 8 <= bytes.length) {
          final clen = bd.getUint32(off, Endian.little);
          final ctype = bd.getUint32(off + 4, Endian.little);
          off += 8;
          final chunk = Uint8List.sublistView(bytes, off, off + clen);
          if (ctype == _chunkJson) {
            json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
          } else if (ctype == _chunkBin) {
            bin = chunk;
          }
          off += clen;
        }
        if (json == null) throw GltfLoadException('GLB missing JSON chunk');
        return (json, bin);
      }
    }
    // Plain .gltf JSON.
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return (json, null);
  }

  static List<Uint8List> _resolveBuffers(
      Map<String, dynamic> json, Uint8List? binChunk) {
    final out = <Uint8List>[];
    final buffers = json['buffers'] as List? ?? const [];
    for (var i = 0; i < buffers.length; i++) {
      final b = buffers[i] as Map;
      final uri = b['uri'] as String?;
      if (uri == null) {
        // GLB: buffer 0 is the BIN chunk.
        out.add(binChunk ?? Uint8List(0));
      } else if (uri.startsWith('data:')) {
        final comma = uri.indexOf(',');
        out.add(base64Decode(uri.substring(comma + 1)));
      } else {
        // External .bin files are not supported (use .glb instead).
        out.add(Uint8List(0));
      }
    }
    if (out.isEmpty && binChunk != null) out.add(binChunk);
    return out;
  }

  // ── Accessors ──────────────────────────────────────────────────────────

  static const Map<int, int> _compSize = {
    5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4,
  };

  static int _accessorComponentCount(Map a) {
    switch (a['type'] as String) {
      case 'SCALAR':
        return 1;
      case 'VEC2':
        return 2;
      case 'VEC3':
        return 3;
      case 'VEC4':
        return 4;
      case 'MAT2':
        return 4;
      case 'MAT3':
        return 9;
      case 'MAT4':
        return 16;
      default:
        return 1;
    }
  }

  static Float32List _readAccessorFloats(
    int index,
    List accessors,
    List bufferViews,
    List<Uint8List> buffers,
  ) {
    final a = accessors[index] as Map;
    final compType = (a['componentType'] as num).toInt();
    final count = (a['count'] as num).toInt();
    final ncomp = _accessorComponentCount(a);
    final normalized = a['normalized'] as bool? ?? false;
    final out = Float32List(count * ncomp);

    final bvIndex = (a['bufferView'] as num?)?.toInt();
    if (bvIndex == null) return out; // sparse-only / empty
    final bv = bufferViews[bvIndex] as Map;
    final buffer = buffers[(bv['buffer'] as num).toInt()];
    final bd = ByteData.sublistView(buffer);
    final compSize = _compSize[compType]!;
    final byteOffset =
        ((bv['byteOffset'] as num?)?.toInt() ?? 0) + ((a['byteOffset'] as num?)?.toInt() ?? 0);
    final stride = (bv['byteStride'] as num?)?.toInt() ?? (compSize * ncomp);

    for (var i = 0; i < count; i++) {
      final base = byteOffset + i * stride;
      for (var c = 0; c < ncomp; c++) {
        final o = base + c * compSize;
        double v;
        switch (compType) {
          case 5126:
            v = bd.getFloat32(o, Endian.little);
            break;
          case 5121:
            final raw = bd.getUint8(o);
            v = normalized ? raw / 255.0 : raw.toDouble();
            break;
          case 5123:
            final raw = bd.getUint16(o, Endian.little);
            v = normalized ? raw / 65535.0 : raw.toDouble();
            break;
          case 5120:
            final raw = bd.getInt8(o);
            v = normalized ? (raw / 127.0).clamp(-1.0, 1.0) : raw.toDouble();
            break;
          case 5122:
            final raw = bd.getInt16(o, Endian.little);
            v = normalized ? (raw / 32767.0).clamp(-1.0, 1.0) : raw.toDouble();
            break;
          case 5125:
            v = bd.getUint32(o, Endian.little).toDouble();
            break;
          default:
            v = 0;
        }
        out[i * ncomp + c] = v;
      }
    }
    return out;
  }

  static Int32List _readAccessorInts(
    int index,
    List accessors,
    List bufferViews,
    List<Uint8List> buffers,
  ) {
    final a = accessors[index] as Map;
    final compType = (a['componentType'] as num).toInt();
    final count = (a['count'] as num).toInt();
    final ncomp = _accessorComponentCount(a);
    final out = Int32List(count * ncomp);

    final bvIndex = (a['bufferView'] as num?)?.toInt();
    if (bvIndex == null) return out;
    final bv = bufferViews[bvIndex] as Map;
    final buffer = buffers[(bv['buffer'] as num).toInt()];
    final bd = ByteData.sublistView(buffer);
    final compSize = _compSize[compType]!;
    final byteOffset =
        ((bv['byteOffset'] as num?)?.toInt() ?? 0) + ((a['byteOffset'] as num?)?.toInt() ?? 0);
    final stride = (bv['byteStride'] as num?)?.toInt() ?? (compSize * ncomp);

    for (var i = 0; i < count; i++) {
      final base = byteOffset + i * stride;
      for (var c = 0; c < ncomp; c++) {
        final o = base + c * compSize;
        int v;
        switch (compType) {
          case 5121:
            v = bd.getUint8(o);
            break;
          case 5123:
            v = bd.getUint16(o, Endian.little);
            break;
          case 5125:
            v = bd.getUint32(o, Endian.little);
            break;
          case 5120:
            v = bd.getInt8(o);
            break;
          case 5122:
            v = bd.getInt16(o, Endian.little);
            break;
          default:
            v = 0;
        }
        out[i * ncomp + c] = v;
      }
    }
    return out;
  }

  // ── Materials / nodes ──────────────────────────────────────────────────

  static GltfMaterial _parseMaterial(Map m) {
    final pbr = m['pbrMetallicRoughness'] as Map? ?? const {};
    final bcf = pbr['baseColorFactor'] as List?;
    final ef = m['emissiveFactor'] as List?;
    final bct = pbr['baseColorTexture'] as Map?;
    final alphaMode = (m['alphaMode'] as String?) ?? 'OPAQUE';
    return GltfMaterial(
      baseColor: bcf != null && bcf.length >= 3
          ? Vec3((bcf[0] as num).toDouble(), (bcf[1] as num).toDouble(),
              (bcf[2] as num).toDouble())
          : const Vec3(1, 1, 1),
      alpha: bcf != null && bcf.length >= 4 ? (bcf[3] as num).toDouble() : 1.0,
      metallic: (pbr['metallicFactor'] as num?)?.toDouble() ?? 1.0,
      roughness: (pbr['roughnessFactor'] as num?)?.toDouble() ?? 1.0,
      emissive: ef != null && ef.length >= 3
          ? Vec3((ef[0] as num).toDouble(), (ef[1] as num).toDouble(),
              (ef[2] as num).toDouble())
          : Vec3.zero,
      doubleSided: m['doubleSided'] as bool? ?? false,
      blend: alphaMode == 'BLEND',
      baseColorTexture: (bct?['index'] as num?)?.toInt(),
    );
  }

  static GltfNodeDef _parseNode(Map node) {
    final children = <int>[
      for (final c in (node['children'] as List? ?? const [])) (c as num).toInt(),
    ];
    final matrix = node['matrix'] as List?;
    if (matrix != null && matrix.length == 16) {
      return GltfNodeDef(
        matrix: Mat4.fromColumnMajor(
            [for (final v in matrix) (v as num).toDouble()]),
        children: children,
        mesh: (node['mesh'] as num?)?.toInt(),
        skin: (node['skin'] as num?)?.toInt(),
        name: node['name'] as String?,
      );
    }
    final t = node['translation'] as List?;
    final r = node['rotation'] as List?;
    final s = node['scale'] as List?;
    return GltfNodeDef(
      translation: t != null
          ? Vec3((t[0] as num).toDouble(), (t[1] as num).toDouble(),
              (t[2] as num).toDouble())
          : Vec3.zero,
      rotation: r != null
          ? Quaternion((r[0] as num).toDouble(), (r[1] as num).toDouble(),
              (r[2] as num).toDouble(), (r[3] as num).toDouble())
          : Quaternion.identity,
      scale: s != null
          ? Vec3((s[0] as num).toDouble(), (s[1] as num).toDouble(),
              (s[2] as num).toDouble())
          : Vec3.one,
      children: children,
      mesh: (node['mesh'] as num?)?.toInt(),
      skin: (node['skin'] as num?)?.toInt(),
      name: node['name'] as String?,
    );
  }

  // ── Textures ───────────────────────────────────────────────────────────

  static Future<List<GltfTexture>> _decodeTextures(
    Map<String, dynamic> json,
    List bufferViews,
    List<Uint8List> buffers,
  ) async {
    final textures = json['textures'] as List? ?? const [];
    final images = json['images'] as List? ?? const [];
    final out = <GltfTexture>[];
    for (final tex in textures) {
      final source = ((tex as Map)['source'] as num?)?.toInt();
      if (source == null || source >= images.length) {
        out.add(_placeholder());
        continue;
      }
      try {
        final img = images[source] as Map;
        Uint8List? data;
        if (img['bufferView'] != null) {
          final bv = bufferViews[(img['bufferView'] as num).toInt()] as Map;
          final buffer = buffers[(bv['buffer'] as num).toInt()];
          final off = (bv['byteOffset'] as num?)?.toInt() ?? 0;
          final len = (bv['byteLength'] as num).toInt();
          data = Uint8List.sublistView(buffer, off, off + len);
        } else if (img['uri'] != null &&
            (img['uri'] as String).startsWith('data:')) {
          final uri = img['uri'] as String;
          data = base64Decode(uri.substring(uri.indexOf(',') + 1));
        }
        if (data == null) {
          out.add(_placeholder());
          continue;
        }
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        out.add(GltfTexture(frame.image));
      } catch (_) {
        out.add(_placeholder());
      }
    }
    return out;
  }

  static GltfTexture? _placeholderImage;

  /// A 1×1 white texture, used when an image fails to decode so a textured
  /// primitive still renders (lit by its base-colour factor). Built
  /// synchronously off a [ui.PictureRecorder].
  static GltfTexture _placeholder() {
    final cached = _placeholderImage;
    if (cached != null) return cached;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final image = recorder.endRecording().toImageSync(1, 1);
    final tex = GltfTexture(image);
    _placeholderImage = tex;
    return tex;
  }

  // ── Bounds estimate ─────────────────────────────────────────────────────

  static (Vec3, double, Vec3, Vec3) _estimateBounds(
    List<GltfNodeDef> nodes,
    List<int> roots,
    List<List<GltfPrimitive>> meshes,
    List<GltfSkin> skins,
  ) {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    var any = false;

    // Rest-pose global transforms (no animation).
    final globals = List<Mat4>.filled(nodes.length, Mat4.identity());
    final visited = List<bool>.filled(nodes.length, false);
    void rec(int i, Mat4 parent) {
      if (i < 0 || i >= nodes.length || visited[i]) return;
      visited[i] = true;
      globals[i] = parent * nodes[i].localMatrix();
      for (final c in nodes[i].children) {
        rec(c, globals[i]);
      }
    }
    final id = Mat4.identity();
    for (final r in roots) {
      rec(r, id);
    }

    for (var ni = 0; ni < nodes.length; ni++) {
      final meshIdx = nodes[ni].mesh;
      if (meshIdx == null || meshIdx >= meshes.length) continue;
      final skinIdx = nodes[ni].skin;
      List<Mat4>? jointMats;
      if (skinIdx != null && skinIdx < skins.length) {
        final skin = skins[skinIdx];
        jointMats = [
          for (var k = 0; k < skin.joints.length; k++)
            globals[skin.joints[k]] * skin.inverseBind[k],
        ];
      }
      for (final prim in meshes[meshIdx]) {
        final pos = prim.positions;
        final step = (prim.vertexCount ~/ 64).clamp(1, 1 << 20);
        for (var v = 0; v < prim.vertexCount; v += step) {
          final px = pos[v * 3], py = pos[v * 3 + 1], pz = pos[v * 3 + 2];
          Vec3 world;
          if (jointMats != null && prim.skinned) {
            world = _skinPoint(jointMats, prim.joints!, prim.weights!, v, px, py, pz);
          } else {
            world = globals[ni].transformPoint(Vec3(px, py, pz));
          }
          if (world.x < minX) minX = world.x;
          if (world.y < minY) minY = world.y;
          if (world.z < minZ) minZ = world.z;
          if (world.x > maxX) maxX = world.x;
          if (world.y > maxY) maxY = world.y;
          if (world.z > maxZ) maxZ = world.z;
          any = true;
        }
      }
    }
    if (!any) {
      return (Vec3.zero, 1.0, const Vec3(-0.5, -0.5, -0.5), const Vec3(0.5, 0.5, 0.5));
    }
    final center = Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
    final radius = Vec3(maxX - minX, maxY - minY, maxZ - minZ).length / 2;
    return (center, radius, Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
  }

  static Vec3 _skinPoint(List<Mat4> jm, Uint16List joints, Float32List weights,
      int v, double px, double py, double pz) {
    var x = 0.0, y = 0.0, z = 0.0;
    for (var w = 0; w < 4; w++) {
      final wt = weights[v * 4 + w];
      if (wt == 0) continue;
      final m = jm[joints[v * 4 + w]].m;
      x += wt * (m[0] * px + m[4] * py + m[8] * pz + m[12]);
      y += wt * (m[1] * px + m[5] * py + m[9] * pz + m[13]);
      z += wt * (m[2] * px + m[6] * py + m[10] * pz + m[14]);
    }
    return Vec3(x, y, z);
  }
}
