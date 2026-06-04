/// Fallback implementation used when neither `dart:io` nor `dart:html` is
/// available. Always throws — the conditional export in
/// `model_fetch.dart` replaces this with a real implementation on every
/// supported Flutter platform.
library;

import 'dart:typed_data';

Future<Uint8List> fetchModelBytes(String url) {
  throw UnsupportedError(
    'GLTF model fetching is not supported on this platform (no dart:io or '
    'dart:html). URL: $url',
  );
}
