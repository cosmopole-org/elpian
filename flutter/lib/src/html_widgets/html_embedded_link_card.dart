import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gives embedded content (an iframe, a web view) the HTML default size —
/// 300 × 150 — on any axis its parent leaves loose, so a platform view is
/// never laid out unbounded. A fixed (tight) size from the style wins.
class EmbeddedContentBox extends StatelessWidget {
  const EmbeddedContentBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasTightWidth
            ? null
            : (constraints.hasBoundedWidth
                ? constraints.maxWidth.clamp(0.0, 300.0)
                : 300.0);
        final height = constraints.hasTightHeight
            ? null
            : (constraints.hasBoundedHeight
                ? constraints.maxHeight.clamp(0.0, 150.0)
                : 150.0);
        return SizedBox(width: width, height: height, child: child);
      },
    );
  }
}

/// Where embedded web content cannot be shown inline: a card naming it with
/// a button that opens the URL in the browser.
class EmbeddedLinkCard extends StatelessWidget {
  const EmbeddedLinkCard({
    super.key,
    required this.url,
    required this.label,
    this.hasInlineDocument = false,
  });

  final String url;
  final String label;

  /// The content is an inline document (`srcdoc`) with no URL to open.
  final bool hasInlineDocument;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty && !hasInlineDocument) {
      return Center(child: Text('$label source is required'));
    }
    final uri = Uri.tryParse(url);
    return Container(
      decoration:
          BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.public, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url.isEmpty ? '$label (inline document)' : '$label: $url',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (uri != null && url.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open $label',
              onPressed: () =>
                  launchUrl(uri, mode: LaunchMode.externalApplication),
            ),
          ],
        ],
      ),
    );
  }
}
