import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/elpian_services.dart';
import '../core/event_dispatcher.dart';
import '../core/node_events.dart';
import '../core/resources.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlImg {
  static Widget build(ElpianNode node, List<Widget> children) {
    final rawSrc = node.props['src'] as String? ?? '';
    final alt = node.props['alt'] as String? ?? '';

    // Server-driven UIs reference images root-relatively ("/icons/x.png"):
    // resolve against the server origin (ElpianResources.baseUrl / the page
    // origin on web) and load over the network. Only explicit `asset:` srcs
    // target the Flutter asset bundle.
    final src = ElpianResources.resolve(rawSrc);

    // D5: when a display size is known from the style, decode the image at that
    // size instead of full resolution — large source images otherwise decode at
    // their native pixel dimensions, wasting decode CPU and image-cache memory.
    final w = node.style?.width;
    final h = node.style?.height;
    final cacheWidth = (w != null && w > 0) ? w.round() : null;
    final cacheHeight = (h != null && h > 0) ? h.round() : null;

    Widget result = ElpianResources.isNetwork(src)
        ? Image.network(src,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            errorBuilder: (_, __, ___) => Text(alt))
        : Image.asset(src.startsWith('asset:') ? src.substring(6) : src,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            errorBuilder: (_, __, ___) => Text(alt));

    // `<img usemap="#name">`: clickable regions from `<map name="name">`.
    final services = ElpianServices.current;
    final areas = services.document.imageMap(node.props['usemap']?.toString());
    if (areas != null && areas.isNotEmpty) {
      result = HtmlImageMap(
        image: result,
        naturalSize: imageProviderFor(src),
        areas: areas,
        imageId: elementIdOf(node),
        dispatcher: services.events,
      );
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  /// The un-resized provider for a resolved `src` (used to learn the image's
  /// natural size).
  static ImageProvider? imageProviderFor(String src) {
    if (src.isEmpty) return null;
    if (src.startsWith('data:')) {
      try {
        return MemoryImage(UriData.parse(src).contentAsBytes());
      } catch (_) {
        return null;
      }
    }
    if (ElpianResources.isNetwork(src)) return NetworkImage(src);
    return AssetImage(src.startsWith('asset:') ? src.substring(6) : src);
  }
}

/// One `<area>`'s region, in the image's natural pixels.
class ImageMapArea {
  ImageMapArea(this.shape, this.coords);

  /// `rect`, `circle`, `poly` or `default` (the whole image).
  final String shape;
  final List<double> coords;

  factory ImageMapArea.of(ElpianNode area) {
    final raw = (area.props['shape'] ?? 'rect').toString().toLowerCase();
    final shape = switch (raw) {
      'circ' || 'circle' => 'circle',
      'poly' || 'polygon' => 'poly',
      'default' => 'default',
      _ => 'rect',
    };
    final coords = (area.props['coords'] ?? '')
        .toString()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    return ImageMapArea(shape, coords);
  }

  /// Whether the natural-pixel point (x, y) lies in this region (HTML image
  /// map hit testing; polygons by the even-odd rule).
  bool contains(double x, double y) {
    final c = coords;
    switch (shape) {
      case 'default':
        return true;
      case 'circle':
        if (c.length < 3) return false;
        final dx = x - c[0], dy = y - c[1];
        return dx * dx + dy * dy <= c[2] * c[2];
      case 'poly':
        final n = c.length ~/ 2;
        if (n < 3) return false;
        var inside = false;
        for (var i = 0, j = n - 1; i < n; j = i++) {
          final xi = c[2 * i], yi = c[2 * i + 1];
          final xj = c[2 * j], yj = c[2 * j + 1];
          if ((yi > y) != (yj > y) &&
              x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
            inside = !inside;
          }
        }
        return inside;
      default:
        if (c.length < 4) return false;
        final l = c[0] < c[2] ? c[0] : c[2];
        final r = c[0] < c[2] ? c[2] : c[0];
        final t = c[1] < c[3] ? c[1] : c[3];
        final b = c[1] < c[3] ? c[3] : c[1];
        return x >= l && x <= r && y >= t && y <= b;
    }
  }
}

/// An image with clickable `<area>` regions.
///
/// Area coordinates are in the image's natural pixels and scale with the
/// rendered size (until the natural size is known they are taken as
/// rendered pixels). A tap is hit-tested against the areas in document order;
/// the first that contains it dispatches its `click` (and `tap`) events —
/// registered under the area's key, as a child of the image — and follows
/// its `href` (`target="_blank"` opens externally). The pointer turns into a
/// hand over an active area; the areas' `alt` texts label it for
/// accessibility.
class HtmlImageMap extends StatefulWidget {
  const HtmlImageMap({
    super.key,
    required this.image,
    required this.areas,
    required this.imageId,
    required this.dispatcher,
    this.naturalSize,
  });

  final Widget image;
  final List<ElpianNode> areas;
  final String imageId;
  final EventDispatcher dispatcher;

  /// Resolved once to learn the natural size.
  final ImageProvider? naturalSize;

  @override
  State<HtmlImageMap> createState() => _HtmlImageMapState();
}

class _HtmlImageMapState extends State<HtmlImageMap> {
  Size? _natural;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int? _hovered;

  late List<ImageMapArea> _regions = widget.areas.map(ImageMapArea.of).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HtmlImageMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areas != widget.areas) {
      _regions = widget.areas.map(ImageMapArea.of).toList();
    }
    if (oldWidget.naturalSize != widget.naturalSize) _resolve();
  }

  void _resolve() {
    final provider = widget.naturalSize;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stopListening();
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _natural =
          Size(info.image.width.toDouble(), info.image.height.toDouble()));
      info.dispose();
    }, onError: (_, __) {});
    _stream = stream..addListener(_listener!);
  }

  void _stopListening() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  /// The area under a local point, or null.
  int? _areaAt(Offset local) {
    final rendered = context.size;
    var x = local.dx, y = local.dy;
    final natural = _natural;
    if (rendered != null &&
        natural != null &&
        rendered.width > 0 &&
        rendered.height > 0) {
      x = x * natural.width / rendered.width;
      y = y * natural.height / rendered.height;
    }
    for (var i = 0; i < _regions.length; i++) {
      if (_isActive(widget.areas[i]) && _regions[i].contains(x, y)) return i;
    }
    return null;
  }

  /// `nohref` areas (no link, no events) are holes in the map.
  bool _isActive(ElpianNode area) =>
      area.props['nohref'] == null &&
      (area.props['href'] != null || (area.events?.isNotEmpty ?? false));

  void _activate(int index, TapUpDetails details) {
    final area = widget.areas[index];
    final id = area.key ?? '${widget.imageId}/area$index';
    if (area.events?.isNotEmpty ?? false) {
      final d = widget.dispatcher;
      d.registerNode(id, area, parentId: widget.imageId);
      if (area.events!.containsKey('tap')) {
        NodeEvents.forDispatcher(area, d, id).pointer('tap',
            position: details.globalPosition,
            localPosition: details.localPosition);
      }
      d.dispatchClick(id, position: details.globalPosition);
    }
    final href = area.props['href']?.toString();
    if (href != null && href.isNotEmpty && !href.startsWith('#')) {
      final uri = Uri.tryParse(href);
      if (uri != null) {
        launchUrl(
          uri,
          mode: area.props['target'] == '_blank'
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered;
    final Widget result = MouseRegion(
      cursor: hovered != null ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (e) {
        final i = _areaAt(e.localPosition);
        if (i != _hovered) setState(() => _hovered = i);
      },
      onExit: (_) {
        if (_hovered != null) setState(() => _hovered = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = _areaAt(d.localPosition);
          if (i != null) _activate(i, d);
        },
        child: widget.image,
      ),
    );
    return Semantics(
      container: true,
      label: widget.areas
          .map((a) => a.props['alt']?.toString())
          .whereType<String>()
          .join(', '),
      child: result,
    );
  }
}
