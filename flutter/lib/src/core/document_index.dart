import '../models/elpian_node.dart';

/// One `<datalist>` option: the value an input takes and the label shown.
class DatalistOption {
  final String value;
  final String label;

  const DatalistOption(this.value, this.label);
}

/// Cross-element lookups an HTML document resolves by id or name, indexed
/// from the rendered tree before its widgets are built.
///
/// Builders only see their own node, but some elements are defined by
/// another one elsewhere in the document: `<input list="x">` takes its
/// suggestions from `<datalist id="x">`, and `<img usemap="#m">` its hot spots
/// from `<map name="m">`. The engine walks the tree once per render
/// ([index]) so those references resolve regardless of document order.
class DocumentIndex {
  final Map<String, List<DatalistOption>> _datalists = {};
  final Map<String, List<ElpianNode>> _imageMaps = {};

  /// The options of `<datalist id="[id]">`, or `null` if there is none.
  List<DatalistOption>? datalist(String? id) =>
      id == null ? null : _datalists[id];

  /// The `<area>` elements of `<map name="[name]">` (a leading `#` is
  /// ignored), or `null` if there is no such map.
  List<ElpianNode>? imageMap(String? name) {
    if (name == null) return null;
    return _imageMaps[name.startsWith('#') ? name.substring(1) : name];
  }

  /// Index [root]'s subtree. Entries from earlier renders stay until an
  /// element with the same id / name replaces them (a scoped re-render only
  /// walks the patched subtree).
  void index(ElpianNode root) => _visit(root);

  void clear() {
    _datalists.clear();
    _imageMaps.clear();
  }

  void _visit(ElpianNode node) {
    switch (node.type) {
      case 'datalist':
        final id = node.props['id'] ?? node.key;
        if (id != null) _datalists[id.toString()] = _options(node);
        break;
      case 'map':
        final name = node.props['name'] ?? node.props['id'] ?? node.key;
        if (name != null) {
          final areas = <ElpianNode>[];
          void collect(ElpianNode n) {
            if (n.type == 'area') areas.add(n);
            n.children.forEach(collect);
          }

          node.children.forEach(collect);
          _imageMaps[name.toString()] = areas;
        }
        break;
    }
    for (final child in node.children) {
      _visit(child);
    }
  }

  static List<DatalistOption> _options(ElpianNode datalist) {
    final out = <DatalistOption>[];
    for (final c in datalist.children) {
      if (c.type != 'option') continue;
      final text = c.props['text']?.toString() ??
          c.children.map((t) => t.props['text']?.toString() ?? '').join();
      final value = c.props['value']?.toString() ?? text;
      if (value.isEmpty) continue;
      final label = c.props['label']?.toString() ?? text;
      out.add(DatalistOption(value, label.isEmpty ? value : label));
    }
    return out;
  }
}
