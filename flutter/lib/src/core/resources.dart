import 'package:flutter/foundation.dart' show kIsWeb;

/// Resolution of server-relative resource URLs (images, media) used by the
/// HTML widgets.
///
/// Server-driven UIs reference assets root-relatively (`/icons/x.png`) or
/// relatively (`img/x.png`) — URLs that mean "on the server that rendered this
/// UI", not "in the Flutter asset bundle". [baseUrl] is the server origin those
/// URLs resolve against; integrations that know the server (e.g.
/// `NextjsServerWidget`) set it when they mount. On web it defaults to the page
/// origin.
class ElpianResources {
  ElpianResources._();

  /// Origin (scheme + host [+ port]) that relative resource URLs resolve
  /// against, e.g. `https://game.example.com`. No trailing slash.
  static String? baseUrl;

  /// Resolve a `src`-style URL:
  /// - absolute `http(s)`/`data:` URLs pass through;
  /// - `asset:foo/bar.png` explicitly targets the Flutter asset bundle
  ///   (returned without the scheme);
  /// - root-relative and relative paths resolve against [baseUrl] (or the page
  ///   origin on web);
  /// - anything unresolvable is returned unchanged.
  static String resolve(String src) {
    if (src.isEmpty ||
        src.startsWith('http://') ||
        src.startsWith('https://') ||
        src.startsWith('data:')) {
      return src;
    }
    if (src.startsWith('asset:')) return src;
    final base = baseUrl ?? (kIsWeb ? Uri.base.origin : null);
    if (base == null) return src;
    if (src.startsWith('/')) return '$base$src';
    return '$base/$src';
  }

  /// True when [resolve] produced (or passes through) a network URL.
  static bool isNetwork(String resolved) =>
      resolved.startsWith('http://') ||
      resolved.startsWith('https://') ||
      resolved.startsWith('data:');
}
