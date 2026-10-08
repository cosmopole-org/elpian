/// Event-handler namespacing for inline client components.
///
/// Each live `clientComp` mount owns a VM; to deliver a tap to the *right* VM,
/// the handler names in its rendered output are namespaced with the mount id
/// (`<mountId>::<fn>`). The host's global event router parses that prefix to pick
/// the owning VM, then invokes the bare function name on it. Keeping this logic
/// pure (and separate from the widget) makes the routing rules directly
/// testable — they are the contract that bounds a client component's events to
/// its own VM instead of leaking across the screen.
library;

class ClientCompRouting {
  ClientCompRouting._();

  /// Separator between a mount id and a handler/function name.
  static const String separator = '::';

  /// The namespaced handler name a tap on this component will carry.
  static String namespaced(String mountId, String fn) =>
      '$mountId$separator$fn';

  /// Parse a (possibly namespaced) handler name. Returns `(mountId, fn)` when it
  /// belongs to a client component, or null when it is a bare/page-VM handler.
  static ({String mountId, String fn})? parse(String handler) {
    final idx = handler.indexOf(separator);
    if (idx <= 0) return null;
    return (
      mountId: handler.substring(0, idx),
      fn: handler.substring(idx + separator.length),
    );
  }

  /// Prefix every event-handler name in [node] (and its descendants) with
  /// [mountId] so taps route back to the owning VM. Already-namespaced names are
  /// left untouched (idempotent). Mutates and returns [node].
  static Map<String, dynamic> namespaceHandlers(
    Map<String, dynamic> node,
    String mountId,
  ) {
    final events = node['events'];
    if (events is Map) {
      final ns = <String, dynamic>{};
      events.forEach((k, v) {
        ns[k.toString()] =
            (v is String && v.isNotEmpty && !v.contains(separator))
                ? namespaced(mountId, v)
                : v;
      });
      node['events'] = ns;
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          namespaceHandlers(child, mountId);
        }
      }
    }
    return node;
  }
}
