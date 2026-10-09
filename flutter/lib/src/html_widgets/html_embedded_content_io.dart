import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'html_embedded_link_card.dart';

/// Embedded web content on native platforms: an inline web view where
/// `webview_flutter` has one (Android, iOS, macOS) — loading the URL, or the
/// inline document (`srcdoc`) when given — and a card that opens the URL in
/// the browser elsewhere (Windows, Linux, tests).
class HtmlEmbeddedContent extends StatefulWidget {
  final String url;
  final String label;

  /// Inline document (`srcdoc`); takes precedence over [url], as in HTML.
  final String? html;

  /// Extra element attributes (honoured by the web iframe only).
  final Map<String, String> attributes;

  const HtmlEmbeddedContent({
    super.key,
    required this.url,
    required this.label,
    this.html,
    this.attributes = const {},
  });

  @override
  State<HtmlEmbeddedContent> createState() => _HtmlEmbeddedContentState();
}

class _HtmlEmbeddedContentState extends State<HtmlEmbeddedContent> {
  WebViewController? _controller;

  bool get _supportsInlineWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get _hasDocument => widget.html != null && widget.html!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant HtmlEmbeddedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.html != widget.html) {
      _configure();
    }
  }

  void _configure() {
    final canLoad = _hasDocument || _isHttpLike(widget.url);
    if (!_supportsInlineWebView || !canLoad) {
      _controller = null;
      return;
    }
    final controller = _controller ??
        (WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted));
    if (_hasDocument) {
      controller.loadHtmlString(widget.html!,
          baseUrl: _isHttpLike(widget.url) ? widget.url : null);
    } else {
      controller.loadRequest(Uri.parse(widget.url));
    }
    _controller = controller;
  }

  static bool _isHttpLike(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return EmbeddedContentBox(
        child: ClipRect(child: WebViewWidget(controller: controller)),
      );
    }
    return EmbeddedLinkCard(
      url: widget.url,
      label: widget.label,
      hasInlineDocument: _hasDocument,
    );
  }
}
