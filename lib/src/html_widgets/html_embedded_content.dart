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
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    if (_supportsInlineWebView && _isHttpLike(widget.url)) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(widget.url));
    }
  }

  static bool _isHttpLike(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }


  @override
  void didUpdateWidget(covariant HtmlEmbeddedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;

    if (_supportsInlineWebView && _isHttpLike(widget.url)) {
      final controller = _controller ??
          (WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted));
      controller.loadRequest(Uri.parse(widget.url));
      _controller = controller;
    } else {
      _controller = null;
    }
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
