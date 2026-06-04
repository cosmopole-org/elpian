/// Asynchronous, deduplicated cache of loaded [GltfModel]s keyed by URL.
///
/// The 3D renderer is synchronous (it runs inside a [CustomPainter]), so it
/// cannot await a download. Instead it calls [get]: the first call kicks off a
/// background fetch + parse and returns null; subsequent frames return the
/// model once it is ready. A widget ticker repainting every frame naturally
/// picks the model up the moment it loads — no explicit callback needed.
library;

import 'dart:typed_data';

import 'gltf_loader.dart';
import 'gltf_model.dart';
import 'net/model_fetch.dart';

enum GltfLoadStatus { idle, loading, ready, failed }

class GltfModelCache {
  GltfModelCache._();
  static final GltfModelCache instance = GltfModelCache._();

  final Map<String, GltfModel> _ready = {};
  final Map<String, GltfLoadStatus> _status = {};
  final Map<String, Object> _errors = {};

  GltfLoadStatus statusOf(String url) => _status[url] ?? GltfLoadStatus.idle;
  Object? errorOf(String url) => _errors[url];

  /// Returns the loaded model for [url], or null if it is not ready yet.
  /// Triggers a background load on first request.
  GltfModel? get(String url) {
    final ready = _ready[url];
    if (ready != null) return ready;
    final status = _status[url] ?? GltfLoadStatus.idle;
    if (status == GltfLoadStatus.idle || status == GltfLoadStatus.failed) {
      // Retry failed loads at most by re-requesting explicitly; for now only
      // (re)start when idle to avoid hammering a broken URL every frame.
      if (status == GltfLoadStatus.idle) {
        _startLoad(url);
      }
    }
    return null;
  }

  /// Explicitly (re)load a URL, returning the model. Useful for preloading.
  Future<GltfModel> load(String url) async {
    final ready = _ready[url];
    if (ready != null) return ready;
    return _startLoad(url);
  }

  /// Preload a batch of models (e.g. at game start) without blocking.
  void preload(Iterable<String> urls) {
    for (final url in urls) {
      if (!_ready.containsKey(url) &&
          (_status[url] ?? GltfLoadStatus.idle) == GltfLoadStatus.idle) {
        _startLoad(url);
      }
    }
  }

  final Map<String, Future<GltfModel>> _inFlight = {};

  Future<GltfModel> _startLoad(String url) {
    final existing = _inFlight[url];
    if (existing != null) return existing;
    _status[url] = GltfLoadStatus.loading;
    final future = _doLoad(url);
    _inFlight[url] = future;
    return future;
  }

  Future<GltfModel> _doLoad(String url) async {
    try {
      final Uint8List bytes = await fetchModelBytes(url);
      final model = await GltfBinaryLoader.parse(bytes);
      _ready[url] = model;
      _status[url] = GltfLoadStatus.ready;
      _inFlight.remove(url);
      return model;
    } catch (e) {
      _status[url] = GltfLoadStatus.failed;
      _errors[url] = e;
      _inFlight.remove(url);
      rethrow;
    }
  }
}
