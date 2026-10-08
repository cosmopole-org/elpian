import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import '../core/resources.dart';
import '../models/elpian_node.dart';

/// `<track>`: a timed text track (WebVTT or SubRip) of its `<video>`. Not
/// rendered itself — the video loads the `default` (or first)
/// subtitles/captions track and overlays its cues, with a CC toggle.
class HtmlTrack {
  static Widget build(ElpianNode node, List<Widget> children) {
    return const SizedBox.shrink();
  }

  /// The text track a `<video>` shows: the `default` subtitles / captions
  /// `<track>`, else the first one; `null` when it has none.
  static ElpianNode? captionTrack(ElpianNode media) {
    final tracks = media.children
        .where((c) =>
            c.type == 'track' &&
            (c.props['src']?.toString() ?? '').isNotEmpty &&
            const {'subtitles', 'captions'}
                .contains((c.props['kind'] ?? 'subtitles').toString()))
        .toList();
    if (tracks.isEmpty) return null;
    return tracks.firstWhere(
      (t) =>
          t.props['default'] == true ||
          t.props['default'] == 'default' ||
          t.props['default'] == '',
      orElse: () => tracks.first,
    );
  }

  /// Load and parse [track]'s cue file — over HTTP(S), from a `data:` URI or
  /// from the asset bundle. SubRip (`.srt`) or WebVTT (anything else).
  static Future<ClosedCaptionFile> load(ElpianNode track) async {
    final src = ElpianResources.resolve(track.props['src'].toString());
    final String text;
    if (src.startsWith('http://') || src.startsWith('https://')) {
      final response = await http.get(Uri.parse(src));
      if (response.statusCode >= 400) {
        throw StateError('track $src: HTTP ${response.statusCode}');
      }
      text = response.body;
    } else if (src.startsWith('data:')) {
      text = UriData.parse(src).contentAsString();
    } else {
      text = await rootBundle
          .loadString(src.startsWith('asset:') ? src.substring(6) : src);
    }
    return parse(text, srcHint: src);
  }

  /// Parse cue text: SubRip when it looks like SubRip (or [srcHint] ends in
  /// `.srt`), WebVTT otherwise.
  static ClosedCaptionFile parse(String text, {String srcHint = ''}) {
    final trimmed = text.trimLeft();
    final isSrt = srcHint.toLowerCase().split('?').first.endsWith('.srt') ||
        (!trimmed.startsWith('WEBVTT') &&
            RegExp(r'^\d+\s*\r?\n\d\d:\d\d:\d\d,\d\d\d').hasMatch(trimmed));
    return isSrt ? SubRipCaptionFile(text) : WebVTTCaptionFile(text);
  }
}
