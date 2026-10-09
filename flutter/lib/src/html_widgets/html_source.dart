import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

/// `<source>`: an alternative resource of its parent. Not rendered itself —
/// `<video>` / `<audio>` play the first `<source src>` when they have no
/// `src` of their own, and `<picture>` picks the first `<source srcset>`
/// whose `media` query matches the viewport.
class HtmlSource {
  static Widget build(ElpianNode node, List<Widget> children) {
    return const SizedBox.shrink();
  }

  /// The resource a `<video>` / `<audio>` plays: its own `src`, else the
  /// first `<source src>` child whose `type` is not one the platform players
  /// cannot handle.
  static String mediaSource(ElpianNode media) {
    final direct = media.props['src']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;
    String? fallback;
    for (final child in media.children) {
      if (child.type != 'source') continue;
      final src = child.props['src']?.toString() ?? '';
      if (src.isEmpty) continue;
      fallback ??= src;
      final type = (child.props['type'] ?? '').toString().toLowerCase();
      if (!_unplayable.any(type.startsWith)) return src;
    }
    return fallback ?? '';
  }

  /// MIME types none of the platform media backends decode.
  static const _unplayable = ['video/ogg', 'audio/ogg; codecs=speex'];
}
