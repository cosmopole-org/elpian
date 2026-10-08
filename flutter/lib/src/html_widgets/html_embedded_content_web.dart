/// Embedded web content on Flutter web: a real `<iframe>` element, embedded
/// as a platform view.
///
/// Elements are created through `dart:js_interop` (as the Godot web surface
/// does) rather than `package:web`, so the package gains no dependency for
/// one `createElement` call.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'html_embedded_link_card.dart';

/// The platform view type of an embedded iframe.
const String elpianIframeViewType = 'elpian-iframe';

bool _registered = false;

@JS('document.createElement')
external JSObject _createElement(JSString tag);

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(
    elpianIframeViewType,
    (int viewId, {Object? params}) {
      final p = params is Map ? params : const <Object?, Object?>{};
      final iframe = _createElement('iframe'.toJS);
      final style = iframe.getProperty<JSObject>('style'.toJS);
      style
        ..setProperty('width'.toJS, '100%'.toJS)
        ..setProperty('height'.toJS, '100%'.toJS)
        ..setProperty('border'.toJS, 'none'.toJS)
        ..setProperty('display'.toJS, 'block'.toJS);
      final attributes = p['attributes'];
      if (attributes is Map) {
        attributes.forEach((name, value) {
          iframe.callMethod<JSAny?>(
              'setAttribute'.toJS, '$name'.toJS, '$value'.toJS);
        });
      }
      final html = p['html'];
      if (html is String && html.isNotEmpty) {
        iframe.setProperty('srcdoc'.toJS, html.toJS);
      }
      final src = p['src'];
      if (src is String && src.isNotEmpty) {
        iframe.setProperty('src'.toJS, src.toJS);
      }
      return iframe;
    },
  );
}

class HtmlEmbeddedContent extends StatelessWidget {
  final String url;
  final String label;

  /// Inline document (`srcdoc`); takes precedence over [url], as in HTML.
  final String? html;

  /// Extra iframe attributes (`allow`, `sandbox`, `referrerpolicy`, …).
  final Map<String, String> attributes;

  const HtmlEmbeddedContent({
    super.key,
    required this.url,
    required this.label,
    this.html,
    this.attributes = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hasDocument = html != null && html!.isNotEmpty;
    if (url.isEmpty && !hasDocument) {
      return EmbeddedLinkCard(url: url, label: label);
    }
    _register();
    return EmbeddedContentBox(
      child: HtmlElementView(
        // A new source is a new element.
        key: ValueKey<Object>(Object.hash(url, html, attributes.toString())),
        viewType: elpianIframeViewType,
        creationParams: <String, Object?>{
          'src': url,
          'html': html,
          'attributes': attributes,
        },
      ),
    );
  }
}
