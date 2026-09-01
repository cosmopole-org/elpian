// =============================================================================
// flutter.js — FL: drive an embedded, real Flutter engine from an Elpian VM
// =============================================================================
//
// This is the guest half of the **Flutter UI bridge** — the twin of
// `godot.js`/`godot.dart`, but targeting a real `libflutter` engine embedded in
// the GDExtension (see `extension/src/flutter_controller.*` and
// `godot/FLUTTER.md`) instead of ClassDB. Where `GD` reaches every Godot class
// reflectively, `FL` speaks a small **declarative widget-tree op protocol**: the
// guest describes a widget tree as plain data, ships it over the `flutter.op`
// seam, and a fixed AOT-compiled Flutter "interpreter app" running inside the
// embedded engine reconciles that data into real Flutter widgets and paints
// them. No JIT, no codegen on the guest side — App-Store-legal, exactly like the
// rest of this repo.
//
//     import 'flutter.js';
//
//     var count = 0;
//     function App() {
//       return FL.scaffold({
//         appBar: FL.appBar(FL.text('Counter')),
//         body: FL.center(FL.column([
//           FL.text('Taps: ' + count, { size: 32 }),
//           FL.filledButton('Tap me', function () { count = count + 1; }),
//         ])),
//       });
//     }
//     var view = FL.mount(GD.host(), App, { design: [720, 1280] });
//
// The framework owns the render loop: `mount` takes a *builder* (a function
// returning the current widget tree), calls it for the first paint, and calls
// it again after every widget event — so a handler just mutates the state the
// builder reads (here `count`) and returns. State changed from outside an event
// (a timer, a network reply) calls `view.update()` (or `view.setState(fn)`).
//
// Composition: this prelude is layered *after* `godot.js` (an `import
// 'flutter.js';` line pulls it in), so it reuses that prelude's callback
// registry (`__gdRegisterCb` / `__gdCallbacks`) and marshaling. Widget event
// handlers therefore route back through the very same namespaced-callable path
// the Godot bridge uses: a handler becomes a `{"callable": cbId}` wire tag, the
// Rust VmManager rewrites the id into the owning VM's namespace, the C++
// FlutterController queues `(cb, args)` on an engine event, and the node flushes
// it as `__godotDispatch([cb, [args…]])` — which reaches the right VM even deep
// in a spawned subtree. One dispatch path, one sandbox model, for both UIs.
//
// ---------------------------------------------------------------------------
// The op protocol (mirrors godot.op — one seam, `flutter.op`/`flutter.batch`)
// ---------------------------------------------------------------------------
//   {"newview": true, "def": id, "parent": {"ref": nodeHandle}, "opts": {…}}
//                                     spin up an engine + a surface node under
//                                     `parent` (a Godot node in the VM sandbox)
//   {"render": viewId, "tree": <serialized widget tree>}
//                                     reconcile the view to this widget tree
//                                     (emitted by the framework's flush, not by
//                                     the app directly)
//   {"call": viewId, "channel": s, "msg": v}
//                                     send a raw platform message to the app
//   {"resize": viewId, "size": [w,h], "dpr": r}  drive metrics explicitly
//   {"disposeview": viewId}           tear the engine + surface down
//
// A serialized widget node is `{"t": type, "p": props, "c": [children…]}` (plus
// optional `"k": key for keyed reconciliation). Event handlers inside `p` are
// replaced with `{"callable": cbId}` tags at render time (see __flReify).

// The set of engine views this VM owns.
var __flViews = {};
var __flNextView = 1;

// ---------------------------------------------------------------------------
// Widget construction — every widget is just `{t, p, c}` data
// ---------------------------------------------------------------------------

// The universal element factory: __flEl('Padding', {all: 8}, [child]). The AOT
// interpreter app owns the `type -> real Flutter widget` mapping, so new widget
// types need no change here — only in the app.
function __flEl(type, props, children) {
  let node = { t: type, p: props == null ? {} : props };
  if (children != null) {
    // A list of children stays a list; a single child (a widget map or a bare
    // string) is wrapped. Use the VM's neutral type tag, never `.length` — a
    // widget map is not a list and probing it for `.length` is an error.
    if (__isType(children, "list")) {
      node.c = children;
    } else {
      node.c = [children];
    }
  }
  return node;
}

// ---------------------------------------------------------------------------
// Reify a tree for the wire: turn function-valued props into callable tags,
// reusing this view's callback slots across renders so re-rendering a tree does
// not leak an unbounded number of cb ids (the retained-reconciliation trick —
// the same idea react.js uses for its host callbacks).
// ---------------------------------------------------------------------------

function __flReify(view, node) {
  return __flReifyValue(view, node);
}

// Reify ANY value for the wire, so an event handler or a widget is reachable in
// EVERY position — a prop value, an element of a prop array (`children`,
// `actions`, `slivers`, `tabs`, …), or a value nested in a prop map. This is
// what makes the guest side complete by construction: any widget type built
// with `FL.el(type, props, children)` and any handler on any prop is expressed
// uniformly, with no per-widget code here.
//
//   * a function            → a `{callable: id}` tag (a durable slot, reused
//                             across renders so cb ids stay bounded);
//   * a widget node (has a string `t`) → reified {t, k?, p, c};
//   * a list                → each element reified;
//   * any other map          → each value reified (catches handlers/widgets
//                             nested inside a value object);
//   * a scalar               → passed through.
function __flReifyValue(view, v) {
  if (v == null) {
    return null;
  }
  // Use the VM's neutral type tags (list/map/function) — never `.length`, since
  // a map is not an array even if it answers to a length probe.
  if (__isType(v, "function")) {
    return { callable: __flSlot(view, v) };
  }
  if (__isType(v, "list")) {
    let arr = [];
    for (let i = 0; i < v.length; i++) {
      arr.push(__flReifyValue(view, v[i]));
    }
    return arr;
  }
  if (__isType(v, "map")) {
    // Widget node: a map carrying a string type tag `t`.
    if (__isType(v.t, "string")) {
      let out = { t: v.t };
      if (v.k != null) {
        out.k = v.k;
      }
      if (v.p != null) {
        let p = {};
        for (let key in v.p) {
          p[key] = __flReifyValue(view, v.p[key]);
        }
        out.p = p;
      }
      if (v.c != null) {
        let kids = [];
        for (let i = 0; i < v.c.length; i++) {
          kids.push(__flReifyValue(view, v.c[i]));
        }
        out.c = kids;
      }
      return out;
    }
    // Any other map (a value object): reify each value so a handler or widget
    // nested inside it (a custom decoration, a route map, …) is still reached.
    let m = {};
    for (let key in v) {
      m[key] = __flReifyValue(view, v[key]);
    }
    return m;
  }
  // Scalars (number / string / bool) pass through.
  return v;
}

// Hand back a stable cb id for a handler in this render pass, reusing a slot
// allocated on a previous render when possible (so cb ids stay bounded by the
// tree's peak handler count instead of growing every frame).
//
// The durable closure registered here is the framework's event driver: it runs
// the widget's current handler (which only MUTATES app state) and then asks the
// framework to re-render (`__flSchedule`). This "handler mutates, framework
// renders" split is exactly VReact's setState → drain model, and it is load
// bearing: the durable closure is created once at top level, so the re-render's
// `view`-method call is never lexically inside a dispatch-time closure — the one
// shape that trips the front-end's closure capture on a resumed turn.
function __flSlot(view, fn) {
  let idx = view._hidx;
  view._hidx = idx + 1;
  if (idx < view._handlers.length) {
    view._handlers[idx] = fn;
    return view._cbids[idx];
  }
  view._handlers.push(fn);
  let cbid = __gdRegisterCb(function (a) {
    let handler = view._handlers[idx];
    if (handler != null) {
      handler(a);
    }
    __flSchedule(view);
  });
  view._cbids.push(cbid);
  return cbid;
}

// Coalesce a re-render: mark the view dirty and, if no flush is already queued,
// schedule ONE on the VM event loop. Many events in a turn collapse to a single
// reify + `flutter.op` crossing at the next microtask.
function __flSchedule(view) {
  if (view._scheduled) {
    return;
  }
  view._scheduled = true;
  __later(function () {
    view._scheduled = false;
    __flFlush(view);
  });
}

// The framework render step: build the tree from the app's builder, reify it,
// and ship it. A top-level function (never a method reached from a dispatch-time
// closure) so the reify's engine crossing runs on solid ground.
function __flFlush(view) {
  if (view.builder == null) {
    return;
  }
  view._hidx = 0;
  let reified = __flReify(view, view.builder());
  askHost("flutter.op", [{ render: view.id, tree: reified }]);
}

// ---------------------------------------------------------------------------
// FLView — one embedded Flutter engine + one surface node in the scene
// ---------------------------------------------------------------------------

class FLView {
  constructor(id, builder) {
    this.id = id;
    this.builder = builder; // () -> root widget tree, called by the framework
    this._handlers = [];
    this._cbids = [];
    this._hidx = 0;
    this._scheduled = false;
  }

  // Request a re-render. Handlers normally never call this — mutating app state
  // and returning is enough, since the framework re-renders after every event —
  // but a state change from OUTSIDE an event (a `GTimer` tick, a network reply)
  // calls `update()` to schedule a coalesced flush.
  update() {
    __flSchedule(this);
  }

  // Flutter-style convenience: run `fn` (mutate state), then re-render.
  setState(fn) {
    if (fn != null) {
      fn();
    }
    __flSchedule(this);
  }

  // Swap the root builder and re-render (e.g. navigate to another screen).
  setBuilder(builder) {
    this.builder = builder;
    __flSchedule(this);
  }

  // Send a raw platform-channel message to the app (escape hatch for custom
  // channels the interpreter app understands).
  call(channel, msg) {
    return __gdUnmarshal(askHost("flutter.op", [{ call: this.id, channel: channel, msg: msg }]));
  }

  // Explicitly drive window metrics (normally the surface node reports these
  // from its own resize/DPI automatically).
  resize(w, h, dpr) {
    return __gdUnmarshal(askHost("flutter.op", [{ resize: this.id, size: [w, h], dpr: dpr }]));
  }

  // Tear down the engine and remove the surface node.
  dispose() {
    delete __flViews["v" + this.id];
    return __gdUnmarshal(askHost("flutter.op", [{ disposeview: this.id }]));
  }
}

// ===========================================================================
// Canvas / CustomPainter — the full dart:ui drawing surface, as a display list.
// ===========================================================================
//
// A painter is recorded to a serializable **display list** (a list of op maps)
// exactly the way the elpis protocol / `dart/src/dart_ui.rs` record a `dart:ui`
// scene: the guest issues Canvas calls into an `FLCanvas`, they become pure
// data, and the host's `_ReplayPainter` replays them onto the REAL Flutter
// `Canvas`. No closures live in the list, so it ships as plain data and repaints
// on any re-render.
//
//     FL.customPaint([300, 200], function (cv) {
//       var p = FL.paint({ color: [1, 0, 0, 1], style: 'stroke', strokeWidth: 4 });
//       cv.drawCircle(150, 100, 60, p);
//       var path = FL.path().moveTo(0, 0).lineTo(300, 200).close();
//       cv.drawPath(path, FL.paint({ color: [0, 0, 1, 1] }));
//     })
//
// Geometry on the wire: Offset = [x,y]; Rect = [left,top,right,bottom] (LTRB —
// use FL.ltwh(l,t,w,h) if you think in width/height); RRect = {rect:[…],
// radius:n} or {rect, tl,tr,bl,br}; Color = [r,g,b,a] (0..1) or a 0xAARRGGBB int.

// Normalize a path argument to plain data (an FLPath, or an already-plain map).
function __flPathData(p) {
  if (p == null) {
    return null;
  }
  if (p._verbs != null) {
    return { verbs: p._verbs, fillType: p._fillType };
  }
  return p;
}

// A Path builder — records verbs; every dart:ui Path method is present.
class FLPath {
  constructor() {
    this._verbs = [];
    this._fillType = "nonZero";
  }
  moveTo(x, y) { this._verbs.push(["moveTo", x, y]); return this; }
  lineTo(x, y) { this._verbs.push(["lineTo", x, y]); return this; }
  relativeMoveTo(dx, dy) { this._verbs.push(["rMoveTo", dx, dy]); return this; }
  relativeLineTo(dx, dy) { this._verbs.push(["rLineTo", dx, dy]); return this; }
  quadraticBezierTo(x1, y1, x2, y2) { this._verbs.push(["quadTo", x1, y1, x2, y2]); return this; }
  relativeQuadraticBezierTo(x1, y1, x2, y2) { this._verbs.push(["rQuadTo", x1, y1, x2, y2]); return this; }
  cubicTo(x1, y1, x2, y2, x3, y3) { this._verbs.push(["cubicTo", x1, y1, x2, y2, x3, y3]); return this; }
  relativeCubicTo(x1, y1, x2, y2, x3, y3) { this._verbs.push(["rCubicTo", x1, y1, x2, y2, x3, y3]); return this; }
  conicTo(x1, y1, x2, y2, w) { this._verbs.push(["conicTo", x1, y1, x2, y2, w]); return this; }
  relativeConicTo(x1, y1, x2, y2, w) { this._verbs.push(["rConicTo", x1, y1, x2, y2, w]); return this; }
  arcTo(rect, startAngle, sweepAngle, forceMoveTo) {
    this._verbs.push(["arcTo", rect, startAngle, sweepAngle, forceMoveTo == true]);
    return this;
  }
  arcToPoint(x, y, opts) {
    let o = opts == null ? {} : opts;
    this._verbs.push(["arcToPoint", x, y, o.radiusX == null ? 0 : o.radiusX, o.radiusY == null ? 0 : o.radiusY, o.rotation == null ? 0 : o.rotation, o.largeArc == true, o.clockwise != false]);
    return this;
  }
  addRect(rect) { this._verbs.push(["addRect", rect]); return this; }
  addRRect(rrect) { this._verbs.push(["addRRect", rrect]); return this; }
  addOval(rect) { this._verbs.push(["addOval", rect]); return this; }
  addArc(rect, startAngle, sweepAngle) { this._verbs.push(["addArc", rect, startAngle, sweepAngle]); return this; }
  addPolygon(points, close) { this._verbs.push(["addPolygon", points, close == true]); return this; }
  addPath(path, dx, dy) { this._verbs.push(["addPath", __flPathData(path), dx == null ? 0 : dx, dy == null ? 0 : dy]); return this; }
  close() { this._verbs.push(["close"]); return this; }
  reset() { this._verbs = []; return this; }
  fillType(t) { this._fillType = t; return this; }
  data() { return { verbs: this._verbs, fillType: this._fillType }; }
}

// The Canvas recorder — every dart:ui Canvas method, each pushing one op.
class FLCanvas {
  constructor() {
    this._ops = [];
  }
  // ---- layers / transform / clip ----
  save() { this._ops.push({ op: "save" }); return this; }
  saveLayer(rect, paint) { this._ops.push({ op: "saveLayer", rect: rect, paint: paint }); return this; }
  restore() { this._ops.push({ op: "restore" }); return this; }
  restoreToCount(count) { this._ops.push({ op: "restoreToCount", count: count }); return this; }
  translate(dx, dy) { this._ops.push({ op: "translate", dx: dx, dy: dy }); return this; }
  scale(sx, sy) { this._ops.push({ op: "scale", sx: sx, sy: sy == null ? sx : sy }); return this; }
  rotate(radians) { this._ops.push({ op: "rotate", radians: radians }); return this; }
  skew(sx, sy) { this._ops.push({ op: "skew", sx: sx, sy: sy }); return this; }
  transform(matrix16) { this._ops.push({ op: "transform", matrix: matrix16 }); return this; }
  clipRect(rect, opts) {
    let o = opts == null ? {} : opts;
    this._ops.push({ op: "clipRect", rect: rect, clipOp: o.op == null ? "intersect" : o.op, aa: o.aa != false });
    return this;
  }
  clipRRect(rrect, aa) { this._ops.push({ op: "clipRRect", rrect: rrect, aa: aa != false }); return this; }
  clipPath(path, aa) { this._ops.push({ op: "clipPath", path: __flPathData(path), aa: aa != false }); return this; }
  // ---- draws ----
  drawColor(color, blendMode) { this._ops.push({ op: "drawColor", color: color, blend: blendMode == null ? "srcOver" : blendMode }); return this; }
  drawPaint(paint) { this._ops.push({ op: "drawPaint", paint: paint }); return this; }
  drawLine(p1, p2, paint) { this._ops.push({ op: "drawLine", p1: p1, p2: p2, paint: paint }); return this; }
  drawRect(rect, paint) { this._ops.push({ op: "drawRect", rect: rect, paint: paint }); return this; }
  drawRRect(rrect, paint) { this._ops.push({ op: "drawRRect", rrect: rrect, paint: paint }); return this; }
  drawDRRect(outer, inner, paint) { this._ops.push({ op: "drawDRRect", outer: outer, inner: inner, paint: paint }); return this; }
  drawOval(rect, paint) { this._ops.push({ op: "drawOval", rect: rect, paint: paint }); return this; }
  drawCircle(cx, cy, radius, paint) { this._ops.push({ op: "drawCircle", cx: cx, cy: cy, radius: radius, paint: paint }); return this; }
  drawArc(rect, startAngle, sweepAngle, useCenter, paint) { this._ops.push({ op: "drawArc", rect: rect, start: startAngle, sweep: sweepAngle, useCenter: useCenter == true, paint: paint }); return this; }
  drawPath(path, paint) { this._ops.push({ op: "drawPath", path: __flPathData(path), paint: paint }); return this; }
  drawImage(src, dx, dy, paint) { this._ops.push({ op: "drawImage", src: src, dx: dx, dy: dy, paint: paint }); return this; }
  drawImageRect(src, srcRect, dstRect, paint) { this._ops.push({ op: "drawImageRect", src: src, srcRect: srcRect, dstRect: dstRect, paint: paint }); return this; }
  drawImageNine(src, center, dstRect, paint) { this._ops.push({ op: "drawImageNine", src: src, center: center, dstRect: dstRect, paint: paint }); return this; }
  drawParagraph(paragraph, dx, dy) { this._ops.push({ op: "drawParagraph", paragraph: paragraph, dx: dx, dy: dy }); return this; }
  drawPoints(mode, points, paint) { this._ops.push({ op: "drawPoints", mode: mode == null ? "points" : mode, points: points, paint: paint }); return this; }
  drawShadow(path, color, elevation, transparentOccluder) { this._ops.push({ op: "drawShadow", path: __flPathData(path), color: color, elevation: elevation, transparentOccluder: transparentOccluder == true }); return this; }
  drawVertices(vertices, blendMode, paint) { this._ops.push({ op: "drawVertices", vertices: vertices, blend: blendMode == null ? "srcOver" : blendMode, paint: paint }); return this; }
  drawAtlas(src, transforms, rects, colors, blendMode, cullRect, paint) { this._ops.push({ op: "drawAtlas", src: src, transforms: transforms, rects: rects, colors: colors, blend: blendMode, cullRect: cullRect, paint: paint }); return this; }
}

// ---------------------------------------------------------------------------
// FL — the facade
// ---------------------------------------------------------------------------

class FL {
  // Mount a Flutter UI under a Godot node `parent` (any GObj in this VM's
  // sandbox). `builder` is a function returning the root widget tree; the
  // framework calls it now and after every event, so a handler need only mutate
  // the state the builder reads. `opts`: { design: [w,h], transparent: bool,
  // gpu: bool }. Returns an FLView. The C++ controller creates the engine and a
  // surface node child of `parent`, so the UI composites over whatever 2D/3D
  // world lives there.
  //
  //     var count = 0;
  //     function App() {
  //       return FL.scaffold({ body: FL.center(FL.column([
  //         FL.text('Taps: ' + count, { size: 32 }),
  //         FL.filledButton('Tap me', function () { count = count + 1; }),
  //       ])) });
  //     }
  //     var view = FL.mount(GD.host(), App, { design: [720, 1280] });
  static mount(parent, builder, opts) {
    let id = __flNextView;
    __flNextView = __flNextView + 1;
    let ref = parent == null ? null : { ref: parent.id };
    // Detect whether the embedded Flutter engine is actually available: a
    // successful newview replies with the (numeric) view handle; a build with
    // no libflutter (the placeholder, and every web export) replies with an
    // error which the front-end surfaces as a throw. Return null so callers can
    // fall back to a native UI (see bridge/project/scripts/flutter_3d_demo.js).
    let ok = false;
    try {
      let reply = __gdUnmarshal(askHost("flutter.op", [{ newview: true, def: id, parent: ref, opts: opts == null ? {} : opts }]));
      ok = __isType(reply, "number");
    } catch (e) {
      ok = false;
    }
    if (!ok) {
      return null;
    }
    let view = new FLView(id, builder);
    __flViews["v" + id] = view;
    __flFlush(view); // initial paint
    return view;
  }

  // True when the embedded Flutter engine is available in this build. Probes by
  // mounting a throwaway view under `parent` and disposing it.
  static available(parent) {
    let v = FL.mount(parent, function () { return FL.el("SizedBox", {}); }, {});
    if (v == null) {
      return false;
    }
    v.dispose();
    return true;
  }

  // Raw op escape hatch, symmetrical with GD.op.
  static op(m) {
    return __gdUnmarshal(askHost("flutter.op", [m]));
  }

  // ---- widget sugar (thin: every one is __flEl(type, props, children)) -----
  static el(t, p, c) {
    return __flEl(t, p, c);
  }
  static app(p) {
    return __flEl("MaterialApp", p);
  }
  static scaffold(p) {
    return __flEl("Scaffold", p);
  }
  static appBar(title) {
    return __flEl("AppBar", { title: title });
  }
  static text(s, p) {
    return __flEl("Text", { data: s, style: p == null ? {} : p });
  }
  static column(children) {
    return __flEl("Column", {}, children);
  }
  static row(children) {
    return __flEl("Row", {}, children);
  }
  static stack(children) {
    return __flEl("Stack", {}, children);
  }
  static center(child) {
    return __flEl("Center", {}, [child]);
  }
  static padding(all, child) {
    return __flEl("Padding", { all: all }, [child]);
  }
  static container(p, child) {
    return __flEl("Container", p, child == null ? null : [child]);
  }
  static sizedBox(w, h, child) {
    return __flEl("SizedBox", { width: w, height: h }, child == null ? null : [child]);
  }
  static expanded(child) {
    return __flEl("Expanded", {}, [child]);
  }
  static listView(children) {
    return __flEl("ListView", {}, children);
  }
  static image(src, p) {
    return __flEl("Image", { src: src, opts: p == null ? {} : p });
  }
  static icon(name, p) {
    return __flEl("Icon", { name: name, opts: p == null ? {} : p });
  }
  static filledButton(label, onTap) {
    return __flEl("FilledButton", { label: label, onTap: onTap });
  }
  static textButton(label, onTap) {
    return __flEl("TextButton", { label: label, onTap: onTap });
  }
  static iconButton(name, onTap) {
    return __flEl("IconButton", { name: name, onTap: onTap });
  }
  static textField(p) {
    return __flEl("TextField", p == null ? {} : p);
  }
  static switchTile(value, onChanged) {
    return __flEl("Switch", { value: value, onChanged: onChanged });
  }
  static slider(value, onChanged, p) {
    let props = p == null ? {} : p;
    props.value = value;
    props.onChanged = onChanged;
    return __flEl("Slider", props);
  }

  // More content / layout sugar (all thin over __flEl; FL.el reaches anything
  // the host registry knows, so this list is convenience, not the coverage
  // boundary — see FLUTTER.md).
  static align(alignment, child) {
    return __flEl("Align", { alignment: alignment }, [child]);
  }
  static positioned(p, child) {
    return __flEl("Positioned", p, [child]);
  }
  static wrap(children, p) {
    return __flEl("Wrap", p == null ? {} : p, children);
  }
  static flexible(child, flex) {
    return __flEl("Flexible", { flex: flex == null ? 1 : flex }, [child]);
  }
  static aspectRatio(ratio, child) {
    return __flEl("AspectRatio", { aspectRatio: ratio }, [child]);
  }
  static opacity(value, child) {
    return __flEl("Opacity", { opacity: value }, [child]);
  }
  static clip(shape, child) {
    return __flEl(shape == null ? "ClipRRect" : shape, {}, [child]);
  }
  static card(child, p) {
    return __flEl("Card", p == null ? {} : p, [child]);
  }
  static listTile(p) {
    return __flEl("ListTile", p == null ? {} : p);
  }
  static chip(label, p) {
    let props = p == null ? {} : p;
    props.label = label;
    return __flEl("Chip", props);
  }
  static checkbox(value, onChanged) {
    return __flEl("Checkbox", { value: value, onChanged: onChanged });
  }
  static radio(value, groupValue, onChanged) {
    return __flEl("Radio", { value: value, groupValue: groupValue, onChanged: onChanged });
  }
  static dropdown(value, items, onChanged) {
    return __flEl("DropdownButton", { value: value, items: items, onChanged: onChanged });
  }
  static scroll(child, p) {
    return __flEl("SingleChildScrollView", p == null ? {} : p, [child]);
  }
  static gridView(children, p) {
    return __flEl("GridView", p == null ? {} : p, children);
  }
  static pageView(children, p) {
    return __flEl("PageView", p == null ? {} : p, children);
  }
  static tabs(tabs, views, p) {
    let props = p == null ? {} : p;
    props.tabs = tabs;
    props.views = views;
    return __flEl("TabScaffold", props);
  }
  static circularProgress(p) {
    return __flEl("CircularProgressIndicator", p == null ? {} : p);
  }
  static linearProgress(p) {
    return __flEl("LinearProgressIndicator", p == null ? {} : p);
  }
  static divider(p) {
    return __flEl("Divider", p == null ? {} : p);
  }
  static circleAvatar(p) {
    return __flEl("CircleAvatar", p == null ? {} : p);
  }
  static tooltip(message, child) {
    return __flEl("Tooltip", { message: message }, [child]);
  }
  static hero(tag, child) {
    return __flEl("Hero", { tag: tag }, [child]);
  }
  static animatedContainer(p, child) {
    return __flEl("AnimatedContainer", p == null ? {} : p, child == null ? null : [child]);
  }

  // =========================================================================
  // The full event surface. Every gesture / pointer / keyboard / focus / drag
  // / scroll / value callback is reachable — a handler is just a function-valued
  // prop, converted to a `{callable}` tag by the reifier and dispatched back
  // through the same path Godot signals use. The host decodes each callback's
  // details into a JSON argument the handler receives.
  // =========================================================================

  // GestureDetector — the complete tap / double-tap / long-press / drag / pan /
  // scale / force-press / secondary / tertiary callback set. Pass any subset in
  // `handlers`; unknown keys are ignored by the host.
  //
  //   onTapDown onTapUp onTap onTapCancel
  //   onSecondaryTap onSecondaryTapDown onSecondaryTapUp onSecondaryTapCancel
  //   onTertiaryTapDown onTertiaryTapUp onTertiaryTapCancel
  //   onDoubleTap onDoubleTapDown onDoubleTapCancel
  //   onLongPress onLongPressStart onLongPressMoveUpdate onLongPressUp onLongPressEnd
  //   onVerticalDragStart onVerticalDragUpdate onVerticalDragEnd onVerticalDragDown onVerticalDragCancel
  //   onHorizontalDragStart onHorizontalDragUpdate onHorizontalDragEnd onHorizontalDragDown onHorizontalDragCancel
  //   onPanStart onPanUpdate onPanEnd onPanDown onPanCancel
  //   onScaleStart onScaleUpdate onScaleEnd
  //   onForcePressStart onForcePressPeak onForcePressUpdate onForcePressEnd
  static gestures(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("GestureDetector", p);
  }

  // InkWell — Material tap feedback: onTap onTapDown onTapUp onTapCancel
  // onDoubleTap onLongPress onSecondaryTap onHover onFocusChange onHighlightChanged.
  static inkWell(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("InkWell", p);
  }

  // Listener — raw pointer events: onPointerDown onPointerMove onPointerUp
  // onPointerHover onPointerCancel onPointerSignal onPointerPanZoomStart
  // onPointerPanZoomUpdate onPointerPanZoomEnd.
  static listener(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("Listener", p);
  }

  // MouseRegion — hover: onEnter onExit onHover (+ cursor).
  static mouseRegion(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("MouseRegion", p);
  }

  // Focus — keyboard focus + key events: onFocusChange onKeyEvent (+ autofocus).
  static focus(child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    return __flEl("Focus", p);
  }

  // KeyboardListener — every hardware key: onKeyEvent (down/up/repeat, with
  // logical/physical key, character, and modifier flags in the details).
  static keyboard(child, onKeyEvent, p) {
    let props = p == null ? {} : p;
    props.child = child;
    props.onKeyEvent = onKeyEvent;
    return __flEl("KeyboardListener", props);
  }

  // NotificationListener — scroll & custom notifications bubbling up:
  // onNotification (ScrollStart/Update/End/Metrics, OverscrollNotification, …).
  static notificationListener(child, onNotification) {
    return __flEl("NotificationListener", { child: child, onNotification: onNotification });
  }

  // Draggable / DragTarget — drag & drop.
  //   Draggable handlers: onDragStarted onDragUpdate onDragEnd onDraggableCanceled onDragCompleted
  //   DragTarget handlers: onWillAccept onAccept onAcceptWithDetails onLeave onMove
  static draggable(child, feedback, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = child;
    p.feedback = feedback;
    return __flEl("Draggable", p);
  }
  static dragTarget(builderChild, handlers) {
    let p = handlers == null ? {} : handlers;
    p.child = builderChild;
    return __flEl("DragTarget", p);
  }

  // Dismissible — swipe to dismiss: onDismissed confirmDismiss onResize onUpdate.
  static dismissible(key, child, handlers) {
    let p = handlers == null ? {} : handlers;
    p.dismissKey = key;
    p.child = child;
    return __flEl("Dismissible", p);
  }

  // RefreshIndicator — pull to refresh: onRefresh.
  static refreshIndicator(child, onRefresh) {
    return __flEl("RefreshIndicator", { child: child, onRefresh: onRefresh });
  }

  // PopScope — intercept back navigation: onPopInvoked (+ canPop).
  static popScope(child, onPopInvoked, canPop) {
    return __flEl("PopScope", { child: child, onPopInvoked: onPopInvoked, canPop: canPop });
  }

  // Form / fields — onChanged onSaved validator onFieldSubmitted onEditingComplete.
  static form(child, onChanged) {
    return __flEl("Form", { child: child, onChanged: onChanged });
  }

  // =========================================================================
  // Canvas / CustomPainter
  // =========================================================================

  // Paint a custom drawing at `size` = [w, h]. `painter(cv)` receives an
  // FLCanvas and issues drawing ops; they are recorded to a display list the
  // host replays onto the real Flutter Canvas. `opts` may add `child`,
  // `foreground: true` (draw over the child), `isComplex`, `willChange`.
  static customPaint(size, painter, opts) {
    let cv = new FLCanvas();
    if (painter != null) {
      painter(cv);
    }
    let p = opts == null ? {} : opts;
    p.size = size;
    if (p.foreground == true) {
      p.foregroundOps = cv._ops;
    } else {
      p.ops = cv._ops;
    }
    return __flEl("CustomPaint", p);
  }

  // Alias reading like dart:ui's PictureRecorder → Canvas flow.
  static canvas(size, painter, opts) {
    return FL.customPaint(size, painter, opts);
  }

  // A Paint descriptor. Recognized keys: color, blendMode, style('fill'|'stroke'),
  // strokeWidth, strokeCap('butt'|'round'|'square'), strokeJoin('miter'|'round'|
  // 'bevel'), strokeMiterLimit, isAntiAlias, shader (a gradient descriptor),
  // maskFilter ({style:'normal'|'solid'|'outer'|'inner', sigma}), blur (sigma
  // shortcut), colorFilter, filterQuality, invertColors.
  static paint(props) {
    return props == null ? {} : props;
  }

  // A fresh Path builder.
  static path() {
    return new FLPath();
  }

  // Geometry helpers.
  static ltwh(l, t, w, h) {
    return [l, t, l + w, t + h];
  }
  static rrect(rect, radius) {
    return { rect: rect, radius: radius };
  }

  // Shaders (a Paint's `shader`).
  static linearGradient(from, to, colors, stops, tileMode) {
    return { type: "linear", from: from, to: to, colors: colors, stops: stops, tileMode: tileMode };
  }
  static radialGradient(center, radius, colors, stops, tileMode) {
    return { type: "radial", center: center, radius: radius, colors: colors, stops: stops, tileMode: tileMode };
  }
  static sweepGradient(center, colors, stops, startAngle, endAngle) {
    return { type: "sweep", center: center, colors: colors, stops: stops, startAngle: startAngle, endAngle: endAngle };
  }

  // A Paragraph descriptor for cv.drawParagraph: { text, maxWidth, style,
  // align('left'|'center'|'right'|'justify') }.
  static paragraph(text, maxWidth, style, align) {
    return { text: text, maxWidth: maxWidth, style: style == null ? {} : style, align: align };
  }
}
