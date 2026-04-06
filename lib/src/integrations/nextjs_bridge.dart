import 'package:flutter/material.dart';

import '../core/elpian_engine.dart';
import '../models/elpian_node.dart';

typedef NextjsNavigate = void Function(String route, {bool replace});

/// Structured response that a Next.js server can return for Elpian clients.
class NextjsRenderEnvelope {
  const NextjsRenderEnvelope({
    required this.component,
    this.stylesheet,
    this.meta,
    this.navigation,
    this.jsCode,
    this.vmAstJson,
    this.jsEntryFunction,
  });

  final Map<String, dynamic> component;
  final Map<String, dynamic>? stylesheet;
  final Map<String, dynamic>? meta;
  final Map<String, dynamic>? navigation;

  /// Optional JavaScript source (QuickJS) to execute on client.
  final String? jsCode;

  /// Optional Elpian VM AST JSON to execute on client.
  final String? vmAstJson;

  /// Optional JS entry function name (defaults to MainComponent).
  final String? jsEntryFunction;

  factory NextjsRenderEnvelope.fromJson(Map<String, dynamic> json) {
    final componentRaw = json['component'];
    if (componentRaw is! Map<String, dynamic>) {
      throw FormatException(
        'Next.js payload must contain a "component" object that matches Elpian JSON.',
      );
    }

    final stylesheetRaw = json['stylesheet'];
    if (stylesheetRaw != null && stylesheetRaw is! Map<String, dynamic>) {
      throw FormatException('"stylesheet" must be a JSON object when provided.');
    }

    final metaRaw = json['meta'];
    if (metaRaw != null && metaRaw is! Map<String, dynamic>) {
      throw FormatException('"meta" must be a JSON object when provided.');
    }

    final navigationRaw = json['navigation'];
    if (navigationRaw != null && navigationRaw is! Map<String, dynamic>) {
      throw FormatException('"navigation" must be a JSON object when provided.');
    }

    final jsCodeRaw = json['jsCode'];
    if (jsCodeRaw != null && jsCodeRaw is! String) {
      throw FormatException('"jsCode" must be a string when provided.');
    }

    final vmAstRaw = json['vmAstJson'];
    if (vmAstRaw != null && vmAstRaw is! String) {
      throw FormatException('"vmAstJson" must be a string when provided.');
    }

    final jsEntryRaw = json['jsEntryFunction'];
    if (jsEntryRaw != null && jsEntryRaw is! String) {
      throw FormatException('"jsEntryFunction" must be a string when provided.');
    }

    return NextjsRenderEnvelope(
      component: componentRaw,
      stylesheet: stylesheetRaw,
      meta: metaRaw,
      navigation: navigationRaw,
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
  })  : _engine = engine ?? ElpianEngine(),
        _onNavigate = onNavigate {
    _registerNavigationWidgets();
  }

  final ElpianEngine _engine;
  NextjsNavigate? _onNavigate;

  ElpianEngine get engine => _engine;

  set onNavigate(NextjsNavigate? handler) {
    _onNavigate = handler;
  }

  void _registerNavigationWidgets() {
    _engine.registerWidget('NextjsLink', _buildNextjsLink);
    _engine.registerWidget('next-link', _buildNextjsLink);
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
