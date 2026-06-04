/// Platform-agnostic entry point for fetching GLB/GLTF bytes.
///
/// Resolves to the `dart:io` implementation on native targets and the
/// `dart:html` implementation on web, with a throwing stub as the fallback so
/// the symbol always exists for static analysis.
library;

export 'model_fetch_stub.dart'
    if (dart.library.io) 'model_fetch_io.dart'
    if (dart.library.html) 'model_fetch_web.dart';
