// reactnative.js — the React Native / Expo widget bridge for Victor guests
// ===========================================================================
//
// This prelude is to React Native what `ui.js` is to Godot `Control` nodes and
// `flutter.js` is to the embedded Flutter engine: a guest-facing widget kit
// whose host is a **real React Native / Expo view tree**. A guest program keeps
// running entirely on the Elpian VM (all app logic stays on the VM — no JIT);
// the widgets it builds here are mirrored, over the `rn.op` seam, into genuine
// React Native components on mobile, desktop and web.
//
//   import 'godot.js';         // marshaling + callback registry + GD/G3 (for 3D)
//   import 'reactnative.js';   // the RN facade (this file)
//
// The 2D tree is React Native. The 3D world stays **Godot**: an `RN.Scene3D`
// widget is a viewport surface into an embedded Godot engine, and everything
// inside it is built with the ordinary `GD` / `G3` surface from `godot.js`
// (those calls cross the normal `godot.op` seam). So a Victor app is a 2D React
// Native widget tree with 3D Godot `Scene3D` widgets embedded anywhere in it —
// cross-platform 2D + 3D, one VM in charge.
//
// Wire protocol (mirrors the Godot op protocol so the multi-VM manager applies
// the identical sandbox stamping — see manager.rs `sanitize_op`):
//   { new: "RNView", def: id }                 create a widget, bind handle id
//   { ref: id, set: prop, value }              patch a prop
//   { ref: id, method: "add_child", args: [{ref: child}] }   structural
//   { ref: id, connect: "press", cb: cbId }    bind an event -> guest closure
//   { ref: id, free: id }                      drop a widget
//   { root: id }                               mark the app's root widget
// Handles (`def`/`ref`) and callback ids (`cb`) are namespaced per-VM by the
// manager, so a sandboxed child VM can only touch widgets in its own subtree
// and its events route back to it — the same governance the Godot host has.

// ---------------------------------------------------------------------------
// internals — ids, batch buffer, the seam
// ---------------------------------------------------------------------------

var __rnNextId = 1; // guest-side widget-handle allocator (positive ids)
var __rnBatch = null; // when non-null, ops queue here (flushed by endBatch)

function __rnAllocId() {
  var id = __rnNextId;
  __rnNextId = __rnNextId + 1;
  return id;
}

// Run one op immediately (one `rn.op` host call) or queue it when a batch is
// open. Batched ops return null — results, if any, are read after endBatch().
function __rnRun(op) {
  if (__rnBatch != null && __isType(__rnBatch, "list")) {
    __rnBatch.push(op);
    return null;
  }
  return askHost("rn.op", [op]);
}

function __rnBeginBatch() {
  if (__rnBatch == null) {
    __rnBatch = [];
  }
}

function __rnEndBatch() {
  var b = __rnBatch;
  __rnBatch = null;
  if (b == null || b.length == 0) {
    return null;
  }
  return askHost("rn.batch", [b]);
}

// Marshal a prop value into wire shape. Scalars/lists/maps pass through; a
// widget handle becomes {"ref": id}; a closure becomes an event callback id.
function __rnMarshal(v) {
  if (__isType(v, "number")) return v;
  if (__isType(v, "string")) return v;
  if (__isType(v, "bool")) return v;
  if (v == null) return null;
  if (__isType(v, "RNObj")) return { ref: v.id };
  if (__isType(v, "function")) {
    // Event handlers must travel as `connect` ops (which the manager namespaces
    // and routes back to the owning VM), never as raw props — so a stray
    // closure in a prop map is dropped here rather than silently mis-routed.
    return null;
  }
  if (__isType(v, "list")) {
    var out = [];
    var i = 0;
    while (i < v.length) {
      out.push(__rnMarshal(v[i]));
      i = i + 1;
    }
    return out;
  }
  if (__isType(v, "map")) {
    var m = {};
    var ks = keys(v);
    var j = 0;
    while (j < ks.length) {
      m[ks[j]] = __rnMarshal(v[ks[j]]);
      j = j + 1;
    }
    return m;
  }
  return v;
}

// ---------------------------------------------------------------------------
// RNObj — a retained handle to one React Native widget
// ---------------------------------------------------------------------------

class RNObj {
  constructor(id) {
    this.id = id;
    this.__isType = "RNObj";
  }

  // Patch a single prop; the host diffs and applies it to the RN component.
  set(prop, value) {
    __rnRun({ ref: this.id, set: prop, value: __rnMarshal(value) });
    return this;
  }

  // Apply a whole prop map at once (one op, host applies each key).
  props(map) {
    __rnRun({ ref: this.id, props: __rnMarshal(map) });
    return this;
  }

  get(prop) {
    return __rnRun({ ref: this.id, get: prop });
  }

  // Structural: append a child widget.
  add(child) {
    __rnRun({ ref: this.id, method: "add_child", args: [{ ref: child.id }] });
    return this;
  }

  // Structural: insert a child at an index (keyed reconciliation lives in the
  // guest; the host just mirrors the ordered child list).
  insert(child, index) {
    __rnRun({
      ref: this.id,
      method: "insert_child",
      args: [{ ref: child.id }, index],
    });
    return this;
  }

  removeChild(child) {
    __rnRun({ ref: this.id, method: "remove_child", args: [{ ref: child.id }] });
    return this;
  }

  // Remove every child (host clears the ordered list).
  clear() {
    __rnRun({ ref: this.id, method: "clear_children", args: [] });
    return this;
  }

  // Bind an event to a guest closure. Returns the callback id (for off()).
  on(event, cb) {
    var id = __gdRegisterCb(cb);
    __rnRun({ ref: this.id, connect: event, cb: id });
    return id;
  }

  off(event, cbId) {
    __rnRun({ ref: this.id, disconnect: event, cb: cbId });
    return this;
  }

  free() {
    __rnRun({ ref: this.id, free: this.id });
  }
}

// Create a widget of the given host class, apply an initial prop map, return the
// handle. Every widget factory below funnels through here.
function __rnCreate(cls, props) {
  var id = __rnAllocId();
  __rnRun({ new: cls, def: id });
  var obj = new RNObj(id);
  if (props != null) {
    // Split event handlers (onPress, onChangeText, …) from plain props: events
    // bind through `connect` ops so the manager namespaces the callback id and
    // routes the event back to this VM; everything else is a prop.
    var plain = {};
    var ks = keys(props);
    var i = 0;
    while (i < ks.length) {
      var k = ks[i];
      var v = props[k];
      if (k.length > 2 && k.charAt(0) == "o" && k.charAt(1) == "n" && __isType(v, "function")) {
        obj.on(__rnEventName(k), v);
      } else {
        plain[k] = v;
      }
      i = i + 1;
    }
    obj.props(plain);
  }
  return obj;
}

// ---------------------------------------------------------------------------
// RN — the widget facade
// ---------------------------------------------------------------------------

class RN {
  // Raw escape hatch: any registered host widget class + prop map.
  static create(cls, props) {
    return __rnCreate(cls, props);
  }

  // Layout containers ------------------------------------------------------
  static view(props) {
    return __rnCreate("RNView", props);
  } // flex View
  static column(props) {
    var p = props == null ? {} : props;
    p.direction = "column";
    return __rnCreate("RNView", p);
  }
  static row(props) {
    var p = props == null ? {} : props;
    p.direction = "row";
    return __rnCreate("RNView", p);
  }
  static scroll(props) {
    return __rnCreate("RNScroll", props);
  } // ScrollView
  static safe(props) {
    return __rnCreate("RNSafeArea", props);
  } // SafeAreaView
  static keyboardAvoiding(props) {
    return __rnCreate("KeyboardAvoidingView", props);
  }
  static modal(props) {
    return __rnCreate("Modal", props);
  } // Modal
  static pressable(props) {
    return __rnCreate("Pressable", props);
  }
  static touchable(props) {
    return __rnCreate("TouchableOpacity", props);
  }
  static touchableHighlight(props) {
    return __rnCreate("TouchableHighlight", props);
  }
  static touchableWithoutFeedback(props) {
    return __rnCreate("TouchableWithoutFeedback", props);
  }
  static touchableNativeFeedback(props) {
    return __rnCreate("TouchableNativeFeedback", props);
  }
  static inputAccessory(props) {
    return __rnCreate("InputAccessoryView", props);
  }
  static drawer(props) {
    return __rnCreate("DrawerLayoutAndroid", props);
  }

  // Lists (virtualized) — build them by add()ing children; the host maps the
  // child list onto the list's data set.
  static flatList(props) {
    return __rnCreate("FlatList", props);
  }
  static sectionList(props) {
    return __rnCreate("SectionList", props);
  }
  static virtualizedList(props) {
    return __rnCreate("VirtualizedList", props);
  }

  // Leaves -----------------------------------------------------------------
  static text(value, props) {
    var p = props == null ? {} : props;
    p.text = "" + value;
    return __rnCreate("RNText", p);
  }
  // text tag whose value comes from props.text (used by h("text", {...})).
  static textNode(props) {
    return __rnCreate("RNText", props == null ? {} : props);
  }
  static button(props) {
    return __rnCreate("RNButton", props);
  } // ergonomic Pressable + label
  static rawButton(props) {
    return __rnCreate("Button", props);
  } // the bare RN <Button/>
  static input(props) {
    return __rnCreate("RNInput", props);
  } // TextInput
  static image(props) {
    return __rnCreate("RNImage", props);
  } // Image
  static imageBackground(props) {
    return __rnCreate("ImageBackground", props);
  }
  static _switch(props) {
    return __rnCreate("RNSwitch", props);
  } // Switch
  static slider(props) {
    return __rnCreate("RNSlider", props);
  } // community slider (graceful fallback if not installed)
  static spinner(props) {
    return __rnCreate("RNActivityIndicator", props);
  } // ActivityIndicator
  static statusBar(props) {
    return __rnCreate("StatusBar", props);
  }
  static refreshControl(props) {
    return __rnCreate("RefreshControl", props);
  }

  // Animated host views (props still marshal as plain values).
  static animatedView(props) {
    return __rnCreate("Animated.View", props);
  }
  static animatedText(props) {
    return __rnCreate("Animated.Text", props);
  }
  static animatedImage(props) {
    return __rnCreate("Animated.Image", props);
  }
  static animatedScroll(props) {
    return __rnCreate("Animated.ScrollView", props);
  }

  // 3D — a Godot Scene3D embedded as a widget. Everything inside is built with
  // the ordinary GD / G3 surface from godot.js (normal godot.op seam). The
  // returned handle carries `.scene3d` = the Godot mount node the guest adds
  // 3D content under (camera, lights, meshes, physics — all of Godot).
  static scene3d(props) {
    var w = __rnCreate("RNScene3D", props);
    // Allocate the Godot mount node's handle guest-side (so the manager
    // namespaces it into this VM's id space, exactly like every other handle)
    // and bind the Scene3D surface to it. Subsequent GD/G3 calls on the same
    // handle then address the same node consistently.
    var nodeId = __gdAllocId();
    // Create the mount node EAGERLY on the immediate godot stream, before any
    // 3D content the guest builds under it. `scene3d_mount` is an rn.op and rn.op
    // is batched (flushed at RN.commit(), i.e. after the guest's build), while
    // godot.op is immediate — so if the host created the mount node from the
    // (late) mount message, every add_child in between would hit an unknown
    // handle and the whole 3D subtree would fail to attach. Creating it here
    // keeps it ahead of the content; the mount message then only re-parents it
    // into the Scene3D viewport.
    __gdRun({ new: "Node3D", def: nodeId });
    __rnRun({ ref: w.id, method: "scene3d_mount", args: [{ ref: nodeId }] });
    w.scene3d = new GObj(nodeId);
    return w;
  }

  // Batch a burst of widget mutations into a single seam crossing.
  static begin() {
    __rnBeginBatch();
  }
  static commit() {
    return __rnEndBatch();
  }

  // Mark a widget as the application root (mounted into <VictorHost/>). The
  // handle travels under `ref` so the manager namespaces it into this VM's id
  // space (the bare `root` key is not a handle key and would not be rewritten).
  static mount(widget) {
    __rnRun({ root: true, ref: widget.id });
    return widget;
  }

  // Toast / status line convenience (host renders a transient overlay).
  static toast(message) {
    askHost("rn.op", [{ toast: "" + message }]);
  }
}

// ---------------------------------------------------------------------------
// A tiny retained declarative layer: h() builds a plain description, mount()
// diffs successive trees and applies the minimum widget mutations. Apps that
// want React proper use VReact (react.js) with the RN driver; this is the
// lightweight, dependency-free path that ships in the front-end subset.
// ---------------------------------------------------------------------------

function h(type, props, children) {
  return {
    __vnode: true,
    type: type,
    props: props == null ? {} : props,
    children: children == null ? [] : children,
  };
}

// Instantiate a vnode into a live RNObj (+ its subtree). Event props whose name
// starts with "on" bind through .on(); everything else is a prop.
function __rnBuild(vnode) {
  if (__isType(vnode, "string") || __isType(vnode, "number")) {
    return RN.text("" + vnode, {});
  }
  var props = {};
  var events = [];
  var ks = keys(vnode.props);
  var i = 0;
  while (i < ks.length) {
    var k = ks[i];
    if (k.length > 2 && k.charAt(0) == "o" && k.charAt(1) == "n") {
      events.push(k);
    } else {
      props[k] = vnode.props[k];
    }
    i = i + 1;
  }
  var obj = __rnCreateByTag(vnode.type, props);
  var e = 0;
  while (e < events.length) {
    var name = events[e];
    obj.on(__rnEventName(name), vnode.props[name]);
    e = e + 1;
  }
  var c = 0;
  while (c < vnode.children.length) {
    var childObj = __rnBuild(vnode.children[c]);
    obj.add(childObj);
    c = c + 1;
  }
  return obj;
}

function __rnEventName(onName) {
  // "onPress" -> "press", "onChangeText" -> "changeText"
  var rest = onName.substring(2, onName.length);
  return rest.substring(0, 1).toLowerCase() + rest.substring(1, rest.length);
}

// Build a widget for a declarative tag by dispatching to the matching RN
// factory (kept as a switch rather than first-class method refs to stay well
// inside the front-end subset).
function __rnCreateByTag(type, props) {
  if (type == "view") return RN.view(props);
  if (type == "column") return RN.column(props);
  if (type == "row") return RN.row(props);
  if (type == "scroll") return RN.scroll(props);
  if (type == "safe") return RN.safe(props);
  if (type == "keyboardAvoiding") return RN.keyboardAvoiding(props);
  if (type == "modal") return RN.modal(props);
  if (type == "pressable") return RN.pressable(props);
  if (type == "touchable") return RN.touchable(props);
  if (type == "touchableHighlight") return RN.touchableHighlight(props);
  if (type == "touchableWithoutFeedback") return RN.touchableWithoutFeedback(props);
  if (type == "flatList") return RN.flatList(props);
  if (type == "sectionList") return RN.sectionList(props);
  if (type == "virtualizedList") return RN.virtualizedList(props);
  if (type == "text") return RN.textNode(props);
  if (type == "button") return RN.button(props);
  if (type == "input") return RN.input(props);
  if (type == "image") return RN.image(props);
  if (type == "imageBackground") return RN.imageBackground(props);
  if (type == "switch") return RN._switch(props);
  if (type == "slider") return RN.slider(props);
  if (type == "spinner") return RN.spinner(props);
  if (type == "statusBar") return RN.statusBar(props);
  if (type == "scene3d") return RN.scene3d(props);
  // Unknown tag -> raw host class of the same name (any registered component).
  return RN.create(type, props);
}

// mount a declarative tree as the app root and return its root RNObj.
function render(vnode) {
  RN.begin();
  var root = __rnBuild(vnode);
  RN.commit();
  RN.mount(root);
  return root;
}
