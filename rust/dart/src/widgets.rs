//! The **widget layer**: a Flutter-shaped widget framework, written in the Dart
//! subset the front-end (the `dart2elpian` crate) compiles, so *real widget
//! code* — `StatelessWidget`/`StatefulWidget` with `build()` methods and nested
//! child widgets — runs on the Elpian VM and drives the `dart:ui` scene the
//! engine rasterizes.
//!
//! # How it fits the pipeline
//!
//! The user's app is authored as ordinary Flutter-style Dart:
//!
//! ```dart
//! class Counter extends StatefulWidget {
//!   State createState() { return CounterState(); }
//! }
//! class CounterState extends State {
//!   int count = 0;
//!   Widget build() {
//!     return GestureDetector(
//!       onTap: () { setState(() { count = count + 1; }); },
//!       child: Text("count: $count"),
//!     );
//!   }
//! }
//! void main() { runApp(Center(child: Counter())); }
//! ```
//!
//! [`compose`] prepends [`WIDGET_PRELUDE`] (this framework) to that source and
//! the whole thing goes through the real Dart → AST → bytecode → VM path. The
//! framework owns the engine's binding handlers (`onDrawFrame`,
//! `onPointerEvent`), so on each vsync it **rebuilds** the widget tree from the
//! root, **lays it out** under constraints, and **paints** it into a `dart:ui`
//! recorder; the resulting scene is what [`crate::runtime::DartRuntime`] hands to
//! the host rasterizer. Pointer-ups are hit-tested against the laid-out
//! `GestureDetector` rects, so taps re-enter guest code, mutate `State`, and
//! `setState` requests the next frame — the full event → VM → scene → pixels loop.
//!
//! # Scope of this slice
//!
//! A load-bearing subset of the framework: `StatelessWidget`, `StatefulWidget` +
//! `State` (with persistent state across frames, matched by build order),
//! `runApp`, and the layout widgets `Container`, `SizedBox`, `Padding`, `Center`,
//! `Align`, `Column`, `Row`, `ColoredBox`, `Text`, `GestureDetector`, plus the
//! `MaterialApp`/`Scaffold` shells. Layout is a single-pass constraint model
//! (tight root constraints = the view size). Deepening — `Expanded`/`Flexible`
//! flex, `Stack`/`Positioned`, `EdgeInsets`, keyed reconciliation, and text
//! measurement from the engine — is documented follow-up.

/// The Flutter-shaped widget framework, in the compilable Dart subset. Prepended
/// to every widget app by [`compose`]. Kept in one string so the whole program
/// (framework + app) is compiled as a unit and shares one class hierarchy (so
/// `is StatelessWidget` over user classes resolves).
pub const WIDGET_PRELUDE: &str = r#"
// ---- framework runtime state (top-level globals) --------------------------
var __rootWidget = null;
var __states = [];
var __locCounter = 0;
var __hits = [];
var __needsFrame = false;
double __screenW = 400.0;
double __screenH = 800.0;

// Return `v` unless it is null, in which case the default `d`.
__or(v, d) { if (v != null) { return v; } return d; }

void __markNeedsFrame() {
  __needsFrame = true;
  askHost("dart:ui/scheduleFrame", []);
}

// ---- geometry -------------------------------------------------------------
class Size {
  double w;
  double h;
  Size(this.w, this.h);
}

// ---- widget base classes --------------------------------------------------
//
// A widget is an immutable configuration. Expansion (resolving Stateless /
// Stateful children to render widgets, re-running their `build()`) happens every
// frame and must NOT mutate the configuration — the root widget handed to
// `runApp` is retained across frames, so freezing its expansion in place would
// stop `build()` from ever re-running. Render widgets therefore keep their
// child *config* (`child` / `children`) pristine and cache the per-frame
// expansion in transient fields (`exChild` / `exKids`) that `inflate()` refreshes.
class Widget {
  // Refresh this widget's transient expanded children from its config children.
  void inflate() {}
  // Natural size under loose constraints (cw x ch available).
  Size measure(double cw, double ch) { return Size(0.0, 0.0); }
  // Emit paint ops for this widget occupying (x, y, cw, ch).
  void paint(double x, double y, double cw, double ch) {}
}

class StatelessWidget extends Widget {
  Widget build() { return null; }
}

class State {
  var widget;
  void initState() {}
  Widget build() { return null; }
  void setState(Function fn) {
    fn();
    __markNeedsFrame();
  }
}

class StatefulWidget extends Widget {
  State createState() { return null; }
}

// ---- the build/layout driver ----------------------------------------------
// Persistent State lookup, matched to a StatefulWidget by its build-order index
// (position-based reconciliation, like Flutter without keys). State survives
// across frames so counters etc. retain their value.
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

// Resolve a widget to a concrete render widget: repeatedly build Stateless /
// Stateful widgets until a render widget remains, then inflate its children.
Widget expand(Widget w) {
  var cur = w;
  var done = false;
  while (!done) {
    if (cur is StatelessWidget) {
      cur = cur.build();
    } else if (cur is StatefulWidget) {
      var st = __stateFor(cur);
      cur = st.build();
    } else {
      done = true;
    }
  }
  cur.inflate();
  return cur;
}

void runApp(Widget app) {
  __rootWidget = app;
  __markNeedsFrame();
}

// ---- engine binding handlers ----------------------------------------------
void onBeginFrame(t) {}

void onDrawFrame() {
  if (__rootWidget == null) { return; }
  __needsFrame = false;
  __locCounter = 0;
  __hits = [];
  var tree = expand(__rootWidget);
  askHost("dart:ui/PictureRecorder.beginRecording", []);
  tree.paint(0.0, 0.0, __screenW, __screenH);
  var pic = askHost("dart:ui/PictureRecorder.endRecording", []);
  var scene = askHost("dart:ui/Picture.toScene", [pic]);
  askHost("dart:ui/FlutterView.render", [scene]);
}

void onPointerEvent(e) {
  var phase = e["phase"];
  // A tap completes on pointer-up; ignore intermediate down/move.
  if (phase != "up") { return; }
  var x = e["x"];
  var y = e["y"];
  // Topmost-first: hit rects are recorded in paint order, so scan back to front.
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

// ---- leaf & layout widgets ------------------------------------------------
class Text extends Widget {
  String data;
  double size;
  int color;
  Text(this.data, {this.size, this.color});
  Size measure(double cw, double ch) {
    var s = __or(size, 16.0);
    return Size(data.length * s * 0.6, s * 1.4);
  }
  void paint(double x, double y, double cw, double ch) {
    var s = __or(size, 16.0);
    var col = __or(color, 4278190080);
    askHost("dart:ui/Canvas.drawParagraph", [data, x, y + s, s, col]);
  }
}

class SizedBox extends Widget {
  double width;
  double height;
  Widget child;
  var exChild;
  SizedBox({this.width, this.height, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) {
    var w = 0.0;
    var h = 0.0;
    if (exChild != null) {
      var cs = exChild.measure(cw, ch);
      w = cs.w;
      h = cs.h;
    }
    return Size(__or(width, w), __or(height, h));
  }
  void paint(double x, double y, double cw, double ch) {
    if (exChild != null) {
      var s = measure(cw, ch);
      exChild.paint(x, y, s.w, s.h);
    }
  }
}

class Container extends Widget {
  double width;
  double height;
  int color;
  double padding;
  Widget child;
  var exChild;
  Container({this.width, this.height, this.color, this.padding, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) {
    var pad = __or(padding, 0.0);
    var w = 0.0;
    var h = 0.0;
    if (exChild != null) {
      var cs = exChild.measure(cw - pad * 2.0, ch - pad * 2.0);
      w = cs.w + pad * 2.0;
      h = cs.h + pad * 2.0;
    }
    return Size(__or(width, w), __or(height, h));
  }
  void paint(double x, double y, double cw, double ch) {
    var s = measure(cw, ch);
    if (color != null) {
      askHost("dart:ui/Canvas.drawRect", [x, y, x + s.w, y + s.h, color]);
    }
    var pad = __or(padding, 0.0);
    if (exChild != null) {
      exChild.paint(x + pad, y + pad, s.w - pad * 2.0, s.h - pad * 2.0);
    }
  }
}

class Padding extends Widget {
  double padding;
  Widget child;
  var exChild;
  Padding({this.padding, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) {
    var pad = __or(padding, 0.0);
    if (exChild != null) {
      var cs = exChild.measure(cw - pad * 2.0, ch - pad * 2.0);
      return Size(cs.w + pad * 2.0, cs.h + pad * 2.0);
    }
    return Size(pad * 2.0, pad * 2.0);
  }
  void paint(double x, double y, double cw, double ch) {
    var pad = __or(padding, 0.0);
    if (exChild != null) {
      exChild.paint(x + pad, y + pad, cw - pad * 2.0, ch - pad * 2.0);
    }
  }
}

class ColoredBox extends Widget {
  int color;
  Widget child;
  var exChild;
  ColoredBox({this.color, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) {
    if (exChild != null) { return exChild.measure(cw, ch); }
    return Size(cw, ch);
  }
  void paint(double x, double y, double cw, double ch) {
    // A ColoredBox fills the box it is given, painting behind its child.
    if (color != null) {
      askHost("dart:ui/Canvas.drawRect", [x, y, x + cw, y + ch, color]);
    }
    if (exChild != null) {
      var s = exChild.measure(cw, ch);
      exChild.paint(x, y, s.w, s.h);
    }
  }
}

class Center extends Widget {
  Widget child;
  var exChild;
  Center({this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) { return Size(cw, ch); }
  void paint(double x, double y, double cw, double ch) {
    if (exChild != null) {
      var cs = exChild.measure(cw, ch);
      var dx = x + (cw - cs.w) / 2.0;
      var dy = y + (ch - cs.h) / 2.0;
      exChild.paint(dx, dy, cs.w, cs.h);
    }
  }
}

class Align extends Widget {
  // ax/ay in [-1, 1]: -1 = start, 0 = center, 1 = end (like Alignment).
  double ax;
  double ay;
  Widget child;
  var exChild;
  Align({this.ax, this.ay, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) { return Size(cw, ch); }
  void paint(double x, double y, double cw, double ch) {
    if (exChild != null) {
      var cs = exChild.measure(cw, ch);
      var fx = (__or(ax, 0.0) + 1.0) / 2.0;
      var fy = (__or(ay, 0.0) + 1.0) / 2.0;
      var dx = x + (cw - cs.w) * fx;
      var dy = y + (ch - cs.h) * fy;
      exChild.paint(dx, dy, cs.w, cs.h);
    }
  }
}

class Column extends Widget {
  List children;
  String mainAxisAlignment;
  String crossAxisAlignment;
  var exKids;
  Column({this.children, this.mainAxisAlignment, this.crossAxisAlignment});
  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }
  Size measure(double cw, double ch) {
    var w = 0.0;
    var h = 0.0;
    for (var c in exKids) {
      var cs = c.measure(cw, ch);
      if (cs.w > w) { w = cs.w; }
      h = h + cs.h;
    }
    return Size(w, h);
  }
  void paint(double x, double y, double cw, double ch) {
    var total = measure(cw, ch);
    var main = __or(mainAxisAlignment, "start");
    var cross = __or(crossAxisAlignment, "center");
    var cy = y;
    if (main == "center") { cy = y + (ch - total.h) / 2.0; }
    if (main == "end") { cy = y + (ch - total.h); }
    for (var c in exKids) {
      var cs = c.measure(cw, ch);
      var cx = x;
      if (cross == "center") { cx = x + (cw - cs.w) / 2.0; }
      if (cross == "end") { cx = x + (cw - cs.w); }
      c.paint(cx, cy, cs.w, cs.h);
      cy = cy + cs.h;
    }
  }
}

class Row extends Widget {
  List children;
  String mainAxisAlignment;
  String crossAxisAlignment;
  var exKids;
  Row({this.children, this.mainAxisAlignment, this.crossAxisAlignment});
  void inflate() {
    exKids = [];
    if (children != null) {
      for (var c in children) { exKids.add(expand(c)); }
    }
  }
  Size measure(double cw, double ch) {
    var w = 0.0;
    var h = 0.0;
    for (var c in exKids) {
      var cs = c.measure(cw, ch);
      w = w + cs.w;
      if (cs.h > h) { h = cs.h; }
    }
    return Size(w, h);
  }
  void paint(double x, double y, double cw, double ch) {
    var total = measure(cw, ch);
    var main = __or(mainAxisAlignment, "start");
    var cross = __or(crossAxisAlignment, "center");
    var cx = x;
    if (main == "center") { cx = x + (cw - total.w) / 2.0; }
    if (main == "end") { cx = x + (cw - total.w); }
    for (var c in exKids) {
      var cs = c.measure(cw, ch);
      var cy = y;
      if (cross == "center") { cy = y + (ch - cs.h) / 2.0; }
      if (cross == "end") { cy = y + (ch - cs.h); }
      c.paint(cx, cy, cs.w, cs.h);
      cx = cx + cs.w;
    }
  }
}

class GestureDetector extends Widget {
  Function onTap;
  Widget child;
  var exChild;
  GestureDetector({this.onTap, this.child});
  void inflate() { if (child != null) { exChild = expand(child); } else { exChild = null; } }
  Size measure(double cw, double ch) {
    if (exChild != null) { return exChild.measure(cw, ch); }
    return Size(0.0, 0.0);
  }
  void paint(double x, double y, double cw, double ch) {
    var s = measure(cw, ch);
    __hits.add({"x0": x, "y0": y, "x1": x + s.w, "y1": y + s.h, "onTap": onTap});
    if (exChild != null) { exChild.paint(x, y, s.w, s.h); }
  }
}

// ---- app shells -----------------------------------------------------------
class MaterialApp extends StatelessWidget {
  Widget home;
  MaterialApp({this.home});
  Widget build() { return home; }
}

class Scaffold extends StatelessWidget {
  Widget body;
  int backgroundColor;
  Scaffold({this.body, this.backgroundColor});
  Widget build() {
    return Container(
      color: __or(backgroundColor, 4294967295),
      width: __screenW,
      height: __screenH,
      child: body,
    );
  }
}
"#;

/// Compose a runnable program from a user's widget-app source by prepending the
/// [`WIDGET_PRELUDE`]. The user's `main()` (auto-invoked by the front-end) calls
/// `runApp(...)`; the prelude supplies the widget classes and the engine binding.
pub fn compose(app_source: &str) -> String {
    format!("{WIDGET_PRELUDE}\n{app_source}")
}

/// The full, idiomatic Flutter widget library (`flutter/flutter.dart`), authored
/// as ordinary Dart and embedded at build time. This is the library an app
/// `import`s; it defines the widget classes, painting value types, layout
/// protocol, and the engine binding. Compiled through the same front-end as the
/// app itself.
pub const FLUTTER_LIB: &str = include_str!("../flutter/flutter.dart");

/// Remove Dart library directives (`import`/`export`/`library`/`part`) from a
/// source file. The Elpian front-end has no module system: an app's
/// `import 'flutter.dart';` is satisfied by concatenating the library ahead of
/// the app (see [`compose_flutter`]), so the directive line itself is dropped.
pub fn strip_directives(src: &str) -> String {
    src.lines()
        .map(|line| {
            let t = line.trim_start();
            if t.starts_with("import ")
                || t.starts_with("export ")
                || t.starts_with("part ")
                || t == "library;"
                || t.starts_with("library ")
            {
                "" // keep line numbering stable
            } else {
                line
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// Compose a full program from an app that `import`s `flutter.dart`: the
/// [`FLUTTER_LIB`] library is placed ahead of the app (both with their library
/// directives stripped), so the whole thing — library + app — compiles as one
/// unit through the Dart → AST → bytecode → VM pipeline.
pub fn compose_flutter(app_source: &str) -> String {
    format!(
        "{}\n{}",
        strip_directives(FLUTTER_LIB),
        strip_directives(app_source)
    )
}
