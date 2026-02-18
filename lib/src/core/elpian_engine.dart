import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';
import '../widgets/elpian_canvas_widget.dart';

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
        color: Colors.red.withOpacity(0.2),
        child: Text('Unknown widget: ${node.type}'),
      );
    }

    // Get styles from stylesheet if element has ID or classes
    CSSStyle? stylesheetStyle;
    if (node.key != null || (node.props['className'] != null)) {
      final classes = node.props['className'] is String
          ? (node.props['className'] as String).split(' ')
          : (node.props['className'] as List?)?.cast<String>();

      stylesheetStyle = _stylesheetManager.getComputedStyle(
        tagName: node.type,
        id: node.key,
        classes: classes,
        inlineStyles: null,
      );
    }

    // Parse inline style if present
    CSSStyle? inlineStyle;
    if (node.props['style'] != null) {
      inlineStyle = CSSParser.parse(node.props['style'] as Map<String, dynamic>);
    }

    // Merge stylesheet style with inline style (inline has higher priority)
    CSSStyle? mergedStyle;
    if (stylesheetStyle != null && inlineStyle != null) {
      // Merge: start with stylesheet styles, override with inline
      final stylesheetMap = _styleToMap(stylesheetStyle);
      final inlineMap = node.props['style'] as Map<String, dynamic>;
      stylesheetMap.addAll(inlineMap);
      mergedStyle = CSSParser.parse(stylesheetMap);
    } else {
      mergedStyle = inlineStyle ?? stylesheetStyle;
    }

    // Create node with merged style
    ElpianNode nodeWithStyle = node;
    if (mergedStyle != null || node.style != null) {
      nodeWithStyle = node.copyWith(style: mergedStyle ?? node.style);
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

    // Wrap with event handling if node has events
    if (nodeWithStyle.events != null && nodeWithStyle.events!.isNotEmpty) {
      result = EventEnabledWidget(
        node: nodeWithStyle,
        parentId: parentId,
        child: result,
      );
    }

    return result;
  }

  /// Convert a CSSStyle back to a style map for merging
  Map<String, dynamic> _styleToMap(CSSStyle style) {
    final map = <String, dynamic>{};
    if (style.width != null) map['width'] = style.width;
    if (style.height != null) map['height'] = style.height;
    if (style.minWidth != null) map['minWidth'] = style.minWidth;
    if (style.maxWidth != null) map['maxWidth'] = style.maxWidth;
    if (style.minHeight != null) map['minHeight'] = style.minHeight;
    if (style.maxHeight != null) map['maxHeight'] = style.maxHeight;
    if (style.padding != null) map['padding'] = '${style.padding!.top} ${style.padding!.right} ${style.padding!.bottom} ${style.padding!.left}';
    if (style.margin != null) map['margin'] = '${style.margin!.top} ${style.margin!.right} ${style.margin!.bottom} ${style.margin!.left}';
    if (style.backgroundColor != null) map['backgroundColor'] = _colorToString(style.backgroundColor!);
    if (style.color != null) map['color'] = _colorToString(style.color!);
    if (style.fontSize != null) map['fontSize'] = style.fontSize;
    if (style.fontWeight != null) map['fontWeight'] = _fontWeightToString(style.fontWeight!);
    if (style.fontStyle != null) map['fontStyle'] = style.fontStyle == FontStyle.italic ? 'italic' : 'normal';
    if (style.fontFamily != null) map['fontFamily'] = style.fontFamily;
    if (style.letterSpacing != null) map['letterSpacing'] = style.letterSpacing;
    if (style.wordSpacing != null) map['wordSpacing'] = style.wordSpacing;
    if (style.lineHeight != null) map['lineHeight'] = style.lineHeight;
    if (style.textAlign != null) map['textAlign'] = style.textAlign.toString().split('.').last;
    if (style.borderRadius != null) map['borderRadius'] = style.borderRadius;
    if (style.borderColor != null) map['borderColor'] = _colorToString(style.borderColor!);
    if (style.borderWidth != null) map['borderWidth'] = style.borderWidth;
    if (style.opacity != null) map['opacity'] = style.opacity;
    if (style.display != null) map['display'] = style.display;
    if (style.flexDirection != null) map['flexDirection'] = style.flexDirection;
    if (style.justifyContent != null) map['justifyContent'] = style.justifyContent;
    if (style.alignItems != null) map['alignItems'] = style.alignItems;
    if (style.flex != null) map['flex'] = style.flex;
    if (style.gap != null) map['gap'] = style.gap;
    if (style.flexWrap != null) map['flexWrap'] = style.flexWrap;
    if (style.gradient != null) map['gradient'] = style.gradient;
    if (style.boxShadow != null) map['boxShadow'] = style.boxShadow;
    if (style.textShadow != null) map['textShadow'] = style.textShadow;
    if (style.rotate != null) map['rotate'] = style.rotate;
    if (style.scale != null) map['scale'] = style.scale;
    if (style.visible != null) map['visible'] = style.visible;
    if (style.position != null) map['position'] = style.position;
    if (style.top != null) map['top'] = style.top;
    if (style.right != null) map['right'] = style.right;
    if (style.bottom != null) map['bottom'] = style.bottom;
    if (style.left != null) map['left'] = style.left;
    return map;
  }

  String _colorToString(Color color) {
    return 'rgba(${color.red},${color.green},${color.blue},${color.alpha / 255.0})';
  }

  String _fontWeightToString(FontWeight weight) {
    if (weight == FontWeight.bold) return 'bold';
    if (weight == FontWeight.normal) return 'normal';
    return '${weight.value}';
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

  void registerWidget(String type, Widget Function(ElpianNode node, List<Widget> children) builder) {
    _registry.register(type, builder);
  }

  void registerWidgets(Map<String, Widget Function(ElpianNode node, List<Widget> children)> builders) {
    _registry.registerAll(builders);
  }
}
