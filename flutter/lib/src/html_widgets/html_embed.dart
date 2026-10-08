import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import 'html_audio.dart';
import 'html_embedded_content.dart';
import 'html_img.dart';
import 'html_video.dart';

class HtmlEmbed {
  static Widget build(ElpianNode node, List<Widget> children) {
    final src = node.props['src'] as String? ?? '';

    Widget result = _buildTypedEmbeddedWidget(node, src);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static Widget _buildTypedEmbeddedWidget(ElpianNode node, String src) {
    final type = (node.props['type'] as String? ?? '').toLowerCase();

    if (_looksLikeImage(type, src)) {
      return HtmlImg.build(node, const []);
    }

    if (_looksLikeVideo(type, src)) {
      return HtmlVideo.build(node, const []);
    }

    if (_looksLikeAudio(type, src)) {
      return HtmlAudio.build(node, const []);
    }

    return HtmlEmbeddedContent(url: src, label: 'embed');
  }

  static bool _looksLikeImage(String type, String src) {
    return type.startsWith('image/') ||
        src.endsWith('.png') ||
        src.endsWith('.jpg') ||
        src.endsWith('.jpeg') ||
        src.endsWith('.gif') ||
        src.endsWith('.webp') ||
        src.endsWith('.svg');
  }

  static bool _looksLikeVideo(String type, String src) {
    return type.startsWith('video/') ||
        src.endsWith('.mp4') ||
        src.endsWith('.webm') ||
        src.endsWith('.mov') ||
        src.endsWith('.m3u8');
  }

  static bool _looksLikeAudio(String type, String src) {
    return type.startsWith('audio/') ||
        src.endsWith('.mp3') ||
        src.endsWith('.wav') ||
        src.endsWith('.ogg') ||
        src.endsWith('.aac') ||
        src.endsWith('.m4a');
  }
}
