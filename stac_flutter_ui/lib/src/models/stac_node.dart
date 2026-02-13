import 'css_style.dart';

class StacNode {
  final String type;
  final Map<String, dynamic> props;
  final List<StacNode> children;
  final CSSStyle? style;
  final String? key;
  final Map<String, dynamic>? events;

  const StacNode({
    required this.type,
    this.props = const {},
    this.children = const [],
    this.style,
    this.key,
    this.events,
  });

  factory StacNode.fromJson(Map<String, dynamic> json) {
    final props = Map<String, dynamic>.from(
      json['props'] as Map<String, dynamic>? ?? {},
    );
    // Include top-level style in props so the engine can parse it
    if (json['style'] != null && !props.containsKey('style')) {
      props['style'] = json['style'];
    }
    return StacNode(
      type: json['type'] as String,
      props: props,
      children: (json['children'] as List<dynamic>?)
              ?.map((child) => StacNode.fromJson(child as Map<String, dynamic>))
              .toList() ??
          [],
      key: json['key'] as String?,
      events: json['events'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'props': props,
      'children': children.map((child) => child.toJson()).toList(),
      if (key != null) 'key': key,
      if (events != null) 'events': events,
    };
  }

  StacNode copyWith({
    String? type,
    Map<String, dynamic>? props,
    List<StacNode>? children,
    CSSStyle? style,
    String? key,
    Map<String, dynamic>? events,
  }) {
    return StacNode(
      type: type ?? this.type,
      props: props ?? this.props,
      children: children ?? this.children,
      style: style ?? this.style,
      key: key ?? this.key,
      events: events ?? this.events,
    );
  }
}
