import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/elpian_engine.dart';
import '../css/css_parser.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';
import '../models/elpian_node.dart';

typedef NextjsNavigate = void Function(String route, {bool replace});

/// Submit a `NextjsForm` to an action route. Returns an error message to show
/// inline, or null on success (the widget will have applied any navigation).
typedef NextjsSubmit = Future<String?> Function(
  String action,
  Map<String, dynamic> values,
);

/// Structured response that a Next.js server can return for Elpian clients.
class NextjsRenderEnvelope {
  const NextjsRenderEnvelope({
    required this.component,
    this.stylesheet,
    this.meta,
    this.navigation,
    this.clientComponents,
    this.jsCode,
    this.vmAstJson,
    this.jsEntryFunction,
  });

  final Map<String, dynamic> component;
  final Map<String, dynamic>? stylesheet;
  final Map<String, dynamic>? meta;
  final Map<String, dynamic>? navigation;
  final Map<String, dynamic>? clientComponents;

  /// Optional JavaScript source (QuickJS) to execute on client.
  final String? jsCode;

  /// Optional Elpian VM AST JSON to execute on client.
  final String? vmAstJson;

  /// Optional JS entry function name (defaults to MainComponent).
  final String? jsEntryFunction;

  factory NextjsRenderEnvelope.fromJson(Map<String, dynamic> json) {
    final componentRaw = json['component'];
    if (componentRaw is! Map<String, dynamic>) {
      throw const FormatException(
        'Next.js payload must contain a "component" object that matches Elpian JSON.',
      );
    }

    final stylesheetRaw = json['stylesheet'];
    if (stylesheetRaw != null && stylesheetRaw is! Map<String, dynamic>) {
      throw const FormatException('"stylesheet" must be a JSON object when provided.');
    }

    final metaRaw = json['meta'];
    if (metaRaw != null && metaRaw is! Map<String, dynamic>) {
      throw const FormatException('"meta" must be a JSON object when provided.');
    }

    final navigationRaw = json['navigation'];
    if (navigationRaw != null && navigationRaw is! Map<String, dynamic>) {
      throw const FormatException('"navigation" must be a JSON object when provided.');
    }

    final clientComponentsRaw = json['clientComponents'];
    if (clientComponentsRaw != null && clientComponentsRaw is! Map<String, dynamic>) {
      throw const FormatException('"clientComponents" must be a JSON object when provided.');
    }

    final jsCodeRaw = json['jsCode'];
    if (jsCodeRaw != null && jsCodeRaw is! String) {
      throw const FormatException('"jsCode" must be a string when provided.');
    }

    final vmAstRaw = json['vmAstJson'];
    if (vmAstRaw != null && vmAstRaw is! String) {
      throw const FormatException('"vmAstJson" must be a string when provided.');
    }

    final jsEntryRaw = json['jsEntryFunction'];
    if (jsEntryRaw != null && jsEntryRaw is! String) {
      throw const FormatException('"jsEntryFunction" must be a string when provided.');
    }

    return NextjsRenderEnvelope(
      component: componentRaw,
      stylesheet: stylesheetRaw,
      meta: metaRaw,
      navigation: navigationRaw,
      clientComponents: clientComponentsRaw,
      jsCode: jsCodeRaw,
      vmAstJson: vmAstRaw,
      jsEntryFunction: jsEntryRaw,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'component': component,
      if (stylesheet != null) 'stylesheet': stylesheet,
      if (meta != null) 'meta': meta,
      if (navigation != null) 'navigation': navigation,
      if (clientComponents != null) 'clientComponents': clientComponents,
      if (jsCode != null) 'jsCode': jsCode,
      if (vmAstJson != null) 'vmAstJson': vmAstJson,
      if (jsEntryFunction != null) 'jsEntryFunction': jsEntryFunction,
    };
  }
}

/// Lightweight bridge for Next.js server-driven rendering with Elpian.
class NextjsBridge {
  NextjsBridge({
    ElpianEngine? engine,
    NextjsNavigate? onNavigate,
    NextjsSubmit? onSubmit,
  })  : _engine = engine ?? ElpianEngine(),
        _onNavigate = onNavigate,
        _onSubmit = onSubmit {
    _registerNavigationWidgets();
  }

  final ElpianEngine _engine;
  NextjsNavigate? _onNavigate;
  NextjsSubmit? _onSubmit;

  ElpianEngine get engine => _engine;

  set onNavigate(NextjsNavigate? handler) {
    _onNavigate = handler;
  }

  set onSubmit(NextjsSubmit? handler) {
    _onSubmit = handler;
  }

  void _registerNavigationWidgets() {
    _engine.registerWidget('NextjsLink', _buildNextjsLink);
    _engine.registerWidget('next-link', _buildNextjsLink);
    _engine.registerWidget('NextjsForm', _buildNextjsForm);
    _engine.registerWidget('nextjs-form', _buildNextjsForm);
  }

  /// Server-driven form: renders input fields + a submit button and POSTs the
  /// collected values to `action`, letting the widget handle auth + navigation.
  ///
  /// Node shape:
  /// ```json
  /// { "type": "NextjsForm", "props": {
  ///     "action": "/auth/signin",
  ///     "submitLabel": "Sign In",
  ///     "fields": [
  ///       { "name": "email", "placeholder": "Email" },
  ///       { "name": "password", "placeholder": "Password", "type": "password" }
  ///     ]
  /// } }
  /// ```
  ///
  /// Field `type` selects the rendered control:
  ///  - `text` (default), `password`, `textarea`, `number` — text inputs
  ///    (`number` gets a numeric keyboard and digit filtering);
  ///  - `select` — a dropdown over `options` (a list of strings or
  ///    `{ "value", "label" }` maps);
  ///  - `checkbox` — a toggle submitting `"true"`/`"false"`;
  ///  - `range` — a slider over `min`/`max`/`step`;
  ///  - `hidden` — never rendered; its `value` is submitted as-is.
  Widget _buildNextjsForm(ElpianNode node, List<Widget> children) {
    final props = node.props;
    final action = props['action']?.toString() ?? '';
    final submitLabel = props['submitLabel']?.toString() ?? 'Submit';
    final rawFields = props['fields'];
    final fields = <Map<String, dynamic>>[];
    if (rawFields is List) {
      for (final f in rawFields) {
        if (f is Map) fields.add(Map<String, dynamic>.from(f));
      }
    }
    return _NextjsFormWidget(
      action: action,
      submitLabel: submitLabel,
      fields: fields,
      onSubmit: _onSubmit,
    );
  }

  /// A `NextjsLink` is the game's primary actionable element: most "buttons"
  /// are links that re-fetch a route. The engine has already resolved the
  /// node's `className`/inline `style` into [ElpianNode.style] (e.g. the shared
  /// `.btn`/`.btn-primary` rules), so we honour it exactly like `div`/`button`
  /// do — otherwise every styled button would fall back to a bare, default
  /// `TextButton` and the whole UI looks unstyled. The label/children are
  /// painted with the resolved background/gradient/border/radius/padding, then
  /// wrapped in a tap target.
  Widget _buildNextjsLink(ElpianNode node, List<Widget> children) {
    final href = node.props['href']?.toString();
    final replace = node.props['replace'] == true;
    final label = node.props['text']?.toString() ?? href ?? 'Navigate';
    final style = node.style;
    final enabled = href != null;

    final ariaLabel = node.props['ariaLabel']?.toString();

    // The element is "button-like" when it carries any container styling
    // (background, gradient, border or padding); otherwise it is a plain
    // inline text link and should read as one (accent colour + pointer).
    final isButtonLike = style != null &&
        (style.backgroundColor != null ||
            style.gradient != null ||
            style.border != null ||
            style.borderColor != null ||
            style.padding != null);

    Widget content;
    if (children.isNotEmpty) {
      content = _layoutLinkChildren(node, children);
    } else {
      content = Text(
        label,
        textAlign: style?.textAlign ?? (isButtonLike ? TextAlign.center : TextAlign.start),
        style: TextStyle(
          // Default to a gold accent so an unstyled link still reads as a link.
          color: style?.color ?? const Color(0xFFD6B36A),
          fontSize: style?.fontSize,
          fontWeight: style?.fontWeight ?? (isButtonLike ? FontWeight.w700 : null),
          letterSpacing: style?.letterSpacing,
        ),
      );
    }

    // Apply the resolved CSS (gradient/background/border/radius/padding/size/…)
    // through the same helper every styled element uses. `applyFlex: false`:
    // we wrap the result in interaction widgets below, so a `flex` style must
    // be re-applied as the OUTERMOST widget (see end of method) — otherwise the
    // Flexible would be buried beneath GestureDetector and Flutter throws
    // "Incorrect use of ParentDataWidget" whenever the link sits in a Row/Column
    // (e.g. the flex:1 Sign In/Sign Up tabs), crashing the whole subtree.
    Widget styled = CSSProperties.applyStyle(content, style, applyFlex: false);

    Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // `href == null` (not the `enabled` alias) so Dart promotes `href` to a
      // non-null `String` inside the navigate closure.
      onTap: href == null ? null : () => _onNavigate?.call(href, replace: replace),
      child: styled,
    );

    tappable = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: tappable,
    );

    if (ariaLabel != null && ariaLabel.isNotEmpty) {
      tappable = Semantics(button: true, label: ariaLabel, child: tappable);
    }

    // Re-apply flex outermost so the Flexible is a direct child of the parent
    // Row/Column (the whole tappable box still flexes and stays clickable).
    // CSS `flex:<n>` grows to fill its share, so use a TIGHT fit (Expanded) —
    // this is what makes equal-width segmented controls (the Sign In/Sign Up
    // tabs, the leaderboard toggles) actually fill their half and centre.
    final linkFlex = style?.flex ?? style?.flexGrow;
    if (linkFlex != null) {
      tappable = Flexible(
        flex: linkFlex,
        fit: FlexFit.tight,
        child: SizedBox(width: double.infinity, child: tappable),
      );
    }

    return tappable;
  }

  /// Lay out a `NextjsLink`'s children for its content box. A bare icon button
  /// is one centred glyph (the [CSSProperties.applyStyle] flex-centring handles
  /// the actual centring once this returns a single child). When a child is
  /// `position:absolute` — the notification badge on the battles/menu icons —
  /// it is lifted out of flow and overlaid in a [Stack] so the glyph stays
  /// centred and the badge floats at its corner, instead of sitting inline and
  /// shoving the glyph off-centre. Mirrors the CSS semantics `HtmlDiv` already
  /// applies; without it links never honoured `position` on their children.
  Widget _layoutLinkChildren(ElpianNode node, List<Widget> children) {
    // Pair each built child widget with its source node's resolved style so we
    // can read `position`/offsets. Falls back gracefully when they don't align.
    final nodes = node.children;
    final aligned = nodes.length == children.length;

    final flow = <Widget>[];
    final overlays = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final childStyle = aligned ? _linkChildStyle(nodes[i]) : null;
      final pos = childStyle?.position;
      if ((pos == 'absolute' || pos == 'fixed') && childStyle != null) {
        overlays.add(Positioned(
          top: childStyle.top,
          left: childStyle.left,
          right: childStyle.right,
          bottom: childStyle.bottom,
          child: children[i],
        ));
      } else {
        flow.add(children[i]);
      }
    }

    final base = flow.isEmpty
        ? const SizedBox.shrink()
        : flow.length == 1
            ? flow.first
            : _linkFlow(node, flow);

    if (overlays.isEmpty) return base;
    // Clip.none: badges intentionally poke past the button's rounded corners.
    return Stack(
      clipBehavior: Clip.none,
      children: [base, ...overlays],
    );
  }

  /// Lay a link's in-flow children out per the link's OWN flex styles. Most
  /// game "buttons" are `NextjsLink`s styled `display:flex` with a `gap` and
  /// centring (`justifyContent`/`alignItems`) — a bare default [Row] dropped
  /// all of that, so a glyph + label rendered squashed together and
  /// mis-aligned (most visibly in the mobile navbar / menu buttons).
  Widget _linkFlow(ElpianNode node, List<Widget> flow) {
    final style = node.style;
    final direction = style?.flexDirection;
    final isColumn = direction == 'column' || direction == 'column-reverse';
    final gap = style?.gap ?? 0;
    final children = _withGaps(
      flow,
      gap,
      isColumn ? Axis.vertical : Axis.horizontal,
    );
    final mainAlign =
        CSSProperties.getMainAxisAlignment(style?.justifyContent);
    // Default the cross axis to CENTER — the [Row] default these buttons were
    // built against (and the sensible default for a button's content box) —
    // honouring an explicit `alignItems` when one is set.
    final crossAlign = style?.alignItems == null
        ? CrossAxisAlignment.center
        : CSSProperties.getCrossAxisAlignment(style?.alignItems);
    return isColumn
        ? Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: mainAlign,
            crossAxisAlignment: crossAlign,
            children: children,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: mainAlign,
            crossAxisAlignment: crossAlign,
            children: children,
          );
  }

  /// Interleave fixed [gap] spacers between [children] along [axis].
  List<Widget> _withGaps(List<Widget> children, double gap, Axis axis) {
    if (gap <= 0 || children.length <= 1) return children;
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) {
        spaced.add(SizedBox(
          width: axis == Axis.horizontal ? gap : 0,
          height: axis == Axis.vertical ? gap : 0,
        ));
      }
    }
    return spaced;
  }

  /// Resolve a link child's inline style (the raw `style` map the builders emit)
  /// into a [CSSStyle] so its `position`/offsets can be read. Prefers the
  /// pre-parsed [ElpianNode.style], falling back to parsing `props['style']`.
  CSSStyle? _linkChildStyle(ElpianNode child) {
    if (child.style != null) return child.style;
    final inline = child.props['style'];
    if (inline is Map<String, dynamic>) return CSSParser.parse(inline);
    return null;
  }

  Widget renderEnvelope(Map<String, dynamic> envelopeJson) {
    return renderParsedEnvelope(NextjsRenderEnvelope.fromJson(envelopeJson));
  }

  Widget renderParsedEnvelope(NextjsRenderEnvelope envelope) {
    return _engine.renderWithStylesheet(
      envelope.component,
      stylesheet: envelope.stylesheet,
    );
  }

  /// Render a full envelope as a SCREEN with browser `<body>` document
  /// semantics (tall content scrolls vertically; full-bleed stages stay
  /// pinned). This is what the host (`NextjsServerWidget`) mounts; use it
  /// instead of [renderEnvelope] when rendering a top-level route so over-tall
  /// screens stay reachable on short viewports.
  Widget renderDocument(Map<String, dynamic> envelopeJson) {
    final envelope = NextjsRenderEnvelope.fromJson(envelopeJson);
    final rendered = renderParsedEnvelope(envelope);
    return _engine.wrapAsDocument(rendered, envelope.component);
  }

  Widget renderComponent(Map<String, dynamic> componentJson) {
    return _engine.renderFromJson(componentJson);
  }

  static Map<String, dynamic> buildRouteRequest({
    required String route,
    Map<String, dynamic>? props,
    Map<String, dynamic>? context,
  }) {
    return {
      'route': route,
      if (props != null) 'props': props,
      if (context != null) 'context': context,
    };
  }
}

/// Stateful renderer for a `NextjsForm` node. Holds input values locally and
/// POSTs them through the bridge's `onSubmit` hook; shows the server's error
/// text inline and a spinner while submitting.
class _NextjsFormWidget extends StatefulWidget {
  const _NextjsFormWidget({
    required this.action,
    required this.submitLabel,
    required this.fields,
    required this.onSubmit,
  });

  final String action;
  final String submitLabel;
  final List<Map<String, dynamic>> fields;
  final NextjsSubmit? onSubmit;

  @override
  State<_NextjsFormWidget> createState() => _NextjsFormWidgetState();
}

/// A select-field choice: the submitted [value] plus the display [label].
class _FieldOption {
  const _FieldOption(this.value, this.label);
  final String value;
  final String label;
}

class _NextjsFormWidgetState extends State<_NextjsFormWidget> {
  /// Controllers for the typed (text-like) fields.
  final Map<String, TextEditingController> _controllers = {};

  /// Current values of the non-text controls (hidden/select/checkbox/range).
  final Map<String, String> _values = {};

  bool _busy = false;
  String? _error;

  static String _fieldType(Map<String, dynamic> f) =>
      f['type']?.toString() ?? '';

  static String _fieldName(Map<String, dynamic> f) =>
      f['name']?.toString() ?? '';

  /// Whether the field is collected through a [TextEditingController].
  static bool _isTextLike(String type) =>
      type != 'hidden' && type != 'select' && type != 'checkbox' && type != 'range';

  /// Parse a select field's options: a list of strings or `{value,label}`
  /// maps. Falls back to splitting a comma-separated `placeholder` so legacy
  /// servers that crammed the choices into the hint still get a dropdown.
  static List<_FieldOption> _optionsOf(Map<String, dynamic> f) {
    final out = <_FieldOption>[];
    final raw = f['options'];
    if (raw is List) {
      for (final o in raw) {
        if (o is Map) {
          final v = (o['value'] ?? o['label'] ?? '').toString();
          out.add(_FieldOption(v, (o['label'] ?? v).toString()));
        } else if (o != null) {
          out.add(_FieldOption(o.toString(), o.toString()));
        }
      }
    }
    if (out.isEmpty) {
      final placeholder = f['placeholder']?.toString() ?? '';
      for (final part in placeholder.split(',')) {
        final v = part.trim();
        if (v.isNotEmpty) out.add(_FieldOption(v, v));
      }
    }
    return out;
  }

  static double _numProp(Map<String, dynamic> f, String key, double fallback) {
    final v = f[key];
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(v?.toString() ?? '');
    return parsed ?? fallback;
  }

  /// Format a slider value for display/submission (drop a trailing `.0`).
  static String _fmtRange(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final name = _fieldName(f);
      if (name.isEmpty) continue;
      final type = _fieldType(f);
      final value = f['value']?.toString() ?? '';
      if (_isTextLike(type)) {
        _controllers[name] = TextEditingController(text: value);
      } else if (type == 'select') {
        final options = _optionsOf(f);
        final valid = options.any((o) => o.value == value);
        _values[name] =
            valid ? value : (options.isNotEmpty ? options.first.value : value);
      } else if (type == 'checkbox') {
        _values[name] = (value == 'true' || value == 'on') ? 'true' : 'false';
      } else if (type == 'range') {
        final min = _numProp(f, 'min', 0);
        final max = _numProp(f, 'max', 100);
        final initial = max > min
            ? (double.tryParse(value) ?? min).clamp(min, max)
            : min;
        _values[name] = _fmtRange(initial.toDouble());
      } else {
        // hidden — submit the server-provided value untouched.
        _values[name] = value;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.onSubmit == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final values = <String, dynamic>{..._values};
    _controllers.forEach((k, v) => values[k] = v.text);
    String? error;
    try {
      error = await widget.onSubmit!(widget.action, values);
    } catch (e) {
      error = 'Request failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nautical/gold theme tokens (shared with the JSON stylesheet) so inputs
    // sit on the navy glass panels instead of rendering as bright default
    // Material fields.
    const fieldFill = Color(0xFF0A1626);
    const fieldBorder = Color(0xFF1C3450);
    const fieldBorderFocus = Color(0xFFD6B36A);
    const textColor = Color(0xFFF7EEDC);
    const hintColor = Color(0xFF6E8394);
    const gold = Color(0xFFD6B36A);

    OutlineInputBorder borderOf(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c, width: w),
        );

    InputDecoration decorationOf(Map<String, dynamic> f, String name) =>
        InputDecoration(
          hintText: f['placeholder']?.toString() ?? name,
          hintStyle: const TextStyle(color: hintColor, fontSize: 14),
          filled: true,
          fillColor: fieldFill,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: borderOf(fieldBorder),
          focusedBorder: borderOf(fieldBorderFocus, 1.5),
          border: borderOf(fieldBorder),
        );

    Widget labelOf(String label) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label,
              style: const TextStyle(
                  color: hintColor, fontSize: 11, fontWeight: FontWeight.w600)),
        );

    final children = <Widget>[];
    for (final f in widget.fields) {
      final name = _fieldName(f);
      if (name.isEmpty) continue;
      final type = _fieldType(f);
      if (type == 'hidden') continue;

      final label = f['label']?.toString();
      Widget control;

      if (type == 'select') {
        final options = _optionsOf(f);
        final current = options.any((o) => o.value == _values[name])
            ? _values[name]
            : (options.isNotEmpty ? options.first.value : null);
        // Same navy-glass DropdownButton treatment as `HtmlSelect` (a
        // DropdownButtonFormField would need the newest Flutter API).
        control = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: fieldBorder),
          ),
          child: DropdownButton<String>(
            value: current,
            isExpanded: true,
            isDense: true,
            dropdownColor: fieldFill,
            iconEnabledColor: gold,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: textColor, fontSize: 14),
            hint: Text(
              f['placeholder']?.toString() ?? name,
              style: const TextStyle(color: hintColor, fontSize: 14),
            ),
            items: [
              for (final o in options)
                DropdownMenuItem<String>(
                  value: o.value,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _values[name] = v ?? current ?? ''),
          ),
        );
      } else if (type == 'checkbox') {
        final checked = _values[name] == 'true';
        control = InkWell(
          onTap: _busy
              ? null
              : () =>
                  setState(() => _values[name] = checked ? 'false' : 'true'),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: fieldFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: fieldBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: checked,
                  activeColor: gold,
                  checkColor: const Color(0xFF06122A),
                  side: const BorderSide(color: hintColor),
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _values[name] = v == true ? 'true' : 'false'),
                ),
                Flexible(
                  child: Text(
                    f['placeholder']?.toString() ?? label ?? name,
                    style: const TextStyle(color: textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (type == 'range') {
        final min = _numProp(f, 'min', 0);
        final max = _numProp(f, 'max', 100);
        final step = _numProp(f, 'step', 1);
        // A degenerate range (no headroom) renders as a fixed-value readout —
        // a Slider with min == max cannot position its thumb.
        final hasRoom = max > min;
        final current = hasRoom
            ? (double.tryParse(_values[name] ?? '') ?? min).clamp(min, max)
            : min;
        final divisions =
            (step > 0 && hasRoom) ? ((max - min) / step).round() : null;
        control = Container(
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: fieldBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: hasRoom
                    ? SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: gold,
                          inactiveTrackColor: fieldBorder,
                          thumbColor: gold,
                          overlayColor: gold.withValues(alpha: 0.15),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: current.toDouble(),
                          min: min,
                          max: max,
                          divisions: divisions,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => _values[name] = _fmtRange(v)),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          f['placeholder']?.toString() ?? 'No range available',
                          style:
                              const TextStyle(color: hintColor, fontSize: 13),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                _values[name] ?? _fmtRange(current.toDouble()),
                style: const TextStyle(
                    color: gold, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      } else {
        final isPassword = type == 'password';
        final isMultiline = type == 'textarea';
        final isNumber = type == 'number';
        control = TextField(
          controller: _controllers[name],
          obscureText: isPassword,
          maxLines: isMultiline ? 4 : 1,
          minLines: isMultiline ? 3 : 1,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(
                  signed: true, decimal: true)
              : null,
          inputFormatters: isNumber
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
              : null,
          style: const TextStyle(color: textColor, fontSize: 14),
          cursorColor: gold,
          onSubmitted: isMultiline ? null : (_) => _busy ? null : _submit(),
          decoration: decorationOf(f, name),
        );
      }

      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null && label.isNotEmpty) labelOf(label),
            control,
          ],
        ),
      ));
    }
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFC0492F), fontSize: 13)),
      ));
    }
    children.add(SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF06122A),
          disabledBackgroundColor: gold.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        child: _busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF06122A)))
            : Text(widget.submitLabel),
      ),
    ));
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
