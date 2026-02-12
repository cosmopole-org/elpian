import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';
import '../widgets/stac_canvas_widget.dart';

// HTML Widgets

class StacEngine {
  final WidgetRegistry _registry = WidgetRegistry();
  final EventDispatcher _eventDispatcher = EventDispatcher();
  final GlobalStylesheetManager _stylesheetManager = GlobalStylesheetManager();
  String? _currentParentId;

  StacEngine() {
    _registerDefaultWidgets();
  }
  
  /// Set global event handler to receive all events
  void setGlobalEventHandler(StacEventListener handler) {
    _eventDispatcher.onGlobalEvent(handler);
  }
  
  /// Subscribe to specific event type
  void onEventType(StacEventType type, StacEventListener listener) {
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
    // Flutter widgets
    _registry.register('Container', StacContainer.build);
    _registry.register('Text', StacText.build);
    _registry.register('Button', StacButton.build);
    _registry.register('Image', StacImage.build);
    _registry.register('Column', StacColumn.build);
    _registry.register('Row', StacRow.build);
    _registry.register('Stack', StacStack.build);
    _registry.register('Positioned', StacPositioned.build);
    _registry.register('Expanded', StacExpanded.build);
    _registry.register('Flexible', StacFlexible.build);
    _registry.register('Center', StacCenter.build);
    _registry.register('Padding', StacPadding.build);
    _registry.register('Align', StacAlign.build);
    _registry.register('SizedBox', StacSizedBox.build);
    _registry.register('ListView', StacListView.build);
    _registry.register('GridView', StacGridView.build);
    _registry.register('TextField', StacTextField.build);
    _registry.register('Checkbox', StacCheckbox.build);
    _registry.register('Radio', StacRadio.build);
    _registry.register('Switch', StacSwitch.build);
    _registry.register('Slider', StacSlider.build);
    _registry.register('Icon', StacIcon.build);
    _registry.register('Card', StacCard.build);
    _registry.register('Scaffold', StacScaffold.build);
    _registry.register('AppBar', StacAppBar.build);
    _registry.register('Canvas', StacCanvasWidget.build);

    // HTML widgets
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
  }

  Widget render(StacNode node, {String? parentId}) {
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
    CSSStyle? mergedStyle = stylesheetStyle;
    if (inlineStyle != null) {
      // Inline styles override stylesheet styles
      mergedStyle = inlineStyle;
    }

    // Create node with merged style
    StacNode nodeWithStyle = node;
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

  Widget renderFromJson(Map<String, dynamic> json) {
    final node = StacNode.fromJson(json);
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

  void registerWidget(String type, Widget Function(StacNode node, List<Widget> children) builder) {
    _registry.register(type, builder);
  }

  void registerWidgets(Map<String, Widget Function(StacNode node, List<Widget> children)> builders) {
    _registry.registerAll(builders);
  }
}
