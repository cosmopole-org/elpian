import 'package:flutter/material.dart';

import 'html_embedded_link_card.dart';

/// Embedded web content where neither `dart:io` nor the web platform is
/// available: a card that opens the URL.
class HtmlEmbeddedContent extends StatelessWidget {
  final String url;
  final String label;

  /// Inline document (`srcdoc`), shown instead of [url] where supported.
  final String? html;

  /// Extra element attributes (honoured by the web iframe).
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
    return EmbeddedLinkCard(
      url: url,
      label: label,
      hasInlineDocument: html != null && html!.isNotEmpty,
    );
  }
}
