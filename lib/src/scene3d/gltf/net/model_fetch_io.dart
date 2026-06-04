/// Native (mobile/desktop) GLB/GLTF byte fetcher built on `dart:io`.
///
/// Supports `http`/`https` URLs as well as bare local file paths (handy for
/// bundling models with the app or testing). Follows redirects and surfaces a
/// descriptive error on non-2xx responses.
library;

import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> fetchModelBytes(String url) async {
  final uri = Uri.parse(url);
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, 'ElpianUI/1.0');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  // Treat anything else as a local file path.
  final file = File(uri.scheme == 'file' ? uri.toFilePath() : url);
  return Uint8List.fromList(await file.readAsBytes());
}
