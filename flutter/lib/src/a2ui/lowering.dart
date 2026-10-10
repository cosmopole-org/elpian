/// Lowering: an A2UI surface → an Elpian node tree (the same JSON a mini app
/// renders), built from Elpian's existing widgets with Material 3 visuals, so
/// agent UI and static Elpian UI mix freely. The same table as the web
/// renderer:
///
/// | A2UI           | Elpian nodes                                                   |
/// |----------------|----------------------------------------------------------------|
/// | Text           | `Text` (typography per variant); Markdown → `p` + inline spans  |
/// | Image          | `Image` sized per variant (`ClipRRect` for avatars)             |
/// | Icon           | `Icon` (Material name, or an `svgPath` the Icon widget paints)  |
/// | Video / Audio  | `video` / `audio` with controls                                |
/// | Row / Column   | `Row` / `Column` (justify → justifyContent, align → alignItems; `weight` → `Expanded`) |
/// | List           | `ListView` (vertical or horizontal scroll)                     |
/// | Card           | `Card`                                                         |
/// | Tabs           | tab header row + the selected child (state kept per surface)    |
/// | Modal          | the trigger; when open, a barrier + dialog over the surface     |
/// | Divider        | `Divider` / a vertical rule                                    |
/// | Button         | `Button` (default / primary / borderless; disabled by checks)   |
/// | TextField      | label + `TextField` (+ check error text)                       |
/// | CheckBox       | `Checkbox` + label                                              |
/// | ChoicePicker   | radio / checkbox list or chips, optional filter field          |
/// | Slider         | label + value + `Slider`                                        |
/// | DateTimeInput  | label + date / time / datetime `TextField` (pickers)           |
///
/// Interactions are closures in the nodes' `events` (the event dispatcher
/// calls function handlers directly); they write the data model (two-way
/// binding), dispatch actions, or change UI-local state through
/// [LoweringHooks]. Nothing here builds Flutter widgets — the output is plain
/// node JSON the engine's widget builders render.
library;

import 'dart:math' as math;

import '../core/event_system.dart';
import 'context.dart';
import 'errors.dart';
import 'functions.dart';
import 'markdown.dart';
import 'processor.dart';

typedef _Node = Map<String, dynamic>;

/// A lowered Elpian node (node JSON).
typedef LoweredNode = Map<String, dynamic>;

class LoweringHooks {
  const LoweringHooks({
    required this.write,
    required this.action,
    required this.invalidate,
    this.error,
  });

  /// Two-way binding: write [value] at the absolute [path].
  final void Function(String surfaceId, String path, Object? value) write;

  /// An interactive component fired its `action` (resolved in [scope]).
  final void Function(
          String surfaceId, String componentId, Object? action, String scope)
      action;

  /// UI-local state changed (tab, modal, filter…): render again.
  final void Function() invalidate;

  /// Evaluation problems (unknown function, bad template…).
  final void Function(A2UIError error)? error;
}

/// UI-local state that survives re-lowering (selected tab, open modal, filter
/// text, touched fields).
class A2UIUiState {
  final Map<String, Object?> _values = {};

  T get<T>(String key, T fallback) =>
      _values.containsKey(key) ? _values[key] as T : fallback;

  void set(String key, Object? value) => _values[key] = value;

  /// Drop the state of one surface (after `deleteSurface`).
  void clearSurface(String prefix) =>
      _values.removeWhere((k, _) => k.startsWith(prefix));
}

class LoweringOptions {
  const LoweringOptions({
    required this.hooks,
    required this.state,
    this.keyPrefix,
    this.showAttribution = true,
    this.expandAll = false,
  });

  final LoweringHooks hooks;
  final A2UIUiState state;

  /// Prefix for node keys (element ids) — unique per embedding widget.
  final String? keyPrefix;

  /// Show `agentDisplayName` / `iconUrl` above the surface.
  final bool showAttribution;

  /// Lower every deferred subtree too — closed modals, hidden tabs (previews, tests).
  final bool expandAll;
}

class LoweringPlaceholder {
  const LoweringPlaceholder(this.id, this.reason);
  final String id;
  final String reason;
}

class LoweringResult {
  LoweringResult(this.node, this.lowered, this.placeholders);
  final LoweredNode node;

  /// `componentId@scope` of every component lowered.
  final List<String> lowered;

  /// Components rendered as an error placeholder (unknown type, cycle, depth).
  final List<LoweringPlaceholder> placeholders;
}

/// The surface palette: Material 3 baseline with the theme's primary color.
class A2UIPalette {
  const A2UIPalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
  });

  final String primary;
  final String onPrimary;
  final String primaryContainer;
  final String onSurface = '#1D1B20';
  final String onSurfaceVariant = '#49454F';
  final String outline = '#79747E';
  final String outlineVariant = '#CAC4D0';
  final String surfaceContainer = '#F7F2FA';
  final String surfaceContainerHigh = '#ECE6F0';
  final String error = '#B3261E';
}

final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

A2UIPalette paletteFor(Map<String, dynamic> theme) {
  final pc = theme['primaryColor'];
  final primary =
      pc is String && _hexColor.hasMatch(pc) ? pc.toUpperCase() : '#6750A4';
  return A2UIPalette(
    primary: primary,
    onPrimary: _luminance(primary) > 0.5 ? '#1D1B20' : '#FFFFFF',
    primaryContainer: _mix(primary, '#FFFFFF', 0.82),
  );
}

List<int> _rgb(String hex) {
  final n = int.parse(hex.substring(1), radix: 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

double _luminance(String hex) {
  final c = _rgb(hex).map((c) {
    final s = c / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }).toList();
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

String _mix(String a, String b, double t) {
  final x = _rgb(a);
  final y = _rgb(b);
  final out = StringBuffer('#');
  for (var i = 0; i < 3; i++) {
    out.write(
        (x[i] + (y[i] - x[i]) * t).round().toRadixString(16).padLeft(2, '0'));
  }
  return out.toString().toUpperCase();
}

/// Leaf-margin strategy: visual leaves carry the spacing, containers none.
const double _leafMargin = 4;
const int _maxDepth = 64;

const Map<String, Map<String, dynamic>> _textVariants = {
  'h1': {'fontSize': 40, 'fontWeight': 600, 'lineHeight': 1.2},
  'h2': {'fontSize': 32, 'fontWeight': 600, 'lineHeight': 1.25},
  'h3': {'fontSize': 28, 'fontWeight': 600, 'lineHeight': 1.28},
  'h4': {'fontSize': 24, 'fontWeight': 600, 'lineHeight': 1.33},
  'h5': {'fontSize': 20, 'fontWeight': 600, 'lineHeight': 1.4},
  'caption': {'fontSize': 13, 'lineHeight': 1.35},
  'body': {'fontSize': 16, 'lineHeight': 1.5},
};

/// A2UI icon names → Material icon names where the snake_case form differs.
const Map<String, String> _iconAliases = {
  'favoriteOff': 'favorite_border',
  'starOff': 'star_border',
  'play': 'play_arrow',
  'rewind': 'fast_rewind',
};

/// The Material icon name for an A2UI icon name (`accountCircle` → `account_circle`).
String materialIconName(String name) =>
    _iconAliases[name] ??
    name
        .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();

const Map<String, String> _justifyMap = {
  'start': 'flex-start',
  'center': 'center',
  'end': 'flex-end',
  'spaceBetween': 'space-between',
  'spaceAround': 'space-around',
  'spaceEvenly': 'space-evenly',
  'stretch': 'flex-start',
};

const Map<String, String> _alignMap = {
  'start': 'flex-start',
  'center': 'center',
  'end': 'flex-end',
  'stretch': 'stretch',
};

class _Ctx {
  _Ctx({
    required this.dc,
    required this.scope,
    required this.depth,
    required this.stack,
    required this.parent,
    required this.contentColor,
    required this.interceptPress,
  });

  final DataContext dc;
  final String scope;
  final int depth;
  final List<String> stack;

  /// The A2UI type of the parent (for `weight`).
  final String? parent;

  /// Inside a button: no leaf margins, icons take the button's content color.
  final String? contentColor;

  /// Modal trigger: a press opens the modal instead of firing the action.
  final void Function()? interceptPress;

  _Ctx copy({
    DataContext? dc,
    String? scope,
    int? depth,
    List<String>? stack,
    Object? parent = _keep,
    Object? contentColor = _keep,
    Object? interceptPress = _keep,
  }) =>
      _Ctx(
        dc: dc ?? this.dc,
        scope: scope ?? this.scope,
        depth: depth ?? this.depth,
        stack: stack ?? this.stack,
        parent: identical(parent, _keep) ? this.parent : parent as String?,
        contentColor: identical(contentColor, _keep)
            ? this.contentColor
            : contentColor as String?,
        interceptPress: identical(interceptPress, _keep)
            ? this.interceptPress
            : interceptPress as void Function()?,
      );
}

const Object _keep = Object();

/// Inline style maps typed for the engine (`Map<String, dynamic>`).
Map<String, dynamic> _st(Map<String, dynamic> m) => m;

_Node _el(String type,
    [Map<String, dynamic>? props,
    List<_Node> children = const [],
    String? key,
    Map<String, dynamic>? events]) {
  final node = <String, dynamic>{
    'type': type,
    'props': props ?? <String, dynamic>{},
    'children': children,
  };
  if (key != null && key.isNotEmpty) node['key'] = key;
  if (events != null && events.isNotEmpty) node['events'] = events;
  return node;
}

_Node _textNode(String text, Map<String, dynamic> style, [String? key]) =>
    _el('Text', {'text': text, 'style': style}, const [], key);

/// Stop an internal event from bubbling into the embedding app's handlers.
void _handled(ElpianEvent e) => e.stopPropagation();

/// The value an input / change event carries.
Object? eventValue(ElpianEvent e) {
  if (e is ElpianInputEvent) return e.value;
  return e.data['value'];
}

/// Lower [surface] to an Elpian node tree.
LoweringResult lowerSurface(
        A2UISurfaceModel surface, LoweringOptions options) =>
    _Lowerer(surface, options).run();

class _Lowerer {
  _Lowerer(this.surface, this.options)
      : palette = paletteFor(surface.theme),
        prefix = '${options.keyPrefix ?? 'a2ui'}:${surface.id}';

  final A2UISurfaceModel surface;
  final LoweringOptions options;
  final A2UIPalette palette;
  final String prefix;
  final List<String> lowered = [];
  final List<LoweringPlaceholder> placeholders = [];
  final List<_Node> overlays = [];

  LoweringHooks get hooks => options.hooks;

  String _stateKey(String key, String what) => '$key#$what';

  LoweringResult run() {
    final parts = <_Node>[];
    final header = options.showAttribution ? _attribution() : null;
    if (header != null) parts.add(header);
    if (surface.isReady) {
      final ctx = _Ctx(
          dc: surface.context('/'),
          scope: '/',
          depth: 0,
          stack: const [],
          parent: null,
          contentColor: null,
          interceptPress: null);
      parts.add(child('root', ctx));
    }
    var node = _el(
        'Column',
        {
          'style': _st({
            'alignItems': 'stretch',
            'justifyContent': 'flex-start',
            'color': palette.onSurface,
          })
        },
        parts,
        prefix);
    if (overlays.isNotEmpty) {
      node = _el('ConstrainedBox', {
        'style': _st({'minHeight': 420})
      }, [
        _el('Stack', {
          'style': _st({'alignment': 'top left'})
        }, [
          node,
          ...overlays
        ])
      ]);
    }
    return LoweringResult(node, lowered, placeholders);
  }

  _Node? _attribution() {
    final theme = surface.theme;
    final name = theme['agentDisplayName'] is String
        ? theme['agentDisplayName'] as String
        : '';
    final iconUrl = theme['iconUrl'];
    final icon = iconUrl is String &&
            RegExp(r'^https?:|^data:image/', caseSensitive: false)
                .hasMatch(iconUrl)
        ? iconUrl
        : '';
    if (name.isEmpty && icon.isEmpty) return null;
    final row = <_Node>[];
    if (icon.isNotEmpty) {
      row.add(_el('ClipRRect', {
        'style': _st({'borderRadius': 10})
      }, [
        _el('Image', {
          'src': icon,
          'fit': 'cover',
          'alt': name,
          'style': _st({'width': 20, 'height': 20}),
        })
      ]));
    }
    if (name.isNotEmpty) {
      row.add(_textNode(
          name,
          _st({
            'fontSize': 12,
            'fontWeight': 500,
            'color': palette.onSurfaceVariant,
            'margin': '0 0 0 8',
          })));
    }
    return _el(
        'Row',
        {
          'style': _st({'alignItems': 'center', 'padding': '4 4 8 4'})
        },
        row,
        '$prefix/attribution');
  }

  String _keyFor(String id, _Ctx ctx) =>
      ctx.scope == '/' ? '$prefix:$id' : '$prefix:$id@${ctx.scope}';

  void _report(A2UIError e) => hooks.error?.call(
      A2UIError(e.category, e.message, surfaceId: surface.id, path: e.path));

  T _eval<T>(_Ctx ctx, T Function() fn, T fallback) =>
      ctx.dc.safe(fn, fallback, _report);

  String _str(_Ctx ctx, Object? v) =>
      v == null ? '' : _eval(ctx, () => ctx.dc.string(v), '');

  _Node _placeholder(String id, String reason, String key) {
    placeholders.add(LoweringPlaceholder(id, reason));
    return _el(
        'Container',
        {
          'style': _st({
            'padding': 8,
            'margin': _leafMargin,
            'backgroundColor': '#FDECEA',
            'borderRadius': 8,
          })
        },
        [
          _textNode(reason, _st({'fontSize': 13, 'color': palette.error}))
        ],
        key);
  }

  /// Lower the component [id] (a child reference) in [ctx].
  _Node child(String id, _Ctx ctx) {
    final component = surface.components[id];
    final key = _keyFor(id, ctx);
    if (component == null) {
      // Not arrived yet (progressive rendering).
      return _el(
          'SizedBox',
          {
            'style': _st({'width': 0, 'height': 0})
          },
          const [],
          key);
    }
    final marker = '$id@${ctx.scope}';
    if (ctx.stack.contains(marker)) {
      return _placeholder(id, 'Circular reference to "$id"', key);
    }
    if (ctx.depth >= _maxDepth) {
      return _placeholder(id, 'Component tree too deep', key);
    }
    lowered.add(marker);
    final inner = ctx.copy(depth: ctx.depth + 1, stack: [...ctx.stack, marker]);
    var node = _component(component, key, inner);
    final weight =
        component['weight'] is num ? component['weight'] as num : null;
    final type = component['component'];
    if (weight != null &&
        weight > 0 &&
        (ctx.parent == 'Row' || ctx.parent == 'Column')) {
      node = _el('Expanded', {'flex': math.max(1, weight.round())}, [node]);
    } else if (ctx.parent == 'Row' &&
        const [
          'Text', 'Column', 'Row', 'List', 'Card', 'Tabs', 'TextField', //
          'CheckBox', 'ChoicePicker', 'Slider', 'DateTimeInput', 'Video',
          'AudioPlayer',
        ].contains(type)) {
      // A row shrinks text and nested layouts to its width (CSS flex-shrink).
      node = _el('Flexible', {'flex': 1, 'fit': 'loose'}, [node]);
    }
    return node;
  }

  List<_Node> _children(A2UIComponent component, _Ctx ctx) {
    final spec = component['children'];
    final out = <_Node>[];
    final childCtx = ctx.copy(
        parent: component['component'] as String?, interceptPress: null);
    if (spec is List) {
      for (final id in spec) {
        if (id is String) out.add(child(id, childCtx));
      }
    } else if (spec is Map &&
        spec['componentId'] is String &&
        spec['path'] is String) {
      final template = spec['componentId'] as String;
      final base = ctx.dc.resolvePath(spec['path'] as String);
      final items = _eval<Object?>(ctx, () => ctx.dc.model.get(base), null);
      String join(Object k) => base == '/' ? '/$k' : '$base/$k';
      final keys = items is List
          ? List<Object>.generate(items.length, (i) => i)
          : items is Map
              ? items.keys.map((k) => k as Object).toList()
              : const <Object>[];
      for (final k in keys) {
        final scope = join(k);
        out.add(child(
            template, childCtx.copy(dc: ctx.dc.child(scope), scope: scope)));
      }
    }
    return out;
  }

  _Node _component(A2UIComponent c, String key, _Ctx ctx) {
    switch (c['component']) {
      case 'Text':
        return _text(c, key, ctx);
      case 'Image':
        return _image(c, key, ctx);
      case 'Icon':
        return _icon(c, key, ctx);
      case 'Video':
        return _el(
            'video',
            {
              'src': _str(ctx, c['url']),
              'controls': true,
              'style': _st({
                'height': 220,
                'margin': _leafMargin,
                'objectFit': 'contain',
              }),
            },
            const [],
            key);
      case 'AudioPlayer':
        final description = _str(ctx, c['description']);
        final parts = <_Node>[];
        if (description.isNotEmpty) {
          parts.add(_textNode(description,
              _st({'fontSize': 14, 'color': palette.onSurfaceVariant})));
        }
        parts.add(_el(
            'audio',
            {
              'src': _str(ctx, c['url']),
              'controls': true,
              'style': _st({'height': 54}),
            },
            const [],
            '$key/audio'));
        return _el(
            'Column',
            {
              'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
            },
            parts,
            key);
      case 'Row':
      case 'Column':
        return _flex(c, key, ctx);
      case 'List':
        return _list(c, key, ctx);
      case 'Card':
        return _el(
            'Card',
            {
              'elevation': 1,
              'style': _st({
                'padding': 16,
                'margin': _leafMargin,
                'borderRadius': 12,
                'backgroundColor': '#FFFFFF',
                'borderColor': palette.outlineVariant,
                'borderWidth': 1,
              }),
            },
            c['child'] is String
                ? [
                    child(c['child'] as String,
                        ctx.copy(parent: 'Card', interceptPress: null))
                  ]
                : const [],
            key);
      case 'Tabs':
        return _tabs(c, key, ctx);
      case 'Modal':
        return _modal(c, key, ctx);
      case 'Divider':
        return c['axis'] == 'vertical'
            ? _el(
                'Container',
                {
                  'style': _st({
                    'width': 1,
                    'minHeight': 24,
                    'margin': '0 8',
                    'backgroundColor': palette.outlineVariant,
                  })
                },
                const [],
                key)
            : _el(
                'Divider',
                {
                  'style': _st({
                    'height': 17,
                    'borderColor': palette.outlineVariant,
                  })
                },
                const [],
                key);
      case 'Button':
        return _button(c, key, ctx);
      case 'TextField':
        return _textField(c, key, ctx);
      case 'CheckBox':
        return _checkBox(c, key, ctx);
      case 'ChoicePicker':
        return _choicePicker(c, key, ctx);
      case 'Slider':
        return _slider(c, key, ctx);
      case 'DateTimeInput':
        return _dateTime(c, key, ctx);
      default:
        return _placeholder(
            '${c['id']}', 'Unknown component: ${c['component']}', key);
    }
  }

  // --------------------------------------------------------------------------
  // Display
  // --------------------------------------------------------------------------

  Map<String, dynamic> _textStyle(String variant, _Ctx ctx) {
    final base = <String, dynamic>{
      ...(_textVariants[variant] ?? _textVariants['body']!)
    };
    if (variant == 'caption') base['color'] = palette.onSurfaceVariant;
    if (ctx.contentColor != null) base['color'] = ctx.contentColor;
    return base;
  }

  _Node _text(A2UIComponent c, String key, _Ctx ctx) {
    final value = _str(ctx, c['text']);
    final variant =
        c['variant'] is String && _textVariants.containsKey(c['variant'])
            ? c['variant'] as String
            : 'body';
    final double margin = ctx.contentColor != null ? 0 : _leafMargin;
    final blocks = parseMarkdown(value);
    if (blocks.isEmpty) {
      return _textNode(
          '', {..._textStyle(variant, ctx), 'margin': margin}, key);
    }
    if (isPlainText(blocks)) {
      return _textNode(plainText(blocks),
          {..._textStyle(variant, ctx), 'margin': margin}, key);
    }
    final out = <_Node>[
      for (var i = 0; i < blocks.length; i++)
        _markdownBlock(blocks[i], variant, ctx, '$key/md$i'),
    ];
    if (out.length == 1) {
      out.first['key'] = key;
      ((out.first['props'] as Map)['style'] as Map)['margin'] = margin;
      return out.first;
    }
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'flex-start', 'margin': margin})
        },
        out,
        key);
  }

  _Node _markdownBlock(
      MarkdownBlock block, String variant, _Ctx ctx, String key) {
    var style = _textStyle(variant, ctx);
    var prefixText = '';
    if (block.type == 'heading' && variant == 'body') {
      style = _textStyle('h${math.min(5, block.level)}', ctx);
    }
    if (block.type == 'bullet') prefixText = '•  ';
    if (block.type == 'ordered') prefixText = '${block.number}.  ';
    final inlines = prefixText.isNotEmpty
        ? [MarkdownInline(prefixText), ...block.inlines]
        : block.inlines;
    final spans = inlines.map(_inline).toList();
    return _el(
        'p',
        {
          'style': <String, dynamic>{
            ...style,
            'margin': 0,
            'padding': block.type == 'bullet' || block.type == 'ordered'
                ? '0 0 0 8'
                : 0,
          }
        },
        spans,
        key);
  }

  _Node _inline(MarkdownInline i) {
    final style = <String, dynamic>{};
    if (i.bold) style['fontWeight'] = 700;
    if (i.italic) style['fontStyle'] = 'italic';
    if (i.strike) style['textDecoration'] = 'line-through';
    if (i.code) {
      style['fontFamily'] = 'monospace';
      style['backgroundColor'] = '#F1EDF4';
    }
    if (i.href != null &&
        RegExp(r'^https?://', caseSensitive: false).hasMatch(i.href!)) {
      return _el('a', {
        'href': i.href,
        'target': '_blank',
        'text': i.text,
        'style': {...style, 'color': palette.primary},
      });
    }
    return _el('span', {'text': i.text, 'style': style});
  }

  _Node _image(A2UIComponent c, String key, _Ctx ctx) {
    final src = _str(ctx, c['url']);
    final variant =
        c['variant'] is String ? c['variant'] as String : 'mediumFeature';
    final alt = _accessibilityLabel(c, ctx) ?? _str(ctx, c['description']);
    final fit = c['fit'] is String
        ? c['fit'] as String
        : variant == 'icon'
            ? 'contain'
            : 'cover';
    const sizes = <String, Map<String, dynamic>>{
      'icon': {'width': 24, 'height': 24},
      'avatar': {'width': 40, 'height': 40},
      'smallFeature': {'width': 100, 'height': 100},
      'mediumFeature': {'height': 200, 'maxWidth': 300},
      'largeFeature': {'height': 320},
      'header': {'height': 200},
    };
    final size = sizes[variant] ?? sizes['mediumFeature']!;
    final image = _el(
        'Image',
        {
          'src': src,
          'fit': fit,
          'alt': alt,
          'style': <String, dynamic>{...size},
        },
        const [],
        '$key/img');
    final radius = variant == 'avatar'
        ? 20
        : variant == 'icon'
            ? 0
            : 8;
    return _el(
        'Container',
        {
          'style': _st({'margin': variant == 'header' ? 0 : _leafMargin})
        },
        [
          radius > 0
              ? _el('ClipRRect', {
                  'style': _st({'borderRadius': radius})
                }, [
                  image
                ])
              : image
        ],
        key);
  }

  _Node _icon(A2UIComponent c, String key, _Ctx ctx) {
    final name = _eval<Object?>(ctx, () => ctx.dc.evaluate(c['name']), null);
    final color = ctx.contentColor ?? palette.onSurfaceVariant;
    final double margin = ctx.contentColor != null ? 0 : _leafMargin;
    if (name is Map && name['svgPath'] is String) {
      // Flutter has no SVG decoder for a data-URI image: the Icon widget
      // paints the path itself.
      return _el(
          'Icon',
          {
            'svgPath': name['svgPath'],
            'size': 24.0,
            'semanticLabel': _accessibilityLabel(c, ctx) ?? '',
            'style': _st({'color': color, 'margin': margin}),
          },
          const [],
          key);
    }
    final text = stringifyValue(name);
    return _el(
        'Icon',
        {
          'icon': materialIconName(text.isEmpty ? 'help' : text),
          'size': 24.0,
          'style': _st({'color': color, 'margin': margin}),
        },
        const [],
        key);
  }

  // --------------------------------------------------------------------------
  // Layout
  // --------------------------------------------------------------------------

  _Node _flex(A2UIComponent c, String key, _Ctx ctx) {
    final justify = c['justify'] is String ? c['justify'] as String : 'start';
    final align = c['align'] is String ? c['align'] as String : 'stretch';
    var children = _children(c, ctx);
    if (justify == 'stretch') {
      children = children
          .map((n) => n['type'] == 'Expanded' || n['type'] == 'Flexible'
              ? n
              : _el('Expanded', {'flex': 1}, [n]))
          .toList();
    }
    return _el(
        c['component'] as String,
        {
          'style': _st({
            'justifyContent': _justifyMap[justify] ?? 'flex-start',
            'alignItems': _alignMap[align] ?? 'stretch',
          })
        },
        children,
        key);
  }

  _Node _list(A2UIComponent c, String key, _Ctx ctx) {
    final horizontal = c['direction'] == 'horizontal';
    final align = c['align'] is String ? c['align'] as String : 'stretch';
    var children =
        _children({...c, 'component': horizontal ? 'Row' : 'Column'}, ctx)
            .map((n) => n['type'] == 'Flexible'
                ? (n['children'] as List).first as _Node
                : n)
            .toList();
    if (horizontal) {
      children = children
          .map((n) => _el('ConstrainedBox', {
                'style': _st({'maxWidth': 320})
              }, [
                n
              ]))
          .toList();
    }
    final inner = _el(
        horizontal ? 'Row' : 'Column',
        {
          'style': _st({'alignItems': _alignMap[align] ?? 'stretch'})
        },
        children);
    return _el(
        'ListView',
        {'scrollDirection': horizontal ? 'horizontal' : 'vertical'},
        horizontal ? children : [inner],
        key);
  }

  _Node _tabs(A2UIComponent c, String key, _Ctx ctx) {
    final tabs = c['tabs'] is List
        ? (c['tabs'] as List).whereType<Map>().toList()
        : const <Map>[];
    final sk = _stateKey(key, 'tab');
    final selected =
        math.min(options.state.get<int>(sk, 0), math.max(0, tabs.length - 1));
    final p = palette;
    final headers = <_Node>[];
    for (var i = 0; i < tabs.length; i++) {
      final active = i == selected;
      headers.add(_el(
          'Container',
          {
            'style': _st({'padding': '12 16 0 16', 'cursor': 'pointer'})
          },
          [
            _el('Column', {
              'style': _st({'alignItems': 'stretch'})
            }, [
              _textNode(
                  _str(ctx, tabs[i]['title']),
                  _st({
                    'fontSize': 14,
                    'fontWeight': 600,
                    'color': active ? p.primary : p.onSurfaceVariant,
                    'textAlign': 'center',
                  })),
              _el('Container', {
                'style': _st({
                  'height': 3,
                  'margin': '10 0 0 0',
                  'backgroundColor': active ? p.primary : 'transparent',
                  'borderRadius': '3 3 0 0',
                })
              }),
            ]),
          ],
          '$key/tab$i',
          {
            'click': (ElpianEvent e) {
              _handled(e);
              options.state.set(sk, i);
              hooks.invalidate();
            },
          }));
    }
    final childCtx = ctx.copy(parent: 'Tabs', interceptPress: null);
    final bodies = <_Node>[];
    for (var i = 0; i < tabs.length; i++) {
      final t = tabs[i];
      if (t['child'] is! String) continue;
      if (i == selected) {
        bodies.add(child(t['child'] as String, childCtx));
      } else if (options.expandAll) {
        child(t['child'] as String, childCtx);
      }
    }
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch'})
        },
        [
          _el(
              'Row',
              {
                'style': _st({
                  'alignItems': 'flex-end',
                  'justifyContent': 'flex-start',
                })
              },
              headers),
          _el('Divider', {
            'style': _st({'height': 1, 'borderColor': p.outlineVariant})
          }),
          ...bodies,
        ],
        key);
  }

  _Node _modal(A2UIComponent c, String key, _Ctx ctx) {
    final sk = _stateKey(key, 'open');
    final open = options.state.get<bool>(sk, false);
    void setOpen(bool v) {
      options.state.set(sk, v);
      hooks.invalidate();
    }

    _Node trigger = _el('SizedBox', {
      'style': _st({'width': 0, 'height': 0})
    });
    if (c['trigger'] is String) {
      final target = surface.components[c['trigger']];
      trigger = child(c['trigger'] as String,
          ctx.copy(parent: 'Modal', interceptPress: () => setOpen(true)));
      if (target != null && target['component'] != 'Button') {
        trigger = _el(
            'GestureDetector',
            {},
            [trigger],
            '$key/trigger',
            {
              'click': (ElpianEvent e) {
                _handled(e);
                setOpen(true);
              },
            });
      }
    }
    if ((open || options.expandAll) && c['content'] is String) {
      final content = child(c['content'] as String,
          ctx.copy(parent: 'Modal', interceptPress: null));
      if (open) overlays.add(_dialog(key, content, () => setOpen(false)));
    }
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'flex-start'})
        },
        [trigger],
        key);
  }

  _Node _dialog(String key, _Node content, void Function() close) {
    final p = palette;
    final closeButton = _el(
        'Container',
        {
          'style': _st({'padding': 8, 'borderRadius': 20, 'cursor': 'pointer'})
        },
        [
          _el('Icon', {
            'icon': 'close',
            'size': 24.0,
            'style': _st({'color': p.onSurfaceVariant}),
          })
        ],
        '$key/close',
        {
          'click': (ElpianEvent e) {
            _handled(e);
            close();
          },
        });
    final panel = _el(
        'Container',
        {
          'style': _st({
            'backgroundColor': p.surfaceContainerHigh,
            'borderRadius': 28,
            'padding': '8 16 24 24',
            'maxWidth': 560,
            'margin': 24,
            'boxShadow': '0 8px 24px rgba(0,0,0,0.25)',
          })
        },
        [
          _el('Column', {
            'style': _st({'alignItems': 'stretch'})
          }, [
            _el('Row', {
              'style': _st({'justifyContent': 'flex-end'})
            }, [
              closeButton
            ]),
            content,
          ])
        ],
        '$key/dialog',
        // Taps inside the dialog stay inside (the barrier closes on outside taps).
        {'click': (ElpianEvent e) => _handled(e)});
    final barrier = _el(
        'Container',
        {
          'style': _st({'backgroundColor': 'rgba(0,0,0,0.4)'})
        },
        [
          _el('Center', {}, [panel])
        ],
        '$key/barrier',
        {
          'click': (ElpianEvent e) {
            _handled(e);
            close();
          },
        });
    return _el('Positioned', {
      'style': _st({'top': 0, 'left': 0, 'right': 0, 'bottom': 0})
    }, [
      barrier
    ]);
  }

  // --------------------------------------------------------------------------
  // Inputs
  // --------------------------------------------------------------------------

  String? _accessibilityLabel(A2UIComponent c, _Ctx ctx) {
    final a = c['accessibility'];
    if (a is Map && a.containsKey('label')) {
      final s = _str(ctx, a['label']);
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// Bind an input: the absolute path its value writes to, or a UI-state slot
  /// for literals.
  ({Object? Function(Object? fallback) read, void Function(Object? v) write})
      _binding(Object? value, _Ctx ctx, String key) {
    final path = isBinding(value)
        ? ctx.dc.resolvePath((value as Map)['path'] as String)
        : null;
    final local = _stateKey(key, 'value');
    return (
      read: (fallback) => path != null
          ? _eval<Object?>(ctx, () => ctx.dc.model.get(path), null)
          : options.state.get<Object?>(local, fallback),
      write: (v) {
        if (path != null) {
          hooks.write(surface.id, path, v);
        } else {
          options.state.set(local, v);
          hooks.invalidate();
        }
      },
    );
  }

  List<String> _checks(A2UIComponent c, _Ctx ctx) =>
      evaluateChecks(c['checks'], ctx.dc, _report);

  _Node _label(String text, [String? color]) => _textNode(
      text,
      _st({
        'fontSize': 12,
        'fontWeight': 500,
        'color': color ?? palette.onSurfaceVariant,
        'margin': '0 0 2 0',
      }));

  List<_Node> _errorText(List<String> messages) => messages.isNotEmpty
      ? [
          _textNode(
              messages.first,
              _st({
                'fontSize': 12,
                'color': palette.error,
                'margin': '4 0 0 0'
              }))
        ]
      : const [];

  bool _touched(String key) =>
      options.state.get<bool>(_stateKey(key, 'touched'), false);

  void _touch(String key) => options.state.set(_stateKey(key, 'touched'), true);

  _Node _button(A2UIComponent c, String key, _Ctx ctx) {
    final variant = c['variant'] is String ? c['variant'] as String : 'default';
    final p = palette;
    final failures = _checks(c, ctx);
    final press = ctx.interceptPress;
    final enabled = press != null || failures.isEmpty;
    final contentColor = variant == 'primary' ? p.onPrimary : p.primary;
    final childNode = c['child'] is String
        ? child(
            c['child'] as String,
            ctx.copy(
                parent: 'Button',
                contentColor: contentColor,
                interceptPress: null))
        : _textNode('', _st({}));
    final childComponent =
        c['child'] is String ? surface.components[c['child']] : null;
    final label = _accessibilityLabel(c, ctx) ??
        (childComponent?['component'] == 'Text'
            ? plainText(parseMarkdown(_str(ctx, childComponent!['text'])))
            : '');
    final Map<String, dynamic> style = variant == 'primary'
        ? {
            'backgroundColor': p.primary,
            'color': p.onPrimary,
            'margin': _leafMargin,
          }
        : variant == 'borderless'
            ? {
                'backgroundColor': 'transparent',
                'color': p.primary,
                'boxShadow': '0 0 0 0 rgba(0,0,0,0)',
                'padding': '0 12',
                'margin': _leafMargin,
              }
            : {
                'backgroundColor': p.surfaceContainer,
                'color': p.primary,
                'border': '1px solid ${p.outlineVariant}',
                'margin': _leafMargin,
              };
    final events = enabled
        ? <String, dynamic>{
            'click': (ElpianEvent e) {
              _handled(e);
              if (press != null) {
                press();
              } else {
                hooks.action(surface.id, '${c['id']}', c['action'], ctx.scope);
              }
            },
          }
        : null;
    return _el(
        'Button',
        {
          'text': label.isEmpty ? 'Button' : label,
          'disabled': !enabled,
          'style': style,
        },
        [childNode],
        key,
        events);
  }

  _Node _textField(A2UIComponent c, String key, _Ctx ctx) {
    final variant =
        c['variant'] is String ? c['variant'] as String : 'shortText';
    final label = _str(ctx, c['label']);
    final bind = _binding(c['value'], ctx, key);
    final raw = bind.read(isBinding(c['value']) ? null : _str(ctx, c['value']));
    final value = stringifyValue(raw);
    var failures = _checks(c, ctx);
    final pattern = c['validationRegexp'];
    if (pattern is String && value.isNotEmpty) {
      var ok = true;
      try {
        ok = RegExp(pattern).hasMatch(value);
      } catch (_) {
        ok = true;
      }
      if (!ok) failures = [...failures, 'Invalid format'];
    }
    final showErrors =
        failures.isNotEmpty && (_touched(key) || value.isNotEmpty);
    final p = palette;
    final a11y = _accessibilityLabel(c, ctx);
    final field = _el(
        'TextField',
        {
          'value': value,
          'hint': a11y != null && label.isEmpty ? a11y : '',
          'obscureText': variant == 'obscured',
          'multiline': variant == 'longText',
          'maxLines': variant == 'longText' ? 4 : 1,
          'keyboardType': variant == 'number' ? 'number' : 'text',
          'style': _st({'color': p.onSurface}),
        },
        const [],
        '$key/input',
        {
          'input': (ElpianEvent e) {
            _handled(e);
            _touch(key);
            bind.write('${eventValue(e) ?? ''}');
          },
        });
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
        },
        [
          if (label.isNotEmpty) _label(label, showErrors ? p.error : null),
          field,
          ..._errorText(showErrors ? failures : const []),
        ],
        key);
  }

  _Node _checkBox(A2UIComponent c, String key, _Ctx ctx) {
    final bind = _binding(c['value'], ctx, key);
    final checked = isBinding(c['value'])
        ? bind.read(false) == true
        : bind.read(_eval(ctx, () => ctx.dc.boolean(c['value']), false)) ==
            true;
    void toggle(bool v) {
      _touch(key);
      bind.write(v);
    }

    final failures = _checks(c, ctx);
    final showErrors = failures.isNotEmpty && _touched(key);
    final box = _el(
        'Checkbox',
        {
          'value': checked,
          'style': _st({'color': palette.primary}),
        },
        const [],
        '$key/box',
        {
          'change': (ElpianEvent e) {
            _handled(e);
            toggle(eventValue(e) == true);
          },
        });
    final labelNode = _el(
        'Container',
        {
          'style': _st({'cursor': 'pointer', 'padding': '0 4'})
        },
        [
          _textNode(_str(ctx, c['label']), _st({'fontSize': 16}))
        ],
        '$key/label',
        {
          'click': (ElpianEvent e) {
            _handled(e);
            toggle(!checked);
          },
        });
    final row = _el('Row', {
      'style': _st({'alignItems': 'center'})
    }, [
      box,
      _el('Flexible', {'flex': 1, 'fit': 'loose'}, [labelNode]),
    ]);
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
        },
        [row, ..._errorText(showErrors ? failures : const [])],
        key);
  }

  _Node _choicePicker(A2UIComponent c, String key, _Ctx ctx) {
    final p = palette;
    final multiple = c['variant'] == 'multipleSelection';
    final chips = c['displayStyle'] == 'chips';
    final bind = _binding(c['value'], ctx, key);
    final current = bind.read(isBinding(c['value'])
        ? null
        : _eval<List<String>>(ctx, () => ctx.dc.stringList(c['value']), []));
    final selected = current is List
        ? current.map(stringifyValue).toList()
        : current is String && current.isNotEmpty
            ? [current]
            : <String>[];
    final options = (c['options'] is List ? c['options'] as List : const [])
        .whereType<Map>()
        .where((o) => o['value'] is String)
        .map((o) {
      final value = o['value'] as String;
      final label = _str(ctx, o['label']);
      return (value: value, label: label.isEmpty ? value : label);
    }).toList();
    final filterKey = _stateKey(key, 'filter');
    final filter = c['filterable'] == true
        ? this.options.state.get<String>(filterKey, '')
        : '';
    final visible = filter.isNotEmpty
        ? options
            .where((o) => o.label.toLowerCase().contains(filter.toLowerCase()))
            .toList()
        : options;
    void choose(String value) {
      _touch(key);
      if (multiple) {
        bind.write(selected.contains(value)
            ? selected.where((v) => v != value).toList()
            : [...selected, value]);
      } else {
        bind.write([value]);
      }
    }

    final parts = <_Node>[];
    final label = _str(ctx, c['label']);
    if (label.isNotEmpty) parts.add(_label(label));
    if (c['filterable'] == true) {
      parts.add(_el(
          'TextField',
          {
            'value': filter,
            'hint': 'Filter options',
            'style': _st({'color': p.onSurface}),
          },
          const [],
          '$key/filter',
          {
            'input': (ElpianEvent e) {
              _handled(e);
              this.options.state.set(filterKey, '${eventValue(e) ?? ''}');
              hooks.invalidate();
            },
          }));
    }
    if (chips) {
      final items = visible.map((o) {
        final on = selected.contains(o.value);
        final content = <_Node>[
          if (on)
            _el('Icon', {
              'icon': 'check',
              'size': 18.0,
              'style': _st({'color': p.primary, 'margin': '0 6 0 0'}),
            }),
          _textNode(
              o.label,
              _st({
                'fontSize': 14,
                'fontWeight': 500,
                'color': on ? p.onSurface : p.onSurfaceVariant,
              })),
        ];
        return _el(
            'Container',
            {
              'style': _st({
                'padding': '6 14',
                'margin': 4,
                'borderRadius': 8,
                'border': '1px solid ${on ? p.primary : p.outline}',
                'backgroundColor': on ? p.primaryContainer : 'transparent',
                'cursor': 'pointer',
              })
            },
            [
              _el(
                  'Row',
                  {
                    'style': _st({'alignItems': 'center'})
                  },
                  content)
            ],
            '$key/opt/${o.value}',
            {
              'click': (ElpianEvent e) {
                _handled(e);
                choose(o.value);
              },
            });
      }).toList();
      parts.add(_el(
          'Wrap',
          {
            'style': _st({'gap': 0})
          },
          items));
    } else {
      for (final o in visible) {
        final on = selected.contains(o.value);
        final Map<String, dynamic> handlers = {
          'change': (ElpianEvent e) {
            _handled(e);
            choose(o.value);
          },
        };
        final control = multiple
            ? _el(
                'Checkbox',
                {
                  'value': on,
                  'style': _st({'color': p.primary}),
                },
                const [],
                '$key/opt/${o.value}',
                handlers)
            : _el(
                'Radio',
                {
                  'value': o.value,
                  'groupValue': selected.isEmpty ? null : selected.first,
                  'style': _st({'color': p.primary}),
                },
                const [],
                '$key/opt/${o.value}',
                handlers);
        final text = _el(
            'Container',
            {
              'style': _st({'cursor': 'pointer', 'padding': '0 4'})
            },
            [
              _textNode(o.label, _st({'fontSize': 16}))
            ],
            '$key/optlabel/${o.value}',
            {
              'click': (ElpianEvent e) {
                _handled(e);
                choose(o.value);
              },
            });
        parts.add(_el('Row', {
          'style': _st({'alignItems': 'center'})
        }, [
          control,
          _el('Flexible', {'flex': 1, 'fit': 'loose'}, [text]),
        ]));
      }
    }
    final failures = _checks(c, ctx);
    parts.addAll(
        _errorText(failures.isNotEmpty && _touched(key) ? failures : const []));
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
        },
        parts,
        key);
  }

  _Node _slider(A2UIComponent c, String key, _Ctx ctx) {
    final p = palette;
    final num min = c['min'] is num ? c['min'] as num : 0;
    final num max = c['max'] is num && (c['max'] as num) > min
        ? c['max'] as num
        : min + 100;
    final bind = _binding(c['value'], ctx, key);
    final raw = bind.read(isBinding(c['value'])
        ? null
        : _eval<num?>(ctx, () => ctx.dc.number(c['value']), min));
    final n = toNum(raw) ?? min;
    final value = n < min ? min : (n > max ? max : n);
    final label = _str(ctx, c['label']);
    final shown = value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed((max - min).abs() <= 1 ? 2 : 1);
    final header = _el('Row', {
      'style': _st({
        'alignItems': 'center',
        'justifyContent': 'space-between',
      })
    }, [
      _el('Flexible', {
        'flex': 1,
        'fit': 'loose'
      }, [
        _textNode(label, _st({'fontSize': 14, 'color': p.onSurfaceVariant}))
      ]),
      _textNode(shown,
          _st({'fontSize': 14, 'fontWeight': 600, 'color': p.onSurface})),
    ]);
    final slider = _el(
        'Slider',
        {
          'min': min.toDouble(),
          'max': max.toDouble(),
          'value': value.toDouble(),
          'style': _st({'color': p.primary}),
        },
        const [],
        '$key/slider',
        {
          'change': (ElpianEvent e) {
            _handled(e);
            final v = toNum(eventValue(e));
            if (v != null) bind.write(v == v.roundToDouble() ? v.round() : v);
          },
        });
    final failures = _checks(c, ctx);
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
        },
        [header, slider, ..._errorText(failures)],
        key);
  }

  _Node _dateTime(A2UIComponent c, String key, _Ctx ctx) {
    final p = palette;
    final enableDate = c['enableDate'] == true;
    final enableTime = c['enableTime'] == true;
    final mode = enableDate && enableTime
        ? 'datetime-local'
        : enableTime
            ? 'time'
            : enableDate
                ? 'date'
                : 'datetime-local';
    final bind = _binding(c['value'], ctx, key);
    final iso = stringifyValue(
        bind.read(isBinding(c['value']) ? null : _str(ctx, c['value'])));
    final label = _str(ctx, c['label']);
    String? bound(Object? v) {
      if (v == null) return null;
      final s = isoToInput(_str(ctx, v), mode);
      return s.isEmpty ? null : s;
    }

    final field = _el(
        'TextField',
        {
          'value': isoToInput(iso, mode),
          'keyboardType': mode,
          'min': bound(c['min']),
          'max': bound(c['max']),
          'style': _st({'color': p.onSurface}),
        },
        const [],
        '$key/input',
        {
          'input': (ElpianEvent e) {
            _handled(e);
            _touch(key);
            bind.write(inputToIso('${eventValue(e) ?? ''}', mode));
          },
        });
    final failures = _checks(c, ctx);
    return _el(
        'Column',
        {
          'style': _st({'alignItems': 'stretch', 'margin': _leafMargin})
        },
        [
          if (label.isNotEmpty) _label(label),
          field,
          ..._errorText(
              failures.isNotEmpty && _touched(key) ? failures : const []),
        ],
        key);
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

final RegExp _timePrefix = RegExp(r'^(\d{2}):(\d{2})');
final RegExp _dateOnlyIso = RegExp(r'^(\d{4}-\d{2}-\d{2})$');
final RegExp _localIso =
    RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$');

/// ISO 8601 (model) → the value a date / time / datetime-local input shows.
String isoToInput(String iso, String mode) {
  if (iso.isEmpty) return '';
  final s = iso.trim();
  final time = _timePrefix.firstMatch(s);
  if (mode == 'time' && time != null) return '${time[1]}:${time[2]}';
  final dateOnly = _dateOnlyIso.firstMatch(s);
  if (dateOnly != null) {
    return mode == 'time'
        ? ''
        : mode == 'date'
            ? dateOnly[1]!
            : '${dateOnly[1]}T00:00';
  }
  final local = _localIso.firstMatch(s);
  if (local != null) {
    if (mode == 'date') return local[1]!;
    if (mode == 'time') return '${local[2]}:${local[3]}';
    return '${local[1]}T${local[2]}:${local[3]}';
  }
  final d = DateTime.tryParse(s)?.toLocal();
  if (d == null) return '';
  final date =
      '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}';
  final t = '${_pad2(d.hour)}:${_pad2(d.minute)}';
  return mode == 'date'
      ? date
      : mode == 'time'
          ? t
          : '${date}T$t';
}

/// An input's value → ISO 8601 for the data model.
String inputToIso(String value, String mode) {
  final v = value.trim();
  if (v.isEmpty) return '';
  if (mode == 'time') return RegExp(r'^\d{2}:\d{2}$').hasMatch(v) ? '$v:00' : v;
  if (mode == 'datetime-local') {
    return RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$').hasMatch(v) ? '$v:00' : v;
  }
  return v;
}
