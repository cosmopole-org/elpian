import 'package:flutter/material.dart';

import '../core/elpian_engine.dart';
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

  Widget _buildNextjsLink(ElpianNode node, List<Widget> children) {
    final href = node.props['href']?.toString();
    final replace = node.props['replace'] == true;
    final label = node.props['text']?.toString() ?? href ?? 'Navigate';

    if (children.isNotEmpty) {
      return TextButton(
        onPressed: href == null ? null : () => _onNavigate?.call(href, replace: replace),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
    }

    return TextButton(
      onPressed: href == null ? null : () => _onNavigate?.call(href, replace: replace),
      child: Text(label),
    );
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

class _NextjsFormWidgetState extends State<_NextjsFormWidget> {
  final Map<String, TextEditingController> _controllers = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final name = f['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      _controllers[name] = TextEditingController(text: f['value']?.toString() ?? '');
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
    final values = <String, dynamic>{};
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
    final children = <Widget>[];
    for (final f in widget.fields) {
      final name = f['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final isPassword = (f['type']?.toString() ?? '') == 'password';
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _controllers[name],
          obscureText: isPassword,
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(
            hintText: f['placeholder']?.toString() ?? name,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ));
    }
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
      ));
    }
    children.add(SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(widget.submitLabel),
      ),
    ));
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
