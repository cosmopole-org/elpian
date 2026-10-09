import 'package:flutter/material.dart';
import '../css/stylesheet.dart' as css;
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_img.dart';

/// `<picture>`: art direction. The first `<source>` (with `srcset` or `src`)
/// whose `media` query matches the current viewport — or that has no
/// `media` — supplies the image shown by the inner `<img>` (its first
/// `srcset` candidate); when none matches the `<img>` shows its own `src`.
/// Re-evaluated when the viewport changes.
class HtmlPicture {
  static Widget build(ElpianNode node, List<Widget> children) {
    final imgIndex = node.children.indexWhere((c) => c.type == 'img');
    final sources = node.children
        .where((c) =>
            c.type == 'source' &&
            ((c.props['srcset'] ?? c.props['srcSet'] ?? c.props['src'])
                    ?.toString()
                    .isNotEmpty ??
                false))
        .toList();

    Widget result;
    if (imgIndex < 0) {
      // No <img>: show whatever else the picture holds.
      final rest = [
        for (var i = 0; i < node.children.length && i < children.length; i++)
          if (node.children[i].type != 'source') children[i],
      ];
      result = rest.isEmpty
          ? const SizedBox.shrink()
          : rest.length == 1
              ? rest.first
              : Column(mainAxisSize: MainAxisSize.min, children: rest);
    } else if (sources.isEmpty) {
      result = imgIndex < children.length
          ? children[imgIndex]
          : HtmlImg.build(node.children[imgIndex], const []);
    } else {
      final img = node.children[imgIndex];
      final rendered = imgIndex < children.length ? children[imgIndex] : null;
      result = Builder(builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final source = selectSource(sources, size.width, size.height);
        if (source == null) {
          return rendered ?? HtmlImg.build(img, const []);
        }
        return HtmlImg.build(
          img.copyWith(props: {...img.props, 'src': source}),
          const [],
        );
      });
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  /// The URL of the first source matching a [width] × [height] viewport.
  static String? selectSource(
      List<ElpianNode> sources, double width, double height) {
    for (final s in sources) {
      final media = s.props['media']?.toString();
      if (media != null &&
          media.trim().isNotEmpty &&
          !css.MediaQuery(query: media, stylesheet: css.CSSStylesheet())
              .matches(width, height)) {
        continue;
      }
      final srcset =
          (s.props['srcset'] ?? s.props['srcSet'] ?? s.props['src']).toString();
      final first = srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
      if (first.isNotEmpty) return first;
    }
    return null;
  }
}
