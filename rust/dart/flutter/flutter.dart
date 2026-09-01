// =============================================================================
// flutter.dart — a self-contained Flutter widget library for the Elpian VM
// =============================================================================
//
// This is real, idiomatic Flutter-style Dart: the widget classes, painting
// value types, and layout protocol an app imports and builds against. It is
// modelled closely on the public API of the real framework
// (`package:flutter/widgets.dart` + `painting/` + `rendering/`) — same class
// names, same constructor shapes, same composition idioms — but reimplemented
// in the subset the Elpian front-end compiles, so a whole app runs on the VM
// with no ahead-of-time compilation and no JIT.
//
// An app uses it exactly like Flutter:
//
//     import 'flutter.dart';
//
//     class MyApp extends StatelessWidget {
//       const MyApp();
//       Widget build(BuildContext context) {
//         return MaterialApp(
//           home: Scaffold(
//             backgroundColor: Colors.blueGrey,
//             body: Center(child: Text('Hello', style: TextStyle(fontSize: 32.0))),
//           ),
//         );
//       }
//     }
//     void main() => runApp(MyApp());
//
// Rendering: instead of RenderObjects talking to the GPU, each widget lowers
// itself to a `dart:ui` scene (drawRect/drawCircle/drawParagraph) via the host
// bridge; the engine rasterizes that scene. Layout is a real two-phase pass —
// `layout(constraints)` sizes and positions, `paint(offset)` emits — mirroring
// RenderBox. State is retained across frames and `setState` schedules a repaint,
// so the app is fully interactive.

// =============================================================================
// SECTION 1 — foundation
// =============================================================================

/// A [Widget]'s identity across rebuilds. (Position-based reconciliation is used
/// here, so keys are accepted for API compatibility but not yet load-bearing.)
class Key {
  final String value;
  const Key(this.value);
}

class ValueKey extends Key {
  const ValueKey(String value) { this.value = value; }
}

/// A handle to a widget's location in the tree. Minimal here: enough for
/// `build(BuildContext context)` signatures to read like Flutter.
class BuildContext {
  var widget;
  BuildContext();
}

// =============================================================================
// SECTION 2 — painting: geometry value types
// =============================================================================

/// An immutable 2D floating-point offset (a point or a vector), like
/// `dart:ui`'s [Offset].
class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
  static Offset zero() => Offset(0.0, 0.0);
  Offset translate(double tx, double ty) => Offset(dx + tx, dy + ty);
}

/// An immutable width/height pair, like `dart:ui`'s [Size].
class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
  static Size zero() => Size(0.0, 0.0);
  static Size square(double d) => Size(d, d);
}

/// Immutable layout constraints: a box's width is in `[minWidth, maxWidth]` and
/// height in `[minHeight, maxHeight]`. Mirrors `rendering`'s [BoxConstraints].
class BoxConstraints {
  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
  const BoxConstraints(this.minWidth, this.maxWidth, this.minHeight, this.maxHeight);

  /// Constraints forcing exactly [size].
  static BoxConstraints tight(Size size) =>
      BoxConstraints(size.width, size.width, size.height, size.height);

  /// Constraints allowing anything up to [size].
  static BoxConstraints loose(Size size) =>
      BoxConstraints(0.0, size.width, 0.0, size.height);

  double clampW(double w) {
    if (w < minWidth) { return minWidth; }
    if (w > maxWidth) { return maxWidth; }
    return w;
  }

  double clampH(double h) {
    if (h < minHeight) { return minHeight; }
    if (h > maxHeight) { return maxHeight; }
    return h;
  }

  Size constrain(Size size) => Size(clampW(size.width), clampH(size.height));

  /// A copy with the max bounds reduced by [dw] x [dh] (min clamped to 0).
  BoxConstraints deflate(double dw, double dh) {
    var mw = maxWidth - dw;
    var mh = maxHeight - dh;
    if (mw < 0.0) { mw = 0.0; }
    if (mh < 0.0) { mh = 0.0; }
    return BoxConstraints(0.0, mw, 0.0, mh);
  }

  BoxConstraints get loosen => BoxConstraints(0.0, maxWidth, 0.0, maxHeight);
}

/// An immutable rectangle from left/top/right/bottom, like `dart:ui`'s [Rect].
class Rect {
  final double left;
  final double top;
  final double right;
  final double bottom;
  const Rect(this.left, this.top, this.right, this.bottom);
  static Rect fromLTWH(double l, double t, double w, double h) => Rect(l, t, l + w, t + h);
}

/// Offsets for the four edges of a box, like `painting`'s [EdgeInsets].
class EdgeInsets {
  final double left;
  final double top;
  final double right;
  final double bottom;
  // Precomputed axis totals (fields rather than getters, computed once).
  double horizontal;
  double vertical;
  EdgeInsets(this.left, this.top, this.right, this.bottom) {
    horizontal = left + right;
    vertical = top + bottom;
  }
  static EdgeInsets all(double v) => EdgeInsets(v, v, v, v);
  static EdgeInsets symmetric(double horizontal, double vertical) =>
      EdgeInsets(horizontal, vertical, horizontal, vertical);
  static EdgeInsets only(double left, double top, double right, double bottom) =>
      EdgeInsets(left, top, right, bottom);
  static EdgeInsets fromLTRB(double l, double t, double r, double b) => EdgeInsets(l, t, r, b);
  static EdgeInsets zero() => EdgeInsets(0.0, 0.0, 0.0, 0.0);
}

/// A point within a rectangle, with x and y in the range -1.0 to 1.0, like
/// `painting`'s [Alignment]. -1 is left/top, 0 is center, 1 is right/bottom.
class Alignment {
  final double x;
  final double y;
  const Alignment(this.x, this.y);
  // The nine canonical alignments.
  static Alignment topLeft() => Alignment(-1.0, -1.0);
  static Alignment topCenter() => Alignment(0.0, -1.0);
  static Alignment topRight() => Alignment(1.0, -1.0);
  static Alignment centerLeft() => Alignment(-1.0, 0.0);
  static Alignment center() => Alignment(0.0, 0.0);
  static Alignment centerRight() => Alignment(1.0, 0.0);
  static Alignment bottomLeft() => Alignment(-1.0, 1.0);
  static Alignment bottomCenter() => Alignment(0.0, 1.0);
  static Alignment bottomRight() => Alignment(1.0, 1.0);

  /// The offset that positions a child of [child] inside a box of [parent],
  /// per this alignment (mirrors Alignment.alongOffset / inscribe).
  Offset withinRect(Size parent, Size child) {
    var fx = (x + 1.0) / 2.0;
    var fy = (y + 1.0) / 2.0;
    return Offset((parent.width - child.width) * fx, (parent.height - child.height) * fy);
  }
}

// =============================================================================
// SECTION 3 — painting: colors, borders, text style
// =============================================================================

/// An immutable 32-bit ARGB color, like `dart:ui`'s [Color].
class Color {
  final int value;
  const Color(this.value);

  /// Construct from 8-bit alpha/red/green/blue channels.
  static Color fromARGB(int a, int r, int g, int b) {
    var v = ((a % 256) * 16777216) + ((r % 256) * 65536) + ((g % 256) * 256) + (b % 256);
    return Color(v);
  }

  /// Construct from 8-bit r/g/b and a 0.0–1.0 opacity.
  static Color fromRGBO(int r, int g, int b, double opacity) {
    var a = (opacity * 255.0 + 0.5).toInt();
    return Color.fromARGB(a, r, g, b);
  }

  int alpha() => (value ~/ 16777216) % 256;
  int red() => (value ~/ 65536) % 256;
  int green() => (value ~/ 256) % 256;
  int blue() => value % 256;

  /// A copy of this color with the given opacity (0.0–1.0).
  Color withOpacity(double opacity) => Color.fromARGB((opacity * 255.0 + 0.5).toInt(), red(), green(), blue());
}

/// The Material color palette — a subset of the real `Colors` class. Each entry
/// is a fully-opaque ARGB constant, reached as `Colors.blue` etc.
class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFF44336);
  static const Color pink = Color(0xFFE91E63);
  static const Color purple = Color(0xFF9C27B0);
  static const Color indigo = Color(0xFF3F51B5);
  static const Color blue = Color(0xFF2196F3);
  static const Color lightBlue = Color(0xFF03A9F4);
  static const Color cyan = Color(0xFF00BCD4);
  static const Color teal = Color(0xFF009688);
  static const Color green = Color(0xFF4CAF50);
  static const Color lightGreen = Color(0xFF8BC34A);
  static const Color lime = Color(0xFFCDDC39);
  static const Color yellow = Color(0xFFFFEB3B);
  static const Color amber = Color(0xFFFFC107);
  static const Color orange = Color(0xFFFF9800);
  static const Color deepOrange = Color(0xFFFF5722);
  static const Color brown = Color(0xFF795548);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color blueGrey = Color(0xFF607D8B);
}

/// A uniform corner radius, like `painting`'s [BorderRadius].
class BorderRadius {
  final double radius;
  const BorderRadius(this.radius);
  static BorderRadius circular(double r) => BorderRadius(r);
  static BorderRadius zero() => BorderRadius(0.0);
}

/// A box background: a fill color and optional rounded corners, a small slice of
/// `painting`'s [BoxDecoration].
class BoxDecoration {
  var color;
  var borderRadius;
  BoxDecoration({this.color, this.borderRadius});
}

/// How to weight glyphs. In the real framework this is a rich class; here it is
/// an enum whose values flow through to the paragraph style.
enum FontWeight { normal, bold }

/// Whether and how to align text horizontally, like `dart:ui`'s [TextAlign].
enum TextAlign { left, right, center }

/// An immutable style for a run of text, a subset of `painting`'s [TextStyle].
class TextStyle {
  var fontSize;
  var color;
  var fontWeight;
  TextStyle({this.fontSize, this.color, this.fontWeight});
}

// =============================================================================
// SECTION 4 — layout enums
// =============================================================================

/// The direction in which boxes flow, like `painting`'s [Axis].
enum Axis { horizontal, vertical }

/// How the children of a [Row]/[Column] are placed along the main axis.
enum MainAxisAlignment { start, end, center, spaceBetween, spaceAround, spaceEvenly }

/// How the children of a [Row]/[Column] are placed along the cross axis.
enum CrossAxisAlignment { start, end, center, stretch }

/// Whether a [Row]/[Column] shrink-wraps or expands along its main axis.
enum MainAxisSize { min, max }

// =============================================================================
// SECTION 5 — the widget framework
// =============================================================================

/// The base class for everything that describes part of the UI. Concrete
/// widgets either *compose* other widgets (via [build]) or *render* themselves
/// (by overriding the layout/paint protocol). Mirrors `widgets`'s [Widget].
abstract class Widget {
  var key;

  // ---- render protocol (a simplified, faithful stand-in for RenderBox) ----
  // The computed size, valid after `layout`.
  var size;

  /// Refresh transient expanded children from config children. Called once per
  /// frame before layout; must NOT mutate configuration.
  void inflate() {}

  /// Size this widget under [constraints], laying out and positioning children.
  /// Returns and records [size]. The default is a zero-size box.
  Size layout(BoxConstraints constraints) {
    this.size = constraints.constrain(Size.zero());
    return this.size;
  }

  /// Emit this widget's paint ops at [offset] (its top-left in the view), then
  /// paint children. Called after [layout].
  void paint(Offset offset) {}
}

/// A widget that describes its UI by composing others, and has no mutable state.
/// Subclasses implement [build]. Mirrors `widgets`'s [StatelessWidget].
abstract class StatelessWidget extends Widget {
  Widget build(BuildContext context) { return null; }
}

/// A widget with mutable [State] that persists across rebuilds. Subclasses
/// implement [createState]. Mirrors `widgets`'s [StatefulWidget].
abstract class StatefulWidget extends Widget {
  State createState() { return null; }
}

/// The logic and mutable state for a [StatefulWidget]. Mirrors `widgets`'s
/// [State]: `initState`, `build`, and `setState` (which requests a repaint).
abstract class State {
  var widget;

  void initState() {}

  Widget build(BuildContext context) { return null; }

  /// Notify the framework that internal state changed, running [fn] and
  /// scheduling a rebuild + repaint.
  void setState(Function fn) {
    fn();
    __markNeedsBuild();
  }
}

// =============================================================================
// SECTION 6 — the binding: runApp, the frame pipeline, and hit-testing
// =============================================================================

// The retained application root and per-frame scratch state.
var __rootWidget = null;
var __states = [];
var __locCounter = 0;
var __hits = [];
var __needsBuild = false;
var __context = null;

// Logical view size (the tight constraints handed to the root each frame).
double __viewWidth = 400.0;
double __viewHeight = 800.0;

/// Mark the tree dirty and ask the engine to schedule another frame — the
/// mechanism behind [State.setState].
void __markNeedsBuild() {
  __needsBuild = true;
  askHost("dart:ui/scheduleFrame", []);
}

/// Persistent [State] lookup, matched to a [StatefulWidget] by build-order
/// index (position-based reconciliation, like Flutter without keys), so state
/// survives across frames.
State __stateFor(StatefulWidget w) {
  var idx = __locCounter;
  __locCounter = __locCounter + 1;
  if (idx < __states.length) {
    var existing = __states[idx];
    existing.widget = w;
    return existing;
  }
  var st = w.createState();
  st.widget = w;
  st.initState();
  __states.add(st);
  return st;
}

/// Resolve a widget to a concrete render widget: repeatedly `build` Stateless /
/// Stateful widgets until a render widget remains, then inflate its children.
Widget expand(Widget w) {
  var cur = w;
  var done = false;
  while (!done) {
    if (cur is StatelessWidget) {
      cur = cur.build(__context);
    } else if (cur is StatefulWidget) {
      var st = __stateFor(cur);
      cur = st.build(__context);
    } else {
      done = true;
    }
  }
  if (cur == null) { cur = SizedBox(); }
  cur.inflate();
  return cur;
}

/// Attach [app] as the root of the widget tree and schedule the first frame.
/// The engine then drives `onBeginFrame`/`onDrawFrame`; taps arrive via
/// `onPointerEvent`. Mirrors `widgets`'s [runApp].
void runApp(Widget app) {
  __context = BuildContext();
  __rootWidget = app;
  __markNeedsBuild();
}

// ---- engine binding handlers (invoked by the runtime) ----

void onBeginFrame(t) {}

void onDrawFrame() {
  if (__rootWidget == null) { return; }
  __needsBuild = false;
  __locCounter = 0;
  __hits = [];

  var tree = expand(__rootWidget);
  var constraints = BoxConstraints.tight(Size(__viewWidth, __viewHeight));
  tree.layout(constraints);

  askHost("dart:ui/PictureRecorder.beginRecording", []);
  tree.paint(Offset.zero());
  var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
  var scene = askHost("dart:ui/Picture.toScene", [pic]);
  askHost("dart:ui/FlutterView.render", [scene]);
}

void onPointerEvent(e) {
  var phase = e["phase"];
  // A tap completes on pointer-up; ignore intermediate down/move events.
  if (phase != "up") { return; }
  var x = e["x"];
  var y = e["y"];
  // Hit rects are recorded front-to-back during paint; scan back-to-front so
  // the topmost detector wins.
  var i = __hits.length - 1;
  while (i >= 0) {
    var h = __hits[i];
    if (x >= h["x0"] && x <= h["x1"] && y >= h["y0"] && y <= h["y1"]) {
      var cb = h["onTap"];
      if (cb != null) { cb(); }
      return;
    }
    i = i - 1;
  }
}

/// Record a tappable region for hit-testing (used by [GestureDetector]).
void __addHit(Offset offset, Size size, Function onTap) {
  __hits.add({
    "x0": offset.dx,
    "y0": offset.dy,
    "x1": offset.dx + size.width,
    "y1": offset.dy + size.height,
    "onTap": onTap,
  });
}

// Low-level paint helpers over the dart:ui bridge.
void __fillRect(Offset offset, Size size, int color) {
  askHost("dart:ui/Canvas.drawRect",
      [offset.dx, offset.dy, offset.dx + size.width, offset.dy + size.height, color]);
}

// =============================================================================
// SECTION 7 — basic render widgets
// =============================================================================

/// A box with a fixed [width]/[height] that sizes its optional child to match.
/// Mirrors `widgets`'s [SizedBox].
class SizedBox extends Widget {
  var width;
  var height;
  var child;
  var exChild;
  SizedBox({this.width, this.height, this.child});
  static SizedBox shrink() => SizedBox(width: 0.0, height: 0.0);

  void inflate() {
    if (child != null) { exChild = expand(child); } else { exChild = null; }
  }

  Size layout(BoxConstraints c) {
    var w = width ?? 0.0;
    var h = height ?? 0.0;
    if (exChild != null) {
      var cs = exChild.layout(BoxConstraints.tight(Size(c.clampW(w), c.clampH(h))));
      if (width == null) { w = cs.width; }
      if (height == null) { h = cs.height; }
    }
    this.size = c.constrain(Size(w, h));
    return this.size;
  }

  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A convenience box that combines painting (color/decoration), positioning
/// (padding/alignment) and sizing (width/height) around a child. This is the
/// workhorse container, mirroring `widgets`'s [Container].
class Container extends Widget {
  var width;
  var height;
  var color;
  var decoration;
  var padding;
  var alignment;
  var child;
  var exChild;
  var childOffset;
  Container({this.width, this.height, this.color, this.decoration, this.padding,
             this.alignment, this.child});

  void inflate() {
    if (child != null) { exChild = expand(child); } else { exChild = null; }
  }

  Size layout(BoxConstraints c) {
    var pad = padding ?? EdgeInsets.zero();
    var childSize = Size.zero();
    if (exChild != null) {
      var inner = c.deflate(pad.horizontal, pad.vertical);
      childSize = exChild.layout(inner);
    }
    var w = width ?? (childSize.width + pad.horizontal);
    var h = height ?? (childSize.height + pad.vertical);
    this.size = c.constrain(Size(w, h));

    // Position the child: centered by [alignment] within the padded area, else
    // at the padding origin.
    if (exChild != null) {
      var innerW = this.size.width - pad.horizontal;
      var innerH = this.size.height - pad.vertical;
      var ox = pad.left;
      var oy = pad.top;
      if (alignment != null) {
        var slack = alignment.withinRect(Size(innerW, innerH), childSize);
        ox = pad.left + slack.dx;
        oy = pad.top + slack.dy;
      }
      this.childOffset = Offset(ox, oy);
    }
    return this.size;
  }

  void paint(Offset offset) {
    var fill = color;
    if (fill == null && decoration != null) { fill = decoration.color; }
    if (fill != null) { __fillRect(offset, this.size, fill.value); }
    if (exChild != null) {
      exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy));
    }
  }
}

/// A box that paints a [BoxDecoration] behind its child, mirroring `widgets`'s
/// [DecoratedBox].
class DecoratedBox extends Widget {
  var decoration;
  var child;
  var exChild;
  DecoratedBox({this.decoration, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (decoration != null && decoration.color != null) {
      __fillRect(offset, this.size, decoration.color.value);
    }
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A box painted with a single [color], mirroring `widgets`'s [ColoredBox].
class ColoredBox extends Widget {
  var color;
  var child;
  var exChild;
  ColoredBox({this.color, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (color != null) { __fillRect(offset, this.size, color.value); }
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// Insets its child by [padding], mirroring `widgets`'s [Padding].
class Padding extends Widget {
  var padding;
  var child;
  var exChild;
  var childOffset;
  Padding({this.padding, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var pad = padding ?? EdgeInsets.zero();
    var childSize = Size.zero();
    if (exChild != null) { childSize = exChild.layout(c.deflate(pad.horizontal, pad.vertical)); }
    this.childOffset = Offset(pad.left, pad.top);
    this.size = c.constrain(Size(childSize.width + pad.horizontal, childSize.height + pad.vertical));
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// Centers its child within itself, mirroring `widgets`'s [Center].
class Center extends Widget {
  var child;
  var exChild;
  var childOffset;
  Center({this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    // Fill the incoming max, place the child in the middle.
    this.size = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) {
      var cs = exChild.layout(c.loosen);
      this.childOffset = Offset((this.size.width - cs.width) / 2.0, (this.size.height - cs.height) / 2.0);
    } else {
      this.childOffset = Offset.zero();
    }
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// Aligns its child within itself per an [Alignment], mirroring `widgets`'s
/// [Align].
class Align extends Widget {
  var alignment;
  var child;
  var exChild;
  var childOffset;
  Align({this.alignment, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    this.size = Size(c.maxWidth, c.maxHeight);
    if (exChild != null) {
      var cs = exChild.layout(c.loosen);
      var a = alignment ?? Alignment.center();
      this.childOffset = a.withinRect(this.size, cs);
    } else {
      this.childOffset = Offset.zero();
    }
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset.translate(this.childOffset.dx, this.childOffset.dy)); }
  }
}

/// A child of a [Row]/[Column] that flexes to fill available main-axis space,
/// mirroring `widgets`'s [Flexible]/[Expanded].
class Flexible extends Widget {
  var flex;
  var child;
  var exChild;
  Flexible({this.flex, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A [Flexible] that fills all available space (flex fit tight).
class Expanded extends Flexible {
  Expanded({int flex, Widget child}) { this.flex = flex; this.child = child; }
}

/// A flex layout base for [Row] and [Column]. Lays out non-flexible children
/// first, then distributes the remaining main-axis extent to [Expanded]/
/// [Flexible] children by flex weight — a faithful sketch of RenderFlex.
abstract class Flex extends Widget {
  var direction;
  var children;
  var mainAxisAlignment;
  var crossAxisAlignment;
  var mainAxisSize;
  var exKids;
  var offsets;

  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }

  bool __isHorizontal() { return direction == Axis.horizontal; }

  double __mainOf(Size s) { if (__isHorizontal()) { return s.width; } return s.height; }
  double __crossOf(Size s) { if (__isHorizontal()) { return s.height; } return s.width; }

  /// Constraints for a child spanning `[mainMin, mainMax]` on the main axis;
  /// the cross axis is tight to [maxCross] when stretching, else loose.
  BoxConstraints __childConstraints(double mainMin, double mainMax, double maxCross, bool stretch) {
    var crossMin = stretch ? maxCross : 0.0;
    if (__isHorizontal()) { return BoxConstraints(mainMin, mainMax, crossMin, maxCross); }
    return BoxConstraints(crossMin, maxCross, mainMin, mainMax);
  }

  Size layout(BoxConstraints c) {
    var horizontal = __isHorizontal();
    var maxMain = horizontal ? c.maxWidth : c.maxHeight;
    var maxCross = horizontal ? c.maxHeight : c.maxWidth;
    var stretch = crossAxisAlignment == CrossAxisAlignment.stretch;

    // Pass 1: total flex and the size taken by inflexible children.
    var totalFlex = 0;
    var usedMain = 0.0;
    var maxChildCross = 0.0;
    for (var ch in exKids) {
      if (ch is Flexible) {
        totalFlex = totalFlex + (ch.flex ?? 1);
      } else {
        var cs = ch.layout(__childConstraints(0.0, maxMain, maxCross, stretch));
        usedMain = usedMain + __mainOf(cs);
        if (__crossOf(cs) > maxChildCross) { maxChildCross = __crossOf(cs); }
      }
    }

    // Pass 2: hand each flex child its share of the leftover main extent.
    if (totalFlex > 0) {
      var free = maxMain - usedMain;
      if (free < 0.0) { free = 0.0; }
      for (var ch in exKids) {
        if (ch is Flexible) {
          var share = free * ((ch.flex ?? 1) / totalFlex);
          var cs = ch.layout(__childConstraints(share, share, maxCross, stretch));
          usedMain = usedMain + __mainOf(cs);
          if (__crossOf(cs) > maxChildCross) { maxChildCross = __crossOf(cs); }
        }
      }
    }

    // Main extent: shrink-wrap unless MainAxisSize.max or something flexes.
    var wantMax = (mainAxisSize == MainAxisSize.max) || totalFlex > 0;
    var mainExtent = wantMax ? maxMain : usedMain;
    var crossExtent = maxChildCross;
    if (crossAxisAlignment == CrossAxisAlignment.stretch) { crossExtent = maxCross; }

    this.size = horizontal ? Size(mainExtent, crossExtent) : Size(crossExtent, mainExtent);
    this.size = c.constrain(this.size);

    // Placement: distribute leading/between space per mainAxisAlignment.
    var count = exKids.length;
    var slack = __mainOf(this.size) - usedMain;
    if (slack < 0.0) { slack = 0.0; }
    var leading = 0.0;
    var between = 0.0;
    var main = mainAxisAlignment ?? MainAxisAlignment.start;
    if (main == MainAxisAlignment.end) { leading = slack; }
    if (main == MainAxisAlignment.center) { leading = slack / 2.0; }
    if (main == MainAxisAlignment.spaceBetween && count > 1) { between = slack / (count - 1); }
    if (main == MainAxisAlignment.spaceAround && count > 0) {
      between = slack / count;
      leading = between / 2.0;
    }
    if (main == MainAxisAlignment.spaceEvenly && count > 0) {
      between = slack / (count + 1);
      leading = between;
    }

    this.offsets = [];
    var cursor = leading;
    for (var ch in exKids) {
      var cm = __mainOf(ch.size);
      var cc = __crossOf(ch.size);
      var crossPos = __crossPos(crossExtent, cc);
      var off = horizontal ? Offset(cursor, crossPos) : Offset(crossPos, cursor);
      this.offsets.add(off);
      cursor = cursor + cm + between;
    }
    return this.size;
  }

  double __crossPos(double crossExtent, double childCross) {
    var a = crossAxisAlignment ?? CrossAxisAlignment.center;
    if (a == CrossAxisAlignment.start) { return 0.0; }
    if (a == CrossAxisAlignment.end) { return crossExtent - childCross; }
    if (a == CrossAxisAlignment.stretch) { return 0.0; }
    return (crossExtent - childCross) / 2.0; // center
  }

  void paint(Offset offset) {
    var i = 0;
    while (i < exKids.length) {
      var off = this.offsets[i];
      exKids[i].paint(offset.translate(off.dx, off.dy));
      i = i + 1;
    }
  }
}

/// Lays its children out vertically, mirroring `widgets`'s [Column].
class Column extends Flex {
  Column({List children, MainAxisAlignment mainAxisAlignment,
          CrossAxisAlignment crossAxisAlignment, MainAxisSize mainAxisSize}) {
    this.direction = Axis.vertical;
    this.children = children;
    this.mainAxisAlignment = mainAxisAlignment;
    this.crossAxisAlignment = crossAxisAlignment;
    this.mainAxisSize = mainAxisSize;
  }
}

/// Lays its children out horizontally, mirroring `widgets`'s [Row].
class Row extends Flex {
  Row({List children, MainAxisAlignment mainAxisAlignment,
       CrossAxisAlignment crossAxisAlignment, MainAxisSize mainAxisSize}) {
    this.direction = Axis.horizontal;
    this.children = children;
    this.mainAxisAlignment = mainAxisAlignment;
    this.crossAxisAlignment = crossAxisAlignment;
    this.mainAxisSize = mainAxisSize;
  }
}

/// An empty flexible spacer that eats free space in a [Row]/[Column], mirroring
/// `widgets`'s [Spacer].
class Spacer extends Expanded {
  Spacer() { this.flex = 1; this.child = SizedBox(); }
}

/// Overlays its children, sized to the biggest, mirroring `widgets`'s [Stack].
/// (Non-positioned children are top-left aligned; [Positioned] places explicitly.)
class Stack extends Widget {
  var children;
  var alignment;
  var exKids;
  var offsets;
  Stack({this.children, this.alignment});

  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }

  Size layout(BoxConstraints c) {
    var w = 0.0;
    var h = 0.0;
    for (var ch in exKids) {
      var cs = ch.layout(c.loosen);
      if (ch is Positioned) {
        // A positioned child does not affect the stack's size.
      } else {
        if (cs.width > w) { w = cs.width; }
        if (cs.height > h) { h = cs.height; }
      }
    }
    this.size = c.constrain(Size(w, h));
    var a = alignment ?? Alignment.topLeft();
    this.offsets = [];
    for (var ch in exKids) {
      if (ch is Positioned) {
        this.offsets.add(Offset(ch.left ?? 0.0, ch.top ?? 0.0));
      } else {
        this.offsets.add(a.withinRect(this.size, ch.size));
      }
    }
    return this.size;
  }

  void paint(Offset offset) {
    var i = 0;
    while (i < exKids.length) {
      var off = this.offsets[i];
      exKids[i].paint(offset.translate(off.dx, off.dy));
      i = i + 1;
    }
  }
}

/// Positions its child at explicit [left]/[top] within a [Stack], mirroring
/// `widgets`'s [Positioned].
class Positioned extends Widget {
  var left;
  var top;
  var child;
  var exChild;
  Positioned({this.left, this.top, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c.loosen); }
    this.size = s;
    return this.size;
  }
  void paint(Offset offset) {
    if (exChild != null) { exChild.paint(offset); }
  }
}

/// A run of text with a [TextStyle], mirroring `widgets`'s [Text]. Text is
/// measured with a monospace-ish estimate (the engine provides exact metrics in
/// the full binding); it lowers to a `drawParagraph` scene op.
class Text extends Widget {
  var data;
  var style;
  var textAlign;
  Text(this.data, {this.style, this.textAlign});

  double __fontSize() {
    if (style != null && style.fontSize != null) { return style.fontSize; }
    return 14.0;
  }

  int __color() {
    if (style != null && style.color != null) { return style.color.value; }
    return 4278190080; // opaque black
  }

  Size layout(BoxConstraints c) {
    var fs = __fontSize();
    var w = data.length * fs * 0.58;
    this.size = c.constrain(Size(w, fs * 1.4));
    return this.size;
  }

  void paint(Offset offset) {
    var fs = __fontSize();
    askHost("dart:ui/Canvas.drawParagraph", [data, offset.dx, offset.dy + fs, fs, __color()]);
  }
}

/// A simple square glyph stand-in (the real [Icon] rasterizes a font glyph);
/// here it paints a rounded swatch so icon-bearing layouts render.
class Icon extends Widget {
  var codePoint;
  var color;
  var iconSize;
  Icon(this.codePoint, {this.color, this.iconSize});
  Size layout(BoxConstraints c) {
    var s = iconSize ?? 24.0;
    this.size = c.constrain(Size(s, s));
    return this.size;
  }
  void paint(Offset offset) {
    var col = color ?? Colors.black;
    __fillRect(offset, this.size, col.value);
  }
}

/// A thin horizontal rule, mirroring `material`'s [Divider].
class Divider extends Widget {
  var color;
  var thickness;
  Divider({this.color, this.thickness});
  Size layout(BoxConstraints c) {
    this.size = Size(c.maxWidth, thickness ?? 1.0);
    return this.size;
  }
  void paint(Offset offset) {
    var col = color ?? Colors.grey;
    __fillRect(offset, this.size, col.value);
  }
}

/// Recognizes taps on its child, mirroring `widgets`'s [GestureDetector]. On a
/// pointer-up inside the child's box, [onTap] runs.
class GestureDetector extends Widget {
  var onTap;
  var child;
  var exChild;
  GestureDetector({this.onTap, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size layout(BoxConstraints c) {
    var s = Size.zero();
    if (exChild != null) { s = exChild.layout(c); }
    this.size = c.constrain(s);
    return this.size;
  }
  void paint(Offset offset) {
    __addHit(offset, this.size, onTap);
    if (exChild != null) { exChild.paint(offset); }
  }
}

// =============================================================================
// SECTION 8 — Material-style app shells
// =============================================================================

/// The top-level Material application wrapper. Minimal here: it simply mounts
/// its [home]. Mirrors `material`'s [MaterialApp].
class MaterialApp extends StatelessWidget {
  var home;
  var title;
  MaterialApp({this.home, this.title});
  Widget build(BuildContext context) {
    return home ?? SizedBox();
  }
}

/// A top app bar with a [title], a colored band across the top of a [Scaffold].
/// Mirrors `material`'s [AppBar].
class AppBar extends StatelessWidget {
  var title;
  var backgroundColor;
  var barHeight;
  AppBar({this.title, this.backgroundColor, this.barHeight});
  Widget build(BuildContext context) {
    return Container(
      height: barHeight ?? 56.0,
      color: backgroundColor ?? Colors.blue,
      padding: EdgeInsets.symmetric(16.0, 8.0),
      alignment: Alignment.centerLeft(),
      child: title,
    );
  }
}

/// The basic Material visual layout structure: an optional [appBar] pinned to
/// the top and a [body] filling the rest, over a [backgroundColor]. Mirrors
/// `material`'s [Scaffold].
class Scaffold extends StatelessWidget {
  var appBar;
  var body;
  var backgroundColor;
  Scaffold({this.appBar, this.body, this.backgroundColor});
  Widget build(BuildContext context) {
    var col;
    if (appBar != null) {
      col = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [appBar, Expanded(child: body ?? SizedBox())],
      );
    } else {
      col = body ?? SizedBox();
    }
    return Container(
      width: __viewWidth,
      height: __viewHeight,
      color: backgroundColor ?? Colors.white,
      child: col,
    );
  }
}

/// A Material card: a rounded, colored surface with padding around its child.
/// Mirrors `material`'s [Card].
class Card extends StatelessWidget {
  var color;
  var child;
  var margin;
  Card({this.color, this.child, this.margin});
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.all(8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(8.0)),
        child: child,
      ),
    );
  }
}

/// A filled, tappable Material button with a label, mirroring `material`'s
/// [ElevatedButton].
class ElevatedButton extends StatelessWidget {
  var onPressed;
  var child;
  var color;
  ElevatedButton({this.onPressed, this.child, this.color});
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        color: color ?? Colors.blue,
        padding: EdgeInsets.symmetric(20.0, 12.0),
        alignment: Alignment.center(),
        child: child,
      ),
    );
  }
}

/// A flat, tappable text button, mirroring `material`'s [TextButton].
class TextButton extends StatelessWidget {
  var onPressed;
  var child;
  TextButton({this.onPressed, this.child});
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Padding(padding: EdgeInsets.symmetric(16.0, 8.0), child: child),
    );
  }
}
