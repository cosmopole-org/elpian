import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';
import '../widgets/elpian_canvas_widget.dart';
import '../widgets/elpian_cached_canvas.dart';
import '../widgets/elpian_scope.dart';

// HTML Widgets

class ElpianEngine {
  final WidgetRegistry _registry = WidgetRegistry();
  final EventDispatcher _eventDispatcher = EventDispatcher();
  final GlobalStylesheetManager _stylesheetManager = GlobalStylesheetManager();
  String? _currentParentId;

  ElpianEngine() {
    _registerDefaultWidgets();
  }

  /// Set global event handler to receive all events
  void setGlobalEventHandler(ElpianEventListener handler) {
    _eventDispatcher.onGlobalEvent(handler);
  }

  /// Subscribe to specific event type
  void onEventType(ElpianEventType type, ElpianEventListener listener) {
    _eventDispatcher.onEventType(type, listener);
  }

  /// Get event dispatcher for advanced usage
  EventDispatcher get eventDispatcher => _eventDispatcher;

  /// Load JSON stylesheet
  void loadStylesheet(Map<String, dynamic> stylesheetJson) {
    final stylesheet = JsonStylesheetParser.parseJsonStylesheet(stylesheetJson);

    // Copy all rules to global stylesheet
    for (final rule in stylesheet.rules) {
      _stylesheetManager.global.addRule(rule.selector, rule.styles);
    }
  }

  /// Load stylesheet from builder
  void loadStylesheetFromBuilder(JsonStylesheetBuilder builder) {
    loadStylesheet(builder.build());
  }

  /// Get global stylesheet
  CSSStylesheet get globalStylesheet => _stylesheetManager.global;

  /// Clear all stylesheets
  void clearStylesheets() {
    _stylesheetManager.clear();
  }

  void _registerDefaultWidgets() {
    // Flutter widgets - Core
    _registry.register('Container', ElpianContainer.build);
    _registry.register('Text', ElpianText.build);
    _registry.register('Button', ElpianButton.build);
    _registry.register('Image', ElpianImage.build);
    _registry.register('Column', ElpianColumn.build);
    _registry.register('Row', ElpianRow.build);
    _registry.register('Stack', ElpianStack.build);
    _registry.register('Positioned', ElpianPositioned.build);
    _registry.register('Expanded', ElpianExpanded.build);
    _registry.register('Flexible', ElpianFlexible.build);
    _registry.register('Center', ElpianCenter.build);
    _registry.register('Padding', ElpianPadding.build);
    _registry.register('Align', ElpianAlign.build);
    _registry.register('SizedBox', ElpianSizedBox.build);
    _registry.register('ListView', ElpianListView.build);
    _registry.register('GridView', ElpianGridView.build);
    _registry.register('TextField', ElpianTextField.build);
    _registry.register('Checkbox', ElpianCheckbox.build);
    _registry.register('Radio', ElpianRadio.build);
    _registry.register('Switch', ElpianSwitch.build);
    _registry.register('Slider', ElpianSlider.build);
    _registry.register('Icon', ElpianIcon.build);
    _registry.register('Card', ElpianCard.build);
    _registry.register('Scaffold', ElpianScaffold.build);
    _registry.register('AppBar', ElpianAppBar.build);
    _registry.register('Canvas', ElpianCanvasWidget.build);
    _registry.register('CachedCanvas', ElpianCachedCanvas.build);
    _registry.register('Scope', ElpianScope.build);

    // Bevy 3D Scene Renderer
    _registry.register('BevyScene', BevySceneWidget.build);
    _registry.register('Bevy3D', BevySceneWidget.build);
    _registry.register('Scene3D', BevySceneWidget.build);

    // Pure-Dart 3D Game Scene Renderer
    _registry.register('GameScene', GameSceneWidget.build);
    _registry.register('Game3D', GameSceneWidget.build);

    // Flutter widgets - Additional
    _registry.register('Wrap', ElpianWrap.build);
    _registry.register('InkWell', ElpianInkWell.build);
    _registry.register('GestureDetector', ElpianGestureDetector.build);
    _registry.register('Opacity', ElpianOpacity.build);
    _registry.register('Transform', ElpianTransform.build);
    _registry.register('ClipRRect', ElpianClipRRect.build);
    _registry.register('ConstrainedBox', ElpianConstrainedBox.build);
    _registry.register('AspectRatio', ElpianAspectRatio.build);
    _registry.register('FractionallySizedBox', ElpianFractionallySizedBox.build);
    _registry.register('FittedBox', ElpianFittedBox.build);
    _registry.register('LimitedBox', ElpianLimitedBox.build);
    _registry.register('OverflowBox', ElpianOverflowBox.build);
    _registry.register('Baseline', ElpianBaseline.build);
    _registry.register('Spacer', ElpianSpacer.build);
    _registry.register('Divider', ElpianDivider.build);
    _registry.register('VerticalDivider', ElpianVerticalDivider.build);
    _registry.register('CircularProgressIndicator', ElpianCircularProgressIndicator.build);
    _registry.register('LinearProgressIndicator', ElpianLinearProgressIndicator.build);
    _registry.register('Tooltip', ElpianTooltip.build);
    _registry.register('Badge', ElpianBadge.build);
    _registry.register('Chip', ElpianChip.build);
    _registry.register('Dismissible', ElpianDismissible.build);
    _registry.register('Draggable', ElpianDraggable.build);
    _registry.register('DragTarget', ElpianDragTarget.build);
    _registry.register('Hero', ElpianHero.build);
    _registry.register('IndexedStack', ElpianIndexedStack.build);
    _registry.register('RotatedBox', ElpianRotatedBox.build);
    _registry.register('DecoratedBox', ElpianDecoratedBox.build);
    _registry.register('MathExpression', ElpianMathExpression.build);
    _registry.register('Math', ElpianMathExpression.build);

    // Animation widgets - Implicit
    _registry.register('AnimatedContainer', ElpianAnimatedContainer.build);
    _registry.register('AnimatedOpacity', ElpianAnimatedOpacity.build);
    _registry.register('AnimatedCrossFade', ElpianAnimatedCrossFade.build);
    _registry.register('AnimatedSwitcher', ElpianAnimatedSwitcher.build);
    _registry.register('AnimatedAlign', ElpianAnimatedAlign.build);
    _registry.register('AnimatedPadding', ElpianAnimatedPadding.build);
    _registry.register('AnimatedPositioned', ElpianAnimatedPositioned.build);
    _registry.register('AnimatedScale', ElpianAnimatedScale.build);
    _registry.register('AnimatedRotation', ElpianAnimatedRotation.build);
    _registry.register('AnimatedSlide', ElpianAnimatedSlide.build);
    _registry.register('AnimatedSize', ElpianAnimatedSize.build);
    _registry.register('AnimatedDefaultTextStyle', ElpianAnimatedDefaultTextStyle.build);

    // Animation widgets - Explicit
    _registry.register('FadeTransition', ElpianFadeTransition.build);
    _registry.register('SlideTransition', ElpianSlideTransition.build);
    _registry.register('ScaleTransition', ElpianScaleTransition.build);
    _registry.register('RotationTransition', ElpianRotationTransition.build);
    _registry.register('SizeTransition', ElpianSizeTransition.build);

    // Animation widgets - Custom
    _registry.register('TweenAnimationBuilder', ElpianTweenAnimationBuilder.build);
    _registry.register('StaggeredAnimation', ElpianStaggeredAnimation.build);
    _registry.register('Shimmer', ElpianShimmer.build);
    _registry.register('Pulse', ElpianPulse.build);
    _registry.register('AnimatedGradient', ElpianAnimatedGradient.build);

    // HTML widgets - Basic
    _registry.register('div', HtmlDiv.build);
    _registry.register('span', HtmlSpan.build);
    _registry.register('h1', HtmlH1.build);
    _registry.register('h2', HtmlH2.build);
    _registry.register('h3', HtmlH3.build);
    _registry.register('h4', HtmlH4.build);
    _registry.register('h5', HtmlH5.build);
    _registry.register('h6', HtmlH6.build);
    _registry.register('p', HtmlP.build);
    _registry.register('a', HtmlA.build);
    _registry.register('button', HtmlButton.build);
    _registry.register('input', HtmlInput.build);
    _registry.register('img', HtmlImg.build);
    _registry.register('ul', HtmlUl.build);
    _registry.register('ol', HtmlOl.build);
    _registry.register('li', HtmlLi.build);
    _registry.register('table', HtmlTable.build);
    _registry.register('tr', HtmlTr.build);
    _registry.register('td', HtmlTd.build);
    _registry.register('th', HtmlTh.build);
    _registry.register('form', HtmlForm.build);
    _registry.register('label', HtmlLabel.build);
    _registry.register('select', HtmlSelect.build);
    _registry.register('option', HtmlOption.build);
    _registry.register('textarea', HtmlTextarea.build);
    _registry.register('section', HtmlSection.build);
    _registry.register('article', HtmlArticle.build);
    _registry.register('header', HtmlHeader.build);
    _registry.register('footer', HtmlFooter.build);
    _registry.register('nav', HtmlNav.build);
    _registry.register('aside', HtmlAside.build);
    _registry.register('main', HtmlMain.build);
    _registry.register('video', HtmlVideo.build);
    _registry.register('audio', HtmlAudio.build);
    _registry.register('canvas', HtmlCanvas.build);
    _registry.register('iframe', HtmlIframe.build);
    _registry.register('strong', HtmlStrong.build);
    _registry.register('em', HtmlEm.build);
    _registry.register('code', HtmlCode.build);
    _registry.register('pre', HtmlPre.build);
    _registry.register('blockquote', HtmlBlockquote.build);
    _registry.register('hr', HtmlHr.build);
    _registry.register('br', HtmlBr.build);

    // HTML widgets - Extended
    _registry.register('figure', HtmlFigure.build);
    _registry.register('figcaption', HtmlFigcaption.build);
    _registry.register('mark', HtmlMark.build);
    _registry.register('del', HtmlDel.build);
    _registry.register('ins', HtmlIns.build);
    _registry.register('sub', HtmlSub.build);
    _registry.register('sup', HtmlSup.build);
    _registry.register('small', HtmlSmall.build);
    _registry.register('abbr', HtmlAbbr.build);
    _registry.register('cite', HtmlCite.build);
    _registry.register('kbd', HtmlKbd.build);
    _registry.register('samp', HtmlSamp.build);
    _registry.register('var', HtmlVar.build);
    _registry.register('details', HtmlDetails.build);
    _registry.register('summary', HtmlSummary.build);
    _registry.register('dialog', HtmlDialog.build);
    _registry.register('progress', HtmlProgress.build);
    _registry.register('meter', HtmlMeter.build);
    _registry.register('time', HtmlTime.build);
    _registry.register('data', HtmlData.build);
    _registry.register('output', HtmlOutput.build);
    _registry.register('fieldset', HtmlFieldset.build);
    _registry.register('legend', HtmlLegend.build);
    _registry.register('datalist', HtmlDatalist.build);
    _registry.register('optgroup', HtmlOptgroup.build);
    _registry.register('picture', HtmlPicture.build);
    _registry.register('source', HtmlSource.build);
    _registry.register('track', HtmlTrack.build);
    _registry.register('embed', HtmlEmbed.build);
    _registry.register('object', HtmlObject.build);
    _registry.register('param', HtmlParam.build);
    _registry.register('map', HtmlMap.build);
    _registry.register('area', HtmlArea.build);
  }

  Widget render(ElpianNode node, {String? parentId}) {
    final builder = _registry.get(node.type);

    if (builder == null) {
      debugPrint('Warning: Unknown widget type "${node.type}"');
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.withValues(alpha: 0.2),
        child: Text('Unknown widget: ${node.type}'),
      );
    }

    final inlineMap = node.props['style'] as Map<String, dynamic>?;

    // Resolve the full cascade in ONE place when the element carries an id or
    // classes, so `getComputedStyleMap` can apply CSS `!important` priority
    // across global rules, matching `@media` rules AND the inline styles
    // (important declarations must beat inline — e.g. the mobile `.game-window`
    // full-screen override beats the window's inline drag offset). Merging the
    // raw maps and parsing once is also lossless (the old CSSStyle round-trip
    // dropped most fields) and cheap (single memoized parse).
    CSSStyle? mergedStyle;
    if (node.key != null || node.props['className'] != null) {
      final classes = node.props['className'] is String
          ? (node.props['className'] as String).split(' ')
          : (node.props['className'] as List?)?.cast<String>();

      final computed = _stylesheetManager.getComputedStyleMap(
        tagName: node.type,
        id: node.key,
        classes: classes,
        inlineStyles: inlineMap,
      );
      if (computed.isNotEmpty) mergedStyle = CSSParser.parse(computed);
    } else if (inlineMap != null) {
      mergedStyle = CSSParser.parse(inlineMap);
    }

    // Create node with merged style
    ElpianNode nodeWithStyle = node;
    if (mergedStyle != null || node.style != null) {
      nodeWithStyle = node.copyWith(style: mergedStyle ?? node.style);
    }

    // CSS `display: none` removes the element from layout entirely. Checked on
    // the RESOLVED cascade so responsive rules work — e.g. a desktop-only
    // navbar cluster hidden by an `@media (max-width: …) { display: none }`
    // stylesheet rule, or shown again when the viewport grows.
    if (nodeWithStyle.style?.display == 'none') {
      return const SizedBox.shrink();
    }

    // Store current parent for child rendering
    final previousParentId = _currentParentId;
    _currentParentId = node.key;

    // Render children with parent ID
    final children = nodeWithStyle.children
        .map((child) => render(child, parentId: _currentParentId))
        .toList();

    // Restore previous parent
    _currentParentId = previousParentId;

    // Build the widget
    Widget result = builder(nodeWithStyle, children);

    final key = nodeWithStyle.key;

    // Wrap with event handling if node has events
    if (nodeWithStyle.events != null && nodeWithStyle.events!.isNotEmpty) {
      result = EventEnabledWidget(
        key: key == null ? null : ValueKey<String>(key),
        node: nodeWithStyle,
        parentId: parentId,
        child: result,
      );
    } else if (key != null && key.isNotEmpty) {
      result = KeyedSubtree(
        key: ValueKey<String>(key),
        child: result,
      );
    }

    return result;
  }

  Widget renderFromJson(Map<String, dynamic> json) {
    final node = ElpianNode.fromJson(json);
    return render(node);
  }

  /// Render with stylesheet
  Widget renderWithStylesheet(
    Map<String, dynamic> json, {
    Map<String, dynamic>? stylesheet,
  }) {
    if (stylesheet != null) {
      loadStylesheet(stylesheet);
    }
    return renderFromJson(json);
  }

  /// Wrap a rendered SCREEN ROOT with browser document semantics: it fills at
  /// least the viewport and scrolls vertically when its content is taller — the
  /// default `<body>` behaviour the bare engine lacked, so tall forms/panels
  /// (auth, the world side-panel, long lists) were clipped and unreachable on
  /// short screens with no way to scroll to them.
  ///
  /// A viewport-locked full-screen STAGE is left pinned (no scroll), because it
  /// intentionally owns the whole viewport and positions a HUD against its
  /// edges — scrolling it would detach the absolute navbar/dock. A root is
  /// treated as such a stage when it declares `position:fixed`, or a
  /// `height` of `100vh`/`100%` (the city/world shell stage). Everything else is
  /// a normal-flow document and becomes vertically scrollable.
  Widget wrapAsDocument(Widget rendered, Map<String, dynamic>? root) {
    if (root == null || _isViewportLockedRoot(root)) return rendered;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: rendered,
          ),
        );
      },
    );
  }

  /// Whether [root]'s fully-cascaded style locks it to the viewport (a full-bleed
  /// stage that should not document-scroll). Reads the RAW computed map so a
  /// `100vh`/`100%`/`fixed` written via a class or inline style is honoured.
  bool _isViewportLockedRoot(Map<String, dynamic> root) {
    final props = root['props'];
    final propsMap = props is Map ? props : const {};
    final className = root['className'] ?? propsMap['className'];
    final classes = className is String
        ? className.split(' ')
        : (className is List ? className.cast<String>() : null);
    final inline = root['style'] ?? propsMap['style'];
    final raw = _stylesheetManager.getComputedStyleMap(
      tagName: root['type'] as String? ?? 'div',
      id: root['key'] as String?,
      classes: classes,
      inlineStyles: inline is Map<String, dynamic> ? inline : null,
    );
    if (raw['position']?.toString() == 'fixed') return true;
    final h = raw['height']?.toString().trim();
    if (h != null && (h.contains('vh') || h == '100%')) return true;
    // A screen that embeds a 3D scene is a full-bleed stage, never a scrolling
    // document: the scene fills the viewport and a HUD floats over it. Scenes
    // also can't be measured for intrinsic height, so document-scrolling one
    // would break its `flex`/`100%` fill. Detect one anywhere in the subtree.
    return _containsScene(root, 0);
  }

  static const _sceneTypes = {
    'GameScene', 'BevyScene', 'scene3d', 'Scene3D', 'mesh3d', 'model3d',
  };

  /// Whether [node]'s subtree contains a 3D scene node (bounded-depth walk).
  bool _containsScene(Map<String, dynamic> node, int depth) {
    if (depth > 6) return false;
    if (_sceneTypes.contains(node['type'])) return true;
    final children = node['children'];
    if (children is List) {
      for (final c in children) {
        if (c is Map<String, dynamic> && _containsScene(c, depth + 1)) {
          return true;
        }
      }
    }
    return false;
  }

  void registerWidget(String type, Widget Function(ElpianNode node, List<Widget> children) builder) {
    _registry.register(type, builder);
  }

  void registerWidgets(Map<String, Widget Function(ElpianNode node, List<Widget> children)> builders) {
    _registry.registerAll(builders);
  }
}
