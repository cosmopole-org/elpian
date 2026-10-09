import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/resources.dart';

/// Decoded images for the canvas `drawImage` / `createPattern` commands.
///
/// A [Canvas] paints synchronously, but images arrive asynchronously, so the
/// painter asks this cache for a `src` and gets `null` the first time — which
/// also starts the load. When the image is decoded the cache notifies its
/// listeners; canvas widgets and cached contexts listen and repaint, at which
/// point the image is there. This is the same contract as an HTML canvas
/// whose `<img>` has not loaded yet: the draw is skipped, and the page draws
/// again once it has.
///
/// Sources accepted:
///  * `http(s)://…` and server-relative paths (resolved with
///    [ElpianResources.resolve]) — loaded over the network;
///  * `data:` URIs — decoded in memory;
///  * `asset:path` or a bare path with no server base — the asset bundle;
///  * any key registered with [put] (host-provided images).
class CanvasImageCache extends ChangeNotifier {
  CanvasImageCache();

  /// The cache every canvas uses unless given another one.
  static final CanvasImageCache shared = CanvasImageCache();

  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  bool _notifyScheduled = false;

  /// The decoded image for [src], or `null` while it loads (or when it
  /// failed). The first miss starts the load.
  ui.Image? get(String src) {
    if (src.isEmpty) return null;
    final image = _images[src];
    if (image != null) return image;
    if (!_loading.contains(src) && !_failed.contains(src)) _load(src);
    return null;
  }

  /// Whether [src] is decoded and ready.
  bool has(String src) => _images.containsKey(src);

  /// Whether [src] is still loading.
  bool isLoading(String src) => _loading.contains(src);

  /// Whether loading [src] failed (it is not retried until [evict]).
  bool hasFailed(String src) => _failed.contains(src);

  /// Register a decoded image under [key] (an id `drawImage` can name with
  /// `src` or `imageId`). Replaces (and disposes) any image already there.
  void put(String key, ui.Image image) {
    final previous = _images[key];
    _images[key] = image;
    _loading.remove(key);
    _failed.remove(key);
    if (previous != null && !identical(previous, image)) previous.dispose();
    _scheduleNotify();
  }

  /// Forget [key], so the next [get] loads it again.
  void evict(String key) {
    _images.remove(key)?.dispose();
    _failed.remove(key);
  }

  /// Drop every image.
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _failed.clear();
  }

  /// The [ImageProvider] for a canvas image source, or `null` if [src] cannot
  /// name one.
  static ImageProvider? providerFor(String src) {
    if (src.isEmpty) return null;
    if (src.startsWith('data:')) {
      try {
        return MemoryImage(UriData.parse(src).contentAsBytes());
      } catch (_) {
        return null;
      }
    }
    final resolved = ElpianResources.resolve(src);
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return NetworkImage(resolved);
    }
    if (resolved.startsWith('asset:')) return AssetImage(resolved.substring(6));
    return AssetImage(resolved);
  }

  void _load(String src) {
    final provider = providerFor(src);
    if (provider == null) {
      _failed.add(src);
      return;
    }
    _loading.add(src);
    final ImageStream stream;
    try {
      stream = provider.resolve(ImageConfiguration.empty);
    } catch (_) {
      _loading.remove(src);
      _failed.add(src);
      return;
    }
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        _loading.remove(src);
        _images[src]?.dispose();
        _images[src] = info.image.clone();
        info.dispose();
        _scheduleNotify();
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        _loading.remove(src);
        _failed.add(src);
        debugPrint('Elpian canvas: image "$src" failed to load: $error');
      },
    );
    stream.addListener(listener);
  }

  /// Notify on a microtask: an image already in Flutter's cache completes
  /// synchronously, i.e. possibly while a canvas is painting, and listeners
  /// (which repaint or rebuild) must not run in the middle of a paint.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
