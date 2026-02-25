import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HtmlEmbeddedContent extends StatelessWidget {
  final String url;
  final String label;

  const HtmlEmbeddedContent({
    super.key,
    required this.url,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Center(
        child: Text('$label source is required'),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: $url',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open $label',
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }
}
