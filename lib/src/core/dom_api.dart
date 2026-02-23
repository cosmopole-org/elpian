
import '../models/elpian_node.dart';
import '../models/css_style.dart';
import '../css/css_parser.dart';

/// DOM-like API for manipulating Elpian elements
class ElpianDOM {
  final Map<String, ElpianElement> _elements = {};
  final List<ElpianElement> _elementsList = [];
  final Map<String, List<ElpianElement>> _elementsByClass = {};
  final Map<String, List<ElpianElement>> _elementsByTag = {};
  
  /// Get element by ID
  ElpianElement? getElementById(String id) {
    return _elements[id];
  }
  
  /// Get elements by class name
  List<ElpianElement> getElementsByClassName(String className) {
    return _elementsByClass[className] ?? [];
  }
  
  /// Get elements by tag name
  List<ElpianElement> getElementsByTagName(String tagName) {
    return _elementsByTag[tagName] ?? [];
  }
  
  /// Query selector (simple implementation)
  ElpianElement? querySelector(String selector) {
    if (selector.startsWith('#')) {
      return getElementById(selector.substring(1));
    } else if (selector.startsWith('.')) {
      final elements = getElementsByClassName(selector.substring(1));
      return elements.isEmpty ? null : elements.first;
    } else {
      final elements = getElementsByTagName(selector);
      return elements.isEmpty ? null : elements.first;
    }
  }
  
  /// Query selector all
  List<ElpianElement> querySelectorAll(String selector) {
    if (selector.startsWith('#')) {
      final element = getElementById(selector.substring(1));
      return [if (element != null) element];
    } else if (selector.startsWith('.')) {
      return getElementsByClassName(selector.substring(1));
    } else {
      return getElementsByTagName(selector);
    }
  }
  
  /// Create element
  ElpianElement createElement(String tagName, {String? id, List<String>? classes}) {
    final element = ElpianElement(
      tagName: tagName,
      id: id,
      classes: classes ?? [],
      dom: this,
    );
    
    if (id != null) {
      _elements[id] = element;
    }
    
    _elementsList.add(element);
    
    (_elementsByTag[tagName] ??= []).add(element);

    for (final className in classes ?? []) {
      (_elementsByClass[className] ??= []).add(element);
    }
    
    return element;
  }
  
  /// Remove element
  void removeElement(ElpianElement element) {
    if (element.id != null) {
      _elements.remove(element.id);
    }
    
    _elementsList.remove(element);
    
    _elementsByTag[element.tagName]?.remove(element);
    
    for (final className in element.classes) {
      _elementsByClass[className]?.remove(element);
    }
    
    element.parent?.removeChild(element);
  }
  
  /// Clear all elements
  void clear() {
    _elements.clear();
    _elementsList.clear();
    _elementsByClass.clear();
    _elementsByTag.clear();
  }
  
  /// Get all elements
  List<ElpianElement> get allElements => List.unmodifiable(_elementsList);
}

/// Represents a DOM-like element
class ElpianElement {
  final String tagName;
  final String? id;
  final List<String> classes;
  final ElpianDOM dom;
  
  ElpianElement? parent;
  final List<ElpianElement> _children = [];
  
  final Map<String, dynamic> _attributes = {};
  final Map<String, dynamic> _style = {};
  final Map<String, Function> _eventListeners = {};
  
  String? _textContent;
  CSSStyle? _computedStyle;
  
  ElpianElement({
    required this.tagName,
    this.id,
    this.classes = const [],
    required this.dom,
  });
  
  /// Get/Set text content
  String? get textContent => _textContent;
  set textContent(String? value) => _textContent = value;
  
  /// Get/Set inner HTML (as text for now)
  String? get innerHTML => _textContent;
  set innerHTML(String? value) => _textContent = value;
  
  /// Get/Set attributes
  dynamic getAttribute(String name) => _attributes[name];
  
  void setAttribute(String name, dynamic value) {
    _attributes[name] = value;
  }
  
  void removeAttribute(String name) {
    _attributes.remove(name);
  }
  
  bool hasAttribute(String name) {
    return _attributes.containsKey(name);
  }
  
  Map<String, dynamic> get attributes => Map.unmodifiable(_attributes);
  
  /// Style manipulation
  void setStyle(String property, dynamic value) {
    _style[property] = value;
    _computedStyle = null; // Invalidate computed style
  }
  
  dynamic getStyle(String property) => _style[property];
  
  void setStyleObject(Map<String, dynamic> styles) {
    _style.addAll(styles);
    _computedStyle = null;
  }
  
  Map<String, dynamic> get style => Map.unmodifiable(_style);
  
  CSSStyle get computedStyle {
    if (_computedStyle == null) {
      _computedStyle = CSSParser.parse(_style);
    }
    return _computedStyle!;
  }
  
  /// Class manipulation
  void addClass(String className) {
    if (!classes.contains(className)) {
      classes.add(className);
      (dom._elementsByClass[className] ??= []).add(this);
    }
  }
  
  void removeClass(String className) {
    classes.remove(className);
    dom._elementsByClass[className]?.remove(this);
  }
  
  bool hasClass(String className) {
    return classes.contains(className);
  }
  
  void toggleClass(String className) {
    if (hasClass(className)) {
      removeClass(className);
    } else {
      addClass(className);
    }
  }
  
  /// Child manipulation
  void appendChild(ElpianElement child) {
    child.parent?.removeChild(child);
    child.parent = this;
    _children.add(child);
  }
  
  void insertBefore(ElpianElement newChild, ElpianElement? referenceChild) {
    newChild.parent?.removeChild(newChild);
    newChild.parent = this;
    
    if (referenceChild == null) {
      _children.add(newChild);
    } else {
      final index = _children.indexOf(referenceChild);
      if (index >= 0) {
        _children.insert(index, newChild);
      }
    }
  }
  
  void removeChild(ElpianElement child) {
    if (_children.remove(child)) {
      child.parent = null;
    }
  }
  
  void replaceChild(ElpianElement newChild, ElpianElement oldChild) {
    final index = _children.indexOf(oldChild);
    if (index >= 0) {
      newChild.parent?.removeChild(newChild);
      newChild.parent = this;
      oldChild.parent = null;
      _children[index] = newChild;
    }
  }
  
  ElpianElement? get firstChild => _children.isNotEmpty ? _children.first : null;
  ElpianElement? get lastChild => _children.isNotEmpty ? _children.last : null;
  
  List<ElpianElement> get children => List.unmodifiable(_children);
  List<ElpianElement> get childNodes => List.unmodifiable(_children);
  
  ElpianElement? get nextSibling {
    if (parent == null) return null;
    final siblings = parent!._children;
    final index = siblings.indexOf(this);
    return index >= 0 && index < siblings.length - 1 ? siblings[index + 1] : null;
  }
  
  ElpianElement? get previousSibling {
    if (parent == null) return null;
    final siblings = parent!._children;
    final index = siblings.indexOf(this);
    return index > 0 ? siblings[index - 1] : null;
  }
  
  /// Event handling
  void addEventListener(String event, Function callback) {
    _eventListeners[event] = callback;
  }
  
  void removeEventListener(String event) {
    _eventListeners.remove(event);
  }
  
  void dispatchEvent(String event, {dynamic data}) {
    final listener = _eventListeners[event];
    if (listener != null) {
      if (listener is Function(dynamic)) {
        listener(data);
      } else if (listener is Function()) {
        listener();
      }
    }
  }
  
  /// Clone element
  ElpianElement clone({bool deep = false}) {
    final cloned = dom.createElement(
      tagName,
      id: null, // Don't clone ID
      classes: List.from(classes),
    );
    
    cloned._attributes.addAll(_attributes);
    cloned._style.addAll(_style);
    cloned._textContent = _textContent;
    
    if (deep) {
      for (final child in _children) {
        cloned.appendChild(child.clone(deep: true));
      }
    }
    
    return cloned;
  }
  
  /// Convert to ElpianNode
  ElpianNode toElpianNode() {
    final props = Map<String, dynamic>.from(_attributes);
    if (_textContent != null) {
      props['text'] = _textContent;
    }
    
    return ElpianNode(
      type: tagName,
      props: props,
      style: _computedStyle,
      key: id,
      children: _children.map((child) => child.toElpianNode()).toList(),
    );
  }
  
  /// Create from ElpianNode
  static ElpianElement fromElpianNode(ElpianNode node, ElpianDOM dom) {
    final element = dom.createElement(
      node.type,
      id: node.key,
    );
    
    element._attributes.addAll(node.props);
    
    if (node.props['text'] != null) {
      element._textContent = node.props['text'] as String;
    }
    
    for (final child in node.children) {
      element.appendChild(fromElpianNode(child, dom));
    }
    
    return element;
  }
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('<$tagName');
    if (id != null) buffer.write(' id="$id"');
    if (classes.isNotEmpty) buffer.write(' class="${classes.join(' ')}"');
    buffer.write('>');
    return buffer.toString();
  }
}
