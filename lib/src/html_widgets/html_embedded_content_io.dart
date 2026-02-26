import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HtmlEmbeddedContent extends StatefulWidget {
  final String url;
  final String label;

  const HtmlEmbeddedContent({
    super.key,
    required this.url,
    required this.label,
  });

  @override
  State<HtmlEmbeddedContent> createState() => _HtmlEmbeddedContentState();
}

class _HtmlEmbeddedContentState extends State<HtmlEmbeddedContent> {
  WebViewController? _controller;

  bool get _supportsInlineWebView {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _configureControllerFor(widget.url);
  }

  @override
  void didUpdateWidget(covariant HtmlEmbeddedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _configureControllerFor(widget.url);
    }
  }

  void _configureControllerFor(String url) {
    if (_supportsInlineWebView && _isHttpLike(url)) {
      final controller = _controller ??
          (WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted));
      controller.loadRequest(Uri.parse(url));
      _controller = controller;
      return;
    }

    _controller = null;
  }

  static bool _isHttpLike(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return Center(
        child: Text('${widget.label} source is required'),
      );
    }

    if (_controller != null) {
      return ClipRect(child: WebViewWidget(controller: _controller!));
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.label}: ${widget.url}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open ${widget.label}',
            onPressed: () async {
              final uri = Uri.tryParse(widget.url);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }
}
