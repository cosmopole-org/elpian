// =============================================================================
// react.js — VReact: a React-compatible runtime for the Victor engine.
// =============================================================================
//
// The third guest library in the stack. Composed AFTER `godot.js` (the engine
// bridge) and `ui.js` (the VUI widget kit), it turns the Elpian VM into a
// React renderer whose "DOM" is the retained Godot scene graph:
//
//     import 'godot.js';
//     import 'ui.js';
//     import 'react.js';
//
//     function Counter(props) {
//       let s = useState(0);
//       let n = s[0]; let set = s[1];
//       return _jsxs("column", { gap: 16, children: [
//         _jsx("heading", { children: "Count: " + n }),
//         _jsx("button", { onPress: () => { set(n + 1); }, children: "Increment" }),
//       ]});
//     }
//     VictorClient.mountApp(_jsx(Counter, {}), { portrait: true });
//
// A developer never writes those `_jsx(...)` calls by hand: they author an
// ordinary Next.js + React project (JSX, hooks, components) and the Victor
// toolchain (`templates/victor-nextjs/tools/build.mjs`) transpiles the JSX with
// Babel's automatic runtime and flattens the modules into the single-file guest
// program the composer expects. This file is the runtime those programs call
// into. It is authored entirely in the `js2elpian` subset — so, like `ui.js`,
// it is user-space code with no privileged access.
//
// ## What it is (and is not)
//
// VReact is a faithful, from-scratch reimplementation of React's *programming
// model* — element factory, function components, the full hook surface, and a
// keyed reconciler that mutates retained host nodes — NOT a port of Facebook's
// `react` + `react-reconciler` packages. Those packages cannot run here: they
// rely on `Object.assign`, spread, generators, `Map`/`Set`, prototypes and a
// dozen other constructs the no-JIT Elpian bytecode subset does not model (see
// the subset chapter in `js2elpian/src/lib.rs`). VReact stands to React exactly
// as Preact does: same public API and semantics, an independent, tiny core.
// A component written against VReact IS ordinary React — the hook rules, the
// deps arrays, the reconciliation guarantees all hold.
//
// ## The rendering model
//
// React's host config here targets Godot `Control` nodes instead of the DOM.
// Every intrinsic element (`"column"`, `"text"`, `"button"`, `"input"`, …, plus
// the web aliases `"div"`, `"span"`, `"img"`, …) is a *host driver* that
// creates a real retained Godot node, patches its properties on update, and
// routes its signals back into event props. The reconciler diffs the element
// tree on each render and applies the minimal set of node mutations — Godot
// paints the retained scene; the VM only reacts. Event handlers are bound once
// through a stable indirection (the baked signal closure reads the *current*
// prop off the persistent instance), so re-renders never re-wire signals.
//
// ## The honest constraints of the subset (documented, not hidden)
//
//   * There is no first-class null: an absent value reads as 0 and `x == null`
//     is also true for a numeric 0. A literal numeric `0` therefore cannot be
//     rendered as a text child (React would render "0") — use `"" + n` or a
//     string. Every other value renders normally.
//   * Deps arrays are compared with `==` (the VM lowers `===` to it), i.e.
//     value identity for scalars and reference identity for objects — the same
//     contract as `Object.is` for the cases apps rely on.
//   * A single `<Context.Provider>` per context is supported app-wide; nesting
//     two providers of the *same* context with different values is not (the
//     value lives on the context object). Distinct contexts nest freely.
//
// Everything else — the hooks, keys, fragments, refs, effects and their
// cleanup ordering — behaves as you expect from React.

// ---------------------------------------------------------------------------
// element model
// ---------------------------------------------------------------------------

// A VReact element. Tagged so the reconciler can tell an element apart from an
// arbitrary props map or a plain value child.
var __VR_ELEMENT = "__vreact_element__";
var __VR_FRAGMENT = "__vreact_fragment__";
var __VR_PORTAL = "__vreact_portal__";

function __vrIsElement(x) {
  if (__isType(x, "map")) {
    return x[__VR_ELEMENT] == true;
  }
  return false;
}

// The JSX automatic-runtime entry points. Babel lowers `<tag .../>` to
// `_jsx(type, props, key)` and `<tag>{a}{b}</tag>` to `_jsxs(...)`; both land
// here. `children` already lives inside `props`, so there are no variadic
// arguments (which the subset could not express).
function jsx(type, props, key) {
  let p = props;
  if (p == null) {
    p = {};
  }
  return {
    __vreact_element__: true,
    type: type,
    props: p,
    key: key == null ? null : key,
    ref: p.ref == null ? null : p.ref,
  };
}

// `_jsxs` is `_jsx` with an array `children`; the reconciler flattens both, so
// they share one implementation.
function jsxs(type, props, key) {
  return jsx(type, props, key);
}

// Classic `React.createElement(type, props, childrenArray)` — provided for
// programmatic construction. The JSX transform uses the automatic runtime
// above; this variant takes children as a single array (no rest params).
function createElement(type, props, children) {
  let p = props;
  if (p == null) {
    p = {};
  }
  if (children != null) {
    p.children = children;
  }
  return jsx(type, p, p.key);
}

// Aliases Babel's automatic runtime references verbatim (it emits `_jsx`,
// `_jsxs`, `_jsxDEV`, `_Fragment`). Defining them as globals here means the
// stripped `import … from "react/jsx-runtime"` lines resolve to the runtime.
var _jsx = jsx;
var _jsxs = jsxs;
var _jsxDEV = jsx;
var Fragment = __VR_FRAGMENT;
var _Fragment = __VR_FRAGMENT;

// ---------------------------------------------------------------------------
// runtime state: current fiber, scheduler queues, effect queues
// ---------------------------------------------------------------------------

// The instance currently rendering (the hook dispatch target) and its hook
// cursor. React's "rules of hooks" hold because dispatch is index-based.
var __vrCur = null;
var __vrHookIndex = 0;

// Instances marked dirty by a setState/dispatch, drained on the next microtask.
var __vrDirty = [];
var __vrFlushScheduled = false;

// Effects whose deps changed this commit, run after the tree is mutated.
var __vrPendingEffects = [];
var __vrEffectsScheduled = false;

// Monotonic id source for useId().
var __vrIdSeq = 0;

// True while a commit is mutating the tree — setState during this phase is
// coalesced into the same flush rather than starting a nested one.
var __vrRendering = false;

// ---------------------------------------------------------------------------
// scheduling
// ---------------------------------------------------------------------------

function __vrScheduleUpdate(inst) {
  // Mark and enqueue once; the flush dedupes and skips instances whose
  // ancestor is already scheduled.
  if (inst.dirty == true) {
    return;
  }
  inst.dirty = true;
  __vrDirty.push(inst);
  if (!__vrFlushScheduled) {
    __vrFlushScheduled = true;
    __later(__vrFlush);
  }
}

function __vrFlush() {
  __vrFlushScheduled = false;
  // Drain the dirty set. setState inside a render re-enqueues, so loop until
  // the queue is empty (bounded in practice by the app's convergence).
  let guard = 0;
  while (__vrDirty.length > 0 && guard < 10000) {
    guard = guard + 1;
    let work = __vrDirty;
    __vrDirty = [];
    for (let i = 0; i < work.length; i++) {
      let inst = work[i];
      if (inst.dirty == true && inst.alive == true) {
        inst.dirty = false;
        __vrRerender(inst);
      } else {
        inst.dirty = false;
      }
    }
  }
  __vrScheduleEffects();
}

function __vrRerender(inst) {
  __vrRendering = true;
  __vrRenderComponent(inst);
  // A re-rendered component may have changed how many host nodes it produces;
  // re-sync the nearest host container so ordering/insertion stays correct.
  __vrSyncFrom(inst.hostContainer);
  __vrRendering = false;
}

// ---------------------------------------------------------------------------
// deps comparison (shared by useEffect / useMemo / useCallback / …)
// ---------------------------------------------------------------------------

function __vrDepsEqual(a, b) {
  // A null deps array means "no deps given" → always stale (re-run).
  if (a == null) {
    return false;
  }
  if (b == null) {
    return false;
  }
  if (a.length != b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// hooks
// ---------------------------------------------------------------------------

function __vrHook(initialiser) {
  let inst = __vrCur;
  let idx = __vrHookIndex;
  __vrHookIndex = idx + 1;
  // Hooks are visited in a stable order, so a slot is new exactly when the
  // cursor reaches the end of the list. (An out-of-bounds array read does not
  // return null in the VM, so length — not a null check — is the reliable
  // "not yet created" test.)
  if (idx < inst.hooks.length) {
    return inst.hooks[idx];
  }
  let h = initialiser();
  inst.hooks.push(h);
  return h;
}

function useState(initial) {
  let inst = __vrCur;
  let make = () => {
    let v = initial;
    if (__isType(initial, "function")) {
      v = initial();
    }
    let hook = { state: v, setState: null };
    hook.setState = (next) => {
      let value = next;
      if (__isType(next, "function")) {
        value = next(hook.state);
      }
      if (hook.state != value) {
        hook.state = value;
        __vrScheduleUpdate(inst);
      }
    };
    return hook;
  };
  let h = __vrHook(make);
  let out = [];
  out.push(h.state);
  out.push(h.setState);
  return out;
}

function useReducer(reducer, initialArg, init) {
  let inst = __vrCur;
  let make = () => {
    let s = initialArg;
    if (init != null && __isType(init, "function")) {
      s = init(initialArg);
    }
    let hook = { state: s, dispatch: null };
    hook.dispatch = (action) => {
      let value = reducer(hook.state, action);
      if (hook.state != value) {
        hook.state = value;
        __vrScheduleUpdate(inst);
      }
    };
    return hook;
  };
  let h = __vrHook(make);
  let out = [];
  out.push(h.state);
  out.push(h.dispatch);
  return out;
}

function useRef(initial) {
  let h = __vrHook(() => {
    return { current: initial };
  });
  return h;
}

function useMemo(factory, deps) {
  let h = __vrHook(() => {
    return { value: null, deps: null, primed: false };
  });
  if (!h.primed || !__vrDepsEqual(h.deps, deps)) {
    h.value = factory();
    h.deps = deps;
    h.primed = true;
  }
  return h.value;
}

function useCallback(fn, deps) {
  let h = __vrHook(() => {
    return { value: null, deps: null, primed: false };
  });
  if (!h.primed || !__vrDepsEqual(h.deps, deps)) {
    h.value = fn;
    h.deps = deps;
    h.primed = true;
  }
  return h.value;
}

// Effects (passive) and layout effects. Both register a job that the commit
// phase runs after the tree is mutated; layout effects run synchronously at the
// end of the commit, passive effects on the following microtask. Here they
// share the queue and the microtask drain (documented approximation — the
// cleanup/re-run ordering that apps depend on is preserved).
function __vrEffectImpl(create, deps, isLayout) {
  let h = __vrHook(() => {
    return { kind: "effect", create: null, cleanup: null, deps: null, pending: false, layout: isLayout };
  });
  h.create = create;
  if (!__vrDepsEqual(h.deps, deps)) {
    h.deps = deps;
    if (!h.pending) {
      h.pending = true;
      __vrPendingEffects.push(h);
    }
  }
}

function useEffect(create, deps) {
  __vrEffectImpl(create, deps, false);
}

function useLayoutEffect(create, deps) {
  __vrEffectImpl(create, deps, true);
}

function useInsertionEffect(create, deps) {
  __vrEffectImpl(create, deps, true);
}

function useImperativeHandle(ref, create, deps) {
  useEffect(() => {
    if (ref != null) {
      if (__isType(ref, "function")) {
        ref(create());
      } else {
        ref.current = create();
      }
    }
    return () => {
      if (ref != null && !__isType(ref, "function")) {
        ref.current = null;
      }
    };
  }, deps);
}

function useId() {
  let h = __vrHook(() => {
    __vrIdSeq = __vrIdSeq + 1;
    return { id: "vr-" + __vrIdSeq };
  });
  return h.id;
}

function useSyncExternalStore(subscribe, getSnapshot) {
  let s = useState(() => {
    return getSnapshot();
  });
  let value = s[0];
  let set = s[1];
  useEffect(() => {
    let check = () => {
      set(getSnapshot());
    };
    // Prime once in case the store changed between render and subscribe.
    check();
    let unsub = subscribe(check);
    return () => {
      if (unsub != null && __isType(unsub, "function")) {
        unsub();
      }
    };
  }, [subscribe]);
  return value;
}

// Concurrent hooks: the Elpian VM renders synchronously, so transitions and
// deferred values resolve immediately — API-compatible, no tearing.
function useTransition() {
  let out = [];
  out.push(false);
  out.push((cb) => {
    if (__isType(cb, "function")) {
      cb();
    }
  });
  return out;
}

function useDeferredValue(value) {
  return value;
}

function useDebugValue(v) {
  // no-op (devtools hook)
}

// useFrame(cb) — run cb(deltaSeconds) every rendered frame, the react-three-
// fiber idiom for imperative animation (rotate a mesh via its ref, step a
// simulation, …). A single GD.onProcess handler fans out to every registered
// callback; the callback always reads the latest closure through a ref, so it
// never goes stale across renders. Registration is cleaned up on unmount.
var __vrFrameCbs = [];
var __vrFrameInstalled = false;

function __vrInstallFrame() {
  if (__vrFrameInstalled) {
    return;
  }
  __vrFrameInstalled = true;
  GD.onProcess((d) => {
    let cbs = __vrFrameCbs;
    for (let i = 0; i < cbs.length; i++) {
      cbs[i](d);
    }
  });
}

function useFrame(cb) {
  let ref = useRef(cb);
  ref.current = cb;
  useEffect(() => {
    __vrInstallFrame();
    let wrapper = (d) => {
      ref.current(d);
    };
    __vrFrameCbs.push(wrapper);
    return () => {
      let out = [];
      for (let i = 0; i < __vrFrameCbs.length; i++) {
        if (__vrFrameCbs[i] != wrapper) {
          out.push(__vrFrameCbs[i]);
        }
      }
      __vrFrameCbs = out;
    };
  }, []);
}

// The live logical viewport (VUI.metrics()): { w, h, scale, compact, medium,
// expanded, portrait }. The component re-renders on every window resize, so
// responsive layouts just branch on the returned metrics.
function useViewport() {
  let s = useState(0);
  let setTick = s[1];
  useEffect(() => {
    let un = VUI.onResize((m) => {
      setTick((v) => v + 1);
    });
    return un;
  }, []);
  return VUI.metrics();
}

// ---------------------------------------------------------------------------
// context
// ---------------------------------------------------------------------------

function createContext(defaultValue) {
  let ctx = {
    __vrcontext: true,
    _value: defaultValue,
    _default: defaultValue,
    _subs: [],
    Provider: null,
    Consumer: null,
  };
  ctx.Provider = (props) => {
    let v = props.value;
    if (ctx._value != v) {
      ctx._value = v;
      __vrNotifyContext(ctx);
    }
    return props.children;
  };
  ctx.Consumer = (props) => {
    // <Context.Consumer>{value => ...}</Context.Consumer>
    let render = props.children;
    if (__isType(render, "function")) {
      return render(ctx._value);
    }
    return null;
  };
  return ctx;
}

function useContext(ctx) {
  let inst = __vrCur;
  // Subscribe this instance to future provider updates.
  let subs = ctx._subs;
  let found = false;
  for (let i = 0; i < subs.length; i++) {
    if (subs[i] == inst) {
      found = true;
    }
  }
  if (!found) {
    subs.push(inst);
  }
  return ctx._value;
}

function __vrNotifyContext(ctx) {
  let subs = ctx._subs;
  for (let i = 0; i < subs.length; i++) {
    let inst = subs[i];
    if (inst.alive == true) {
      __vrScheduleUpdate(inst);
    }
  }
}

// ---------------------------------------------------------------------------
// component helpers: memo / forwardRef / StrictMode
// ---------------------------------------------------------------------------

// forwardRef: the wrapped component receives (props, ref). React 19 keeps ref
// in props; we pass it explicitly for the classic two-arg signature.
function forwardRef(render) {
  let wrapper = (props) => {
    return render(props, props.ref);
  };
  return wrapper;
}

// memo: a shallow-props gate implemented purely with hooks (no reconciler
// special-case, no mutation of the function value). When the incoming props are
// shallow-equal to the previous render's, it returns the cached element so the
// subtree reconciles as a no-op.
function memo(component, areEqual) {
  let wrapped = (props) => {
    let last = useRef(null);
    let lastEl = useRef(null);
    if (last.current != null) {
      let same = false;
      if (areEqual != null && __isType(areEqual, "function")) {
        same = areEqual(last.current, props);
      } else {
        same = __vrShallowEqualProps(last.current, props);
      }
      if (same == true) {
        return lastEl.current;
      }
    }
    last.current = props;
    let el = component(props);
    lastEl.current = el;
    return el;
  };
  return wrapped;
}

var StrictMode = __VR_FRAGMENT;

function __vrShallowEqualProps(a, b) {
  if (a == b) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  let ka = a.keys;
  let kb = b.keys;
  if (ka.length != kb.length) {
    return false;
  }
  for (let i = 0; i < ka.length; i++) {
    let k = ka[i];
    if (a[k] != b[k]) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// children normalisation
// ---------------------------------------------------------------------------

// Flatten a children value into a linear array of renderables (elements and
// string text nodes), dropping null / boolean (and, per the subset caveat,
// numeric 0). Numbers become text; arrays flatten recursively.
function __vrNormalize(children) {
  let out = [];
  __vrNormalizeInto(out, children);
  return out;
}

function __vrNormalizeInto(out, ch) {
  if (ch == null) {
    return;
  }
  if (__isType(ch, "bool")) {
    return;
  }
  if (__isType(ch, "list")) {
    for (let i = 0; i < ch.length; i++) {
      __vrNormalizeInto(out, ch[i]);
    }
    return;
  }
  if (__isType(ch, "number")) {
    out.push("" + ch);
    return;
  }
  if (__isType(ch, "string")) {
    out.push(ch);
    return;
  }
  // an element (or any other map-shaped value we treat as one)
  out.push(ch);
}

// ---------------------------------------------------------------------------
// instances (the committed tree)
// ---------------------------------------------------------------------------
//
// kind:
//   "roothost" — the synthetic root wrapping the mount container
//   "host"     — an intrinsic element backed by a Godot node
//   "comp"     — a function component (owns hooks)
//   "frag"     — a fragment / provider / array of children
//   "text"     — a raw string, backed by a Label
//
// Shared fields: element, key, kind, childInstances, hostContainer, alive.
// A "host"/"roothost" also has: tag, driver, node, container, attached, props.
// A "comp" also has: fn, hooks, props.
// A "text" also has: node, value.

function __vrElementKey(child) {
  if (__vrIsElement(child)) {
    return child.key;
  }
  return null;
}

function __vrElementType(child) {
  if (__vrIsElement(child)) {
    return child.type;
  }
  return "__text__";
}

// Two children are "the same" (updatable in place) when their type and key
// match. Differing type or key means unmount-and-remount.
function __vrSameType(inst, child) {
  if (inst.kind == "text") {
    return !__vrIsElement(child);
  }
  if (!__vrIsElement(child)) {
    return false;
  }
  return inst.element != null && inst.element.type == child.type;
}

// ---------------------------------------------------------------------------
// mounting
// ---------------------------------------------------------------------------

function __vrMount(child, hostContainer) {
  if (!__vrIsElement(child)) {
    // a text node
    let node = __vrDriverText("" + child);
    return {
      kind: "text",
      value: "" + child,
      node: node,
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
      element: null,
      key: null,
    };
  }

  let type = child.type;

  if (__isType(type, "function")) {
    let inst = {
      kind: "comp",
      fn: type,
      element: child,
      props: child.props,
      key: child.key,
      hooks: [],
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
      dirty: false,
    };
    __vrRenderComponent(inst);
    return inst;
  }

  if (type == __VR_FRAGMENT) {
    let inst = {
      kind: "frag",
      element: child,
      key: child.key,
      childInstances: [],
      hostContainer: hostContainer,
      alive: true,
    };
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), hostContainer);
    return inst;
  }

  // an intrinsic host element
  let inst = {
    kind: "host",
    tag: type,
    element: child,
    props: child.props,
    key: child.key,
    node: null,
    container: null,
    attached: [],
    childInstances: [],
    hostContainer: hostContainer,
    alive: true,
  };
  __vrDriverCreate(inst);
  if (inst.ref == null) {
    inst.ref = child.ref;
  }
  // Only container hosts adopt element children; leaf hosts (text, button,
  // camera, …) fold their children into a prop (label text) inside the driver,
  // so reconciling them would build orphan nodes.
  if (inst.container != null) {
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), inst);
    __vrSyncFrom(inst);
  }
  __vrApplyHostRef(inst);
  return inst;
}

function __vrRenderComponent(inst) {
  let fn = inst.fn;
  __vrCur = inst;
  __vrHookIndex = 0;
  let out = fn(inst.props);
  __vrCur = null;
  __vrReconcileChildren(inst, __vrNormalize(out), inst.hostContainer);
}

// ---------------------------------------------------------------------------
// updating
// ---------------------------------------------------------------------------

function __vrUpdate(inst, child, hostContainer) {
  if (!__vrSameType(inst, child)) {
    // replace: unmount the old subtree, mount a fresh one
    __vrUnmount(inst);
    return __vrMount(child, hostContainer);
  }

  if (inst.kind == "text") {
    let v = "" + child;
    if (inst.value != v) {
      inst.value = v;
      inst.node.set("text", v);
    }
    return inst;
  }

  if (inst.kind == "comp") {
    inst.element = child;
    inst.props = child.props;
    __vrRenderComponent(inst);
    return inst;
  }

  if (inst.kind == "frag") {
    inst.element = child;
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), hostContainer);
    return inst;
  }

  // host
  let oldProps = inst.props;
  inst.element = child;
  inst.props = child.props;
  __vrDriverUpdate(inst, oldProps, child.props);
  if (inst.container != null) {
    __vrReconcileChildren(inst, __vrNormalize(child.props.children), inst);
    __vrSyncFrom(inst);
  }
  if (inst.ref != child.ref) {
    inst.ref = child.ref;
    __vrApplyHostRef(inst);
  }
  return inst;
}

// ---------------------------------------------------------------------------
// child reconciliation (keyed, with positional fallback)
// ---------------------------------------------------------------------------

function __vrReconcileChildren(parent, newChildren, hostContainer) {
  let old = parent.childInstances;
  let used = [];
  for (let i = 0; i < old.length; i++) {
    used.push(false);
  }
  let matched = [];
  for (let i = 0; i < newChildren.length; i++) {
    matched.push(-1);
  }

  // Pass 1 — keyed matches.
  for (let i = 0; i < newChildren.length; i++) {
    let key = __vrElementKey(newChildren[i]);
    if (key != null) {
      for (let j = 0; j < old.length; j++) {
        if (!used[j] && old[j].key == key && __vrSameType(old[j], newChildren[i])) {
          matched[i] = j;
          used[j] = true;
          j = old.length;
        }
      }
    }
  }

  // Pass 2 — positional matches for the still-unmatched, keyless children.
  let cursor = 0;
  for (let i = 0; i < newChildren.length; i++) {
    if (matched[i] < 0 && __vrElementKey(newChildren[i]) == null) {
      while (cursor < old.length && (used[cursor] || old[cursor].key != null)) {
        cursor = cursor + 1;
      }
      if (cursor < old.length && __vrSameType(old[cursor], newChildren[i])) {
        matched[i] = cursor;
        used[cursor] = true;
        cursor = cursor + 1;
      }
    }
  }

  // Build the next child-instance list.
  let next = [];
  for (let i = 0; i < newChildren.length; i++) {
    if (matched[i] >= 0) {
      let inst = old[matched[i]];
      next.push(__vrUpdate(inst, newChildren[i], hostContainer));
    } else {
      next.push(__vrMount(newChildren[i], hostContainer));
    }
  }

  // Unmount everything left over.
  for (let j = 0; j < old.length; j++) {
    if (!used[j]) {
      __vrUnmount(old[j]);
    }
  }

  parent.childInstances = next;
}

// ---------------------------------------------------------------------------
// unmounting
// ---------------------------------------------------------------------------

function __vrUnmount(inst) {
  inst.alive = false;

  // Run effect cleanups for a component's own hooks (deepest first would be
  // ideal; this order is adequate for the cleanup contract apps rely on).
  if (inst.kind == "comp") {
    let hooks = inst.hooks;
    for (let i = 0; i < hooks.length; i++) {
      let h = hooks[i];
      if (h != null && h.kind == "effect") {
        if (h.cleanup != null && __isType(h.cleanup, "function")) {
          h.cleanup();
          h.cleanup = null;
        }
      }
    }
  }

  let cs = inst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrUnmount(cs[i]);
  }

  // Free the Godot node backing a host/text instance.
  if (inst.kind == "host" || inst.kind == "text") {
    if (inst.node != null) {
      inst.node.queueFree();
    }
  }
}

// ---------------------------------------------------------------------------
// host-node collection + container synchronisation
// ---------------------------------------------------------------------------

// Collect, in order, the top-level Godot nodes an instance contributes to its
// enclosing host container. Recursion stops at host/text nodes (a host manages
// its own children internally).
function __vrCollect(inst, out) {
  if (inst.kind == "host" || inst.kind == "text") {
    out.push(inst.node);
    return;
  }
  let cs = inst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrCollect(cs[i], out);
  }
}

function __vrSameNodes(a, b) {
  if (a.length != b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

// Handle-id equality. On the web bridge a handle re-marshaled from the engine
// (e.g. get_parent's return) can carry a generation bit at 2^32, so compare
// the low 32 bits only.
function __vrIdEq(a, b) {
  if (a == null || b == null) {
    return false;
  }
  return a % 4294967296 == b % 4294967296;
}

// The current parent of a node, or null when it has none / the handle is
// already freed (a freed handle's op errors — swallowed here on purpose).
function __vrParentOf(n) {
  let p = null;
  try {
    p = n.call("get_parent", []);
  } catch (e) {
    return null;
  }
  if (p == null) {
    return null;
  }
  if (GD.isError(p)) {
    return null;
  }
  if (p.id == null) {
    return null;
  }
  return p;
}

// Reconcile a host instance's container to hold exactly its flattened child
// nodes, in order. Kept nodes are detached and re-appended (Godot preserves
// their state); unmounted nodes were already queue-freed. Skips work entirely
// when the ordered node set is unchanged.
//
// Parent-aware on both sides: a node that moved to ANOTHER container this pass
// must not be ripped out of it (only detach nodes still under this container),
// and a wanted node still sitting under a previous parent must be detached
// there first — Godot refuses add_child on a parented node, which used to make
// whole subtrees silently disappear on screen transitions.
function __vrSyncFrom(hostInst) {
  if (hostInst == null) {
    return;
  }
  let container = hostInst.container;
  if (container == null) {
    return;
  }
  let want = [];
  let cs = hostInst.childInstances;
  for (let i = 0; i < cs.length; i++) {
    __vrCollect(cs[i], want);
  }
  let prev = hostInst.attached;
  if (prev == null) {
    prev = [];
  }
  if (__vrSameNodes(prev, want)) {
    return;
  }
  for (let i = 0; i < prev.length; i++) {
    let pp = __vrParentOf(prev[i]);
    if (pp != null && __vrIdEq(pp.id, container.id)) {
      container.call("remove_child", [prev[i]]);
    }
  }
  for (let i = 0; i < want.length; i++) {
    let wp = __vrParentOf(want[i]);
    if (wp != null) {
      wp.call("remove_child", [want[i]]);
    }
    container.call("add_child", [want[i]]);
  }
  hostInst.attached = want;
}

// ---------------------------------------------------------------------------
// refs on host elements
// ---------------------------------------------------------------------------

function __vrApplyHostRef(inst) {
  let ref = inst.ref;
  if (ref == null) {
    return;
  }
  if (__isType(ref, "function")) {
    ref(inst.node);
  } else {
    ref.current = inst.node;
  }
}

// ---------------------------------------------------------------------------
// effect commit
// ---------------------------------------------------------------------------

function __vrScheduleEffects() {
  if (__vrPendingEffects.length == 0) {
    return;
  }
  if (!__vrEffectsScheduled) {
    __vrEffectsScheduled = true;
    __later(__vrRunEffects);
  }
}

function __vrRunEffects() {
  __vrEffectsScheduled = false;
  let q = __vrPendingEffects;
  __vrPendingEffects = [];
  for (let i = 0; i < q.length; i++) {
    let h = q[i];
    if (h.pending == true) {
      h.pending = false;
      if (h.cleanup != null && __isType(h.cleanup, "function")) {
        h.cleanup();
        h.cleanup = null;
      }
      let c = h.create();
      if (c != null && __isType(c, "function")) {
        h.cleanup = c;
      } else {
        h.cleanup = null;
      }
    }
  }
}

// ===========================================================================
// HOST DRIVERS — the React "host config": intrinsic tags → Godot Control nodes
// ===========================================================================
//
// Each host instance gets a `node` (the outer node attached to its parent) and
// a `container` (the node its children attach into — often the same node; for
// padded/scroll wrappers it is an inner box). Leaves have `container == null`.
// Drivers reuse VUI's theme + style helpers so React output matches the kit.

// Resolve a colour: a Color passes through, a theme token name maps to the
// active theme, an "#rrggbb"/"#rrggbbaa" string parses via Godot's Color.html.
function __vrColor(v) {
  if (v == null) {
    return null;
  }
  if (__isType(v, "Color")) {
    return v;
  }
  let t = VUI.theme();
  if (__isType(v, "string")) {
    if (v == "primary") { return t.primary; }
    if (v == "accent") { return t.accent; }
    if (v == "danger") { return t.danger; }
    if (v == "success") { return t.success; }
    if (v == "warning") { return t.warning; }
    if (v == "info") { return t.info; }
    if (v == "text") { return t.text; }
    if (v == "textDim" || v == "muted") { return t.textDim; }
    if (v == "surface") { return t.surface; }
    if (v == "bg") { return t.bg; }
    return __vrColorHtml(v);
  }
  return null;
}

// One hex nibble → 0..15, or -1 (accepts both cases; no case builtin needed).
function __vrHexDigit(ch) {
  let lower = "0123456789abcdef";
  let upper = "0123456789ABCDEF";
  let i = lower.indexOf(ch);
  if (i >= 0) {
    return i;
  }
  return upper.indexOf(ch);
}

// Parse "#rgb", "#rrggbb" or "#rrggbbaa" in pure JS (the subset has no hex
// literals, and the engine's Expression cannot reach Color.html). Returns
// null on anything unparseable so callers fall back to their own default.
function __vrColorHtml(hex) {
  let s = "" + hex;
  if (s.startsWith("#")) {
    s = s.substring(1, s.length);
  }
  if (s.length == 3) {
    let r3 = __vrHexDigit(s.substring(0, 1));
    let g3 = __vrHexDigit(s.substring(1, 2));
    let b3 = __vrHexDigit(s.substring(2, 3));
    if (r3 < 0 || g3 < 0 || b3 < 0) {
      return null;
    }
    return new Color((r3 * 17) / 255.0, (g3 * 17) / 255.0, (b3 * 17) / 255.0, 1.0);
  }
  if (s.length != 6 && s.length != 8) {
    return null;
  }
  let vals = [];
  for (let i = 0; i < s.length; i = i + 2) {
    let hi = __vrHexDigit(s.substring(i, i + 1));
    let lo = __vrHexDigit(s.substring(i + 1, i + 2));
    if (hi < 0 || lo < 0) {
      return null;
    }
    vals.push((hi * 16 + lo) / 255.0);
  }
  let alpha = 1.0;
  if (vals.length == 4) {
    alpha = vals[3];
  }
  return new Color(vals[0], vals[1], vals[2], alpha);
}

// Call a possibly-absent event prop with an argument.
function __vrCall(fn, arg) {
  if (fn != null && __isType(fn, "function")) {
    fn(arg);
  }
}

function __vrCall0(fn) {
  if (fn != null && __isType(fn, "function")) {
    fn();
  }
}

// Read a numeric prop with a default. The VM's single 0/null/absent value
// means an absent prop and an explicit 0 both take the default; pass -1 for
// an explicit zero (spacing sinks clamp negatives to 0).
function __vrNum(v, d) {
  if (v == null) {
    return d;
  }
  if (__isType(v, "number")) {
    return v;
  }
  return d;
}

function __vrPx(v) {
  if (v < 0) {
    return 0;
  }
  return v;
}

// The subset of style-object keys we understand (so `style={{...}}` from an
// ordinary React component maps onto Godot properties).
function __vrApplyStyle(inst, style) {
  if (style == null) {
    return;
  }
  let node = inst.node;
  if (style.width != null) {
    __vrSetMinSize(node, __vrNum(style.width, 0.0), -1.0);
  }
  if (style.height != null) {
    __vrSetMinSize(node, -1.0, __vrNum(style.height, 0.0));
  }
  if (style.flexGrow != null && style.flexGrow != 0) {
    node.set("size_flags_horizontal", GInt(3));
    node.set("size_flags_vertical", GInt(3));
  }
  if (style.opacity != null) {
    node.set("modulate", new Color(1.0, 1.0, 1.0, __vrNum(style.opacity, 1.0)));
  }
  if (style.backgroundColor != null && inst.container != null) {
    let c = __vrColor(style.backgroundColor);
    if (c != null) {
      __vrSetPanelBg(inst, c);
    }
  }
}

function __vrSetMinSize(node, w, h) {
  let cur = node.get("custom_minimum_size");
  let cw = 0.0;
  let chh = 0.0;
  if (__isType(cur, "Vector2")) {
    cw = cur.x;
    chh = cur.y;
  }
  if (w >= 0.0) {
    cw = w;
  }
  if (h >= 0.0) {
    chh = h;
  }
  node.set("custom_minimum_size", new Vector2(cw, chh));
}

function __vrSetPanelBg(inst, color) {
  // Only meaningful when the outer node is a Panel/PanelContainer.
  inst.node.set("theme_override_styles/panel", VUI.styleBox({ bg: color, radius: VUI.theme().radiusM }));
}

// ---- the text driver (raw string children + <text>/<span>/<p>) -------------

function __vrDriverText(str) {
  let t = VUI.theme();
  let l = GD.create("Label");
  l.set("text", "" + str);
  l.set("theme_override_font_sizes/font_size", GInt(t.fontM));
  l.set("theme_override_colors/font_color", t.text);
  return l;
}

// ---- collect a text value out of children (for <text>, <button>, …) --------

function __vrTextOf(props) {
  let kids = __vrNormalize(props.children);
  let s = "";
  for (let i = 0; i < kids.length; i++) {
    if (!__vrIsElement(kids[i])) {
      s = s + kids[i];
    }
  }
  return s;
}

// ---------------------------------------------------------------------------
// driver dispatch
// ---------------------------------------------------------------------------

// Container tags whose element children become real child instances. Everything
// else is a leaf whose text children collapse into a string.
function __vrIsContainerTag(tag) {
  if (tag == "view") { return true; }
  if (tag == "div") { return true; }
  if (tag == "column") { return true; }
  if (tag == "vstack") { return true; }
  if (tag == "row") { return true; }
  if (tag == "hstack") { return true; }
  if (tag == "stack") { return true; }
  if (tag == "scroll") { return true; }
  if (tag == "center") { return true; }
  if (tag == "panel") { return true; }
  if (tag == "card") { return true; }
  if (tag == "grid") { return true; }
  if (tag == "section") { return true; }
  if (tag == "main") { return true; }
  if (tag == "header") { return true; }
  if (tag == "footer") { return true; }
  if (tag == "nav") { return true; }
  if (tag == "ul") { return true; }
  if (tag == "ol") { return true; }
  if (tag == "li") { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// 3D host tags — Node3D-family elements + the <scene3d> viewport bridge, all
// built through G3 (godot.js). A <scene3d> is a Control that embeds a 3D world;
// every other 3D tag is a Node3D that lives inside one.
// ---------------------------------------------------------------------------

function __vrIs3DTag(tag) {
  if (tag == "scene3d") { return true; }
  if (tag == "viewport3d") { return true; }
  if (tag == "canvas3d") { return true; }
  if (tag == "node3d") { return true; }
  if (tag == "spatial") { return true; }
  if (tag == "group3d") { return true; }
  if (tag == "mesh") { return true; }
  if (tag == "box") { return true; }
  if (tag == "sphere") { return true; }
  if (tag == "cylinder") { return true; }
  if (tag == "capsule") { return true; }
  if (tag == "plane3d") { return true; }
  if (tag == "torus") { return true; }
  if (tag == "prism") { return true; }
  if (tag == "camera3d") { return true; }
  if (tag == "camera") { return true; }
  if (tag == "directionallight") { return true; }
  if (tag == "sun") { return true; }
  if (tag == "omnilight") { return true; }
  if (tag == "pointlight") { return true; }
  if (tag == "spotlight") { return true; }
  if (tag == "environment") { return true; }
  if (tag == "worldenvironment") { return true; }
  if (tag == "staticbody3d") { return true; }
  if (tag == "rigidbody3d") { return true; }
  if (tag == "characterbody3d") { return true; }
  if (tag == "area3d") { return true; }
  if (tag == "collisionshape3d") { return true; }
  if (tag == "gltf") { return true; }
  if (tag == "model") { return true; }
  if (tag == "node") { return true; }
  return false;
}

function __vr3dMeshOpts(props) {
  return {
    size: props.size,
    radius: props.radius,
    height: props.height,
    width: props.width,
    depth: props.depth,
    topRadius: props.topRadius,
    bottomRadius: props.bottomRadius,
    innerRadius: props.innerRadius,
    outerRadius: props.outerRadius,
    color: __vrColor(props.color),
    metallic: props.metallic,
    roughness: props.roughness,
    emission: __vrColor(props.emission),
    emissionEnergy: props.emissionEnergy,
    transparency: props.transparency,
    position: props.position,
    rotation: props.rotation,
    scale: props.scale,
    visible: props.visible,
  };
}

function __vr3dCollisionShape(props) {
  let shape = props.shape;
  if (shape == "sphere") {
    let s = GD.create("SphereShape3D");
    s.set("radius", GFloat(__vrNum(props.radius, 0.5)));
    return s;
  }
  if (shape == "capsule") {
    let s = GD.create("CapsuleShape3D");
    s.set("radius", GFloat(__vrNum(props.radius, 0.4)));
    s.set("height", GFloat(__vrNum(props.height, 1.4)));
    return s;
  }
  let s = GD.create("BoxShape3D");
  s.set("size", new Vector3(__vrNum(props.width, 1.0), __vrNum(props.height, 1.0), __vrNum(props.depth, 1.0)));
  return s;
}

// Wire 3D pick/input events onto a body/area host: `input_event` fires when
// the enclosing <scene3d picking> viewport picks the body. The handler reads
// the CURRENT props off the instance, so re-renders never re-wire the signal.
function __vrWire3DPick(inst) {
  let p = inst.props;
  if (p.onPick == null && p.onInputEvent == null && p.onPress == null) {
    return;
  }
  inst.node.set("input_ray_pickable", true);
  inst.node.connect("input_event", (a) => {
    // a = [camera, event, event_position, normal, shape_idx]
    let cur = inst.props;
    let ev = a[1];
    let evCls = "";
    if (__isType(ev, "GObj")) {
      evCls = ev.cls;
    }
    let info = {
      camera: a[0],
      event: ev,
      eventClass: evCls,
      position: a[2],
      normal: a[3],
      node: inst.node,
    };
    __vrCall(cur.onInputEvent, info);
    // onPick / onPress: only on press of a button/touch (not motion).
    if (cur.onPick != null || cur.onPress != null) {
      let pressed = GD.eval(
        "e.pressed if (e is InputEventMouseButton or e is InputEventScreenTouch) else false",
        ["e"],
        [ev]
      );
      if (pressed == true) {
        __vrCall(cur.onPick, info);
        __vrCall(cur.onPress, info);
      }
    }
  });
  if (p.onHover != null) {
    inst.node.connect("mouse_entered", (a) => {
      __vrCall(inst.props.onHover, true);
    });
    inst.node.connect("mouse_exited", (a) => {
      __vrCall(inst.props.onHover, false);
    });
  }
}

function __vrCreate3D(inst, tag, props) {
  if (tag == "scene3d" || tag == "viewport3d" || tag == "canvas3d") {
    let v = G3.viewport({ transparent: props.transparent, msaa: props.msaa, picking: props.picking });
    inst.node = v.container;
    inst.container = v.viewport;
    inst.viewport = v.viewport;
    v.container.set("size_flags_horizontal", GInt(3));
    v.container.set("size_flags_vertical", GInt(3));
    if (props.height != null) {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), __vrNum(props.height, 320.0));
    } else if (props.grow == true || props.expand == true) {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), 0.0);
    } else {
      __vrSetMinSize(v.container, __vrNum(props.width, 0.0), 320.0);
    }
    // Raw viewport input hook (camera drags, wheel zoom, hover): receives the
    // GObj InputEvent for every event the embedded world sees.
    if (props.onInput != null) {
      v.viewport.connect("gui_focus_changed", (a) => {});
      v.container.connect("gui_input", (a) => {
        __vrCall(inst.props.onInput, a[0]);
      });
    }
    return;
  }
  if (tag == "gltf" || tag == "model") {
    // A Node3D wrapper holding the loaded model, so src swaps and element
    // children (lights, extra meshes, bodies) reconcile against the wrapper.
    let wrap = G3.node({ position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = wrap;
    inst.container = wrap;
    inst.modelSrc = null;
    inst.modelNode = null;
    if (props.src != null) {
      let m = G3.gltf(props.src, { scale: props.modelScale, rotation: props.modelRotation });
      if (m != null) {
        wrap.call("add_child", [m]);
        inst.modelSrc = props.src;
        inst.modelNode = m;
        if (props.targetHeight != null) {
          G3.fitHeight(m, __vrNum(props.targetHeight, 1.0));
        }
      }
    }
    return;
  }
  if (tag == "node3d" || tag == "spatial" || tag == "group3d") {
    let n = G3.node({ position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = n;
    inst.container = n;
    return;
  }
  if (tag == "mesh" || tag == "box" || tag == "sphere" || tag == "cylinder" || tag == "capsule" || tag == "plane3d" || tag == "torus" || tag == "prism") {
    let shape = props.shape;
    if (shape == null) {
      shape = tag == "mesh" ? "box" : tag;
    }
    if (shape == "plane3d") {
      shape = "plane";
    }
    let mi = G3.mesh(shape, __vr3dMeshOpts(props));
    inst.node = mi;
    inst.container = mi;
    inst.meshShape = shape;
    return;
  }
  if (tag == "camera3d" || tag == "camera") {
    let c = G3.camera({ fov: props.fov, current: props.current, position: props.position, rotation: props.rotation, scale: props.scale });
    inst.node = c;
    inst.container = null;
    return;
  }
  if (tag == "directionallight" || tag == "sun") {
    let l = G3.dirLight({ color: __vrColor(props.color), energy: props.energy, shadow: props.shadow, position: props.position, rotation: props.rotation });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "omnilight" || tag == "pointlight") {
    let l = G3.omniLight({ color: __vrColor(props.color), energy: props.energy, range: props.range, position: props.position });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "spotlight") {
    let l = G3.spotLight({ color: __vrColor(props.color), energy: props.energy, range: props.range, angle: props.angle, position: props.position, rotation: props.rotation });
    inst.node = l;
    inst.container = null;
    return;
  }
  if (tag == "environment" || tag == "worldenvironment") {
    let e = G3.environment({ bg: __vrColor(props.bg), ambient: __vrColor(props.ambient), ambientEnergy: props.ambientEnergy });
    inst.node = e;
    inst.container = null;
    return;
  }
  if (tag == "staticbody3d" || tag == "rigidbody3d" || tag == "characterbody3d" || tag == "area3d") {
    let cls = "StaticBody3D";
    if (tag == "rigidbody3d") { cls = "RigidBody3D"; }
    else if (tag == "characterbody3d") { cls = "CharacterBody3D"; }
    else if (tag == "area3d") { cls = "Area3D"; }
    let b = GD.create(cls);
    G3.setTransform(b, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
    inst.node = b;
    inst.container = b;
    __vrWire3DPick(inst);
    return;
  }
  if (tag == "collisionshape3d") {
    let cs = GD.create("CollisionShape3D");
    let shape = __vr3dCollisionShape(props);
    if (shape != null) {
      cs.set("shape", shape);
    }
    G3.setTransform(cs, { position: props.position, rotation: props.rotation });
    inst.node = cs;
    inst.container = null;
    return;
  }
  // generic reflective escape hatch: <node type="AnyGodotClass" .../> — any
  // engine class becomes a host element, a container so it can hold children.
  let cls = props.type ?? "Node";
  let n = GD.create(cls);
  G3.setTransform(n, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });
  inst.node = n;
  inst.container = n;
}

function __vrUpdate3D(inst, oldProps, props) {
  let tag = inst.tag;
  // Declarative transform (only sets the props that are present).
  G3.setTransform(inst.node, { position: props.position, rotation: props.rotation, scale: props.scale, visible: props.visible });

  if (tag == "gltf" || tag == "model") {
    if (props.src != inst.modelSrc) {
      if (inst.modelNode != null) {
        inst.modelNode.queueFree();
        inst.modelNode = null;
      }
      inst.modelSrc = props.src;
      if (props.src != null) {
        let m = G3.gltf(props.src, { scale: props.modelScale, rotation: props.modelRotation });
        if (m != null) {
          inst.node.call("add_child", [m]);
          inst.modelNode = m;
          if (props.targetHeight != null) {
            G3.fitHeight(m, __vrNum(props.targetHeight, 1.0));
          }
        }
      }
    }
    return;
  }

  if (tag == "mesh" || tag == "box" || tag == "sphere" || tag == "cylinder" || tag == "capsule" || tag == "plane3d" || tag == "torus" || tag == "prism") {
    if (props.color != oldProps.color || props.emission != oldProps.emission || props.roughness != oldProps.roughness || props.metallic != oldProps.metallic) {
      let prim = inst.node.get("mesh");
      if (prim != null && !GD.isError(prim)) {
        prim.set("material", G3.material(__vr3dMeshOpts(props)));
      }
    }
    return;
  }
  if (tag == "camera3d" || tag == "camera") {
    if (props.fov != oldProps.fov && props.fov != null) {
      inst.node.set("fov", GFloat(props.fov));
    }
    if (props.current != oldProps.current) {
      inst.node.set("current", props.current == true);
    }
    return;
  }
  if (tag == "directionallight" || tag == "sun" || tag == "omnilight" || tag == "pointlight" || tag == "spotlight") {
    if (props.color != oldProps.color) {
      let c = __vrColor(props.color);
      if (c != null) {
        inst.node.set("light_color", c);
      }
    }
    if (props.energy != oldProps.energy && props.energy != null) {
      inst.node.set("light_energy", GFloat(props.energy));
    }
    return;
  }
}

function __vrDriverCreate(inst) {
  let tag = inst.tag;
  let props = inst.props;
  let t = VUI.theme();

  if (__vrIs3DTag(tag)) {
    __vrCreate3D(inst, tag, props);
    return;
  }

  if (__vrIsContainerTag(tag)) {
    __vrCreateContainer(inst, tag, props, t);
    return;
  }

  // ----- leaves -----
  if (tag == "text" || tag == "span" || tag == "p" || tag == "label" || tag == "paragraph") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, t.fontM, false);
    return;
  }
  if (tag == "heading" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "title") {
    let size = t.fontXL;
    if (tag == "h2" || tag == "title") { size = t.fontL; }
    if (tag == "h3") { size = t.fontM; }
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, size, false);
    if (props.weight == null) {
      // Headlines default to the medium weight, Material-style.
      let hf = VUI.fonts();
      if (hf.medium != null) {
        l.set("theme_override_fonts/font", hf.medium);
      }
    }
    return;
  }
  if (tag == "caption" || tag == "small" || tag == "muted") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    __vrApplyTextProps(inst, null, props, t.fontXS, true);
    return;
  }
  if (tag == "icon") {
    let l = GD.create("Label");
    inst.node = l;
    inst.container = null;
    l.set("horizontal_alignment", GInt(1));
    __vrApplyTextProps(inst, null, props, __vrNum(props.size, t.fontL), false);
    return;
  }
  if (tag == "button") {
    __vrCreateButton(inst, props, t);
    return;
  }
  if (tag == "input" || tag == "field" || tag == "textinput") {
    __vrCreateField(inst, props, t);
    return;
  }
  if (tag == "textarea") {
    __vrCreateTextArea(inst, props, t);
    return;
  }
  if (tag == "select" || tag == "dropdown" || tag == "option") {
    __vrCreateSelect(inst, props, t);
    return;
  }
  if (tag == "richtext") {
    __vrCreateRichText(inst, props, t);
    return;
  }
  if (tag == "image" || tag == "img") {
    __vrCreateImage(inst, props, t);
    return;
  }
  if (tag == "progress") {
    __vrCreateProgress(inst, props, t);
    return;
  }
  if (tag == "slider") {
    __vrCreateSlider(inst, props, t);
    return;
  }
  if (tag == "switch" || tag == "toggle") {
    __vrCreateSwitch(inst, props, t);
    return;
  }
  if (tag == "checkbox") {
    __vrCreateCheckbox(inst, props, t);
    return;
  }
  if (tag == "divider" || tag == "hr") {
    __vrCreateDivider(inst, props, t);
    return;
  }
  if (tag == "spacer") {
    let c = GD.create("Control");
    c.set("size_flags_horizontal", GInt(3));
    c.set("size_flags_vertical", GInt(3));
    inst.node = c;
    inst.container = null;
    return;
  }
  if (tag == "chip") {
    let handle = VUI.chip(__vrTextOf(props), {
      selected: props.selected == true,
      glyph: props.glyph,
      onTap: (on) => {
        __vrCall(inst.props.onChange, on);
        __vrCall0(inst.props.onPress);
      },
    });
    inst.node = handle.node;
    inst.container = null;
    inst.chipHandle = handle;
    return;
  }
  if (tag == "badge") {
    inst.node = VUI.badge(__vrTextOf(props), {
      color: __vrColor(props.color),
      textColor: __vrColor(props.textColor),
    });
    inst.container = null;
    return;
  }
  if (tag == "avatar") {
    inst.node = VUI.avatar(__vrTextOf(props), {
      color: __vrColor(props.color),
      textColor: __vrColor(props.textColor),
      size: props.size,
    });
    inst.container = null;
    return;
  }
  if (tag == "fab") {
    inst.node = VUI.fab(props.glyph ?? __vrTextOf(props), {
      size: props.size,
      bg: __vrColor(props.bg),
      color: __vrColor(props.color),
      onTap: () => {
        __vrCall0(inst.props.onPress);
        __vrCall0(inst.props.onClick);
        __vrCall0(inst.props.onTap);
      },
    });
    inst.container = null;
    return;
  }
  if (tag == "tile" || tag == "listtile") {
    inst.node = VUI.listTile({
      leading: props.leading,
      leadingColor: __vrColor(props.leadingColor),
      title: props.title ?? __vrTextOf(props),
      subtitle: props.subtitle,
      trailing: props.trailing,
      onTap: () => {
        __vrCall0(inst.props.onPress);
        __vrCall0(inst.props.onClick);
        __vrCall0(inst.props.onTap);
      },
    });
    inst.container = null;
    return;
  }

  // Unknown tag → a plain transparent container so the tree still renders.
  __vrCreateContainer(inst, "view", props, t);
}

function __vrCreateContainer(inst, tag, props, t) {
  let box = null;
  let container = null;
  let outer = null;

  if (tag == "row" || tag == "hstack") {
    box = GD.create("HBoxContainer");
    box.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    container = box;
    outer = box;
  } else if (tag == "grid") {
    box = GD.create("GridContainer");
    box.set("columns", GInt(__vrNum(props.cols, 2)));
    let g = __vrPx(__vrNum(props.gap, 12));
    box.set("theme_override_constants/h_separation", GInt(g));
    box.set("theme_override_constants/v_separation", GInt(g));
    container = box;
    outer = box;
  } else if (tag == "scroll") {
    let sc = GD.create("ScrollContainer");
    sc.set("size_flags_horizontal", GInt(3));
    let horizontal = props.horizontal == true;
    VUI.scrollbarStyle(sc);
    let inner = null;
    if (horizontal) {
      // A horizontal strip: HBox content, h-scroll on (bar hidden — chips
      // strips scroll by touch/drag), v-scroll off, natural height.
      sc.set("horizontal_scroll_mode", GInt(3)); // SCROLL_MODE_SHOW_NEVER
      sc.set("vertical_scroll_mode", GInt(0));
      inner = GD.create("HBoxContainer");
      inner.set("size_flags_vertical", GInt(3));
      if (props.height != null) {
        __vrSetMinSize(sc, -1.0, __vrNum(props.height, 48.0));
      }
    } else {
      sc.set("size_flags_vertical", GInt(3));
      inner = GD.create("VBoxContainer");
      inner.set("size_flags_horizontal", GInt(3));
    }
    inner.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    // pad on a scroll = content padding INSIDE the scroll area. Handled here
    // (margin between sc and inner) — the generic pad wrapper below must not
    // touch scroll: it used to wrap the already-parented inner, whose add
    // failed and left the scroll body empty.
    if (props.pad != null) {
      let sm = __vrPad(inner, __vrNum(props.pad, 0));
      sm.set("size_flags_horizontal", GInt(3));
      sm.set("size_flags_vertical", GInt(3));
      sc.call("add_child", [sm]);
    } else {
      sc.call("add_child", [inner]);
    }
    container = inner;
    outer = sc;
  } else if (tag == "center") {
    let c = GD.create("CenterContainer");
    // Centering needs room: fill the parent by default (like VUI.center).
    c.set("size_flags_horizontal", GInt(3));
    c.set("size_flags_vertical", GInt(3));
    container = c;
    outer = c;
  } else if (tag == "stack") {
    let c = GD.create("Control");
    container = c;
    outer = c;
  } else if (tag == "panel" || tag == "card") {
    let pc = GD.create("PanelContainer");
    // Material surfaces: a card is an elevated surfaceContainerLow container
    // (Flutter Card), a panel is the same surface without the shadow.
    // variant="filled" -> surfaceContainerHighest, flat; "outlined" ->
    // surface + hairline outline.
    let bg = t.surfaceContainerLow;
    let shadow = tag == "card" ? 1 : 0;
    if (props.variant == "filled") {
      bg = t.surfaceContainerHighest;
      shadow = 0;
    } else if (props.variant == "outlined") {
      bg = t.surface;
      shadow = 0;
    }
    if (props.shadow != null) {
      shadow = __vrNum(props.shadow, shadow);
    }
    if (props.bg != null) {
      let c = __vrColor(props.bg);
      if (c != null) {
        bg = c;
      }
    }
    let radius = __vrNum(props.radius, tag == "card" ? t.radiusM : t.radiusL);
    let border = __vrNum(props.border, 0);
    let borderColor = __vrColor(props.borderColor) ?? __vrColor(props.accent);
    if (props.variant == "outlined" && border == 0) {
      border = 1;
      if (borderColor == null) {
        borderColor = t.outlineVariant;
      }
    }
    if (props.accent != null && border == 0) {
      border = 1;
    }
    pc.set(
      "theme_override_styles/panel",
      VUI.styleBox({ bg: bg, radius: radius, shadow: shadow, border: border, borderColor: borderColor, skin: tag })
    );
    let inner = GD.create("VBoxContainer");
    inner.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    let pad = __vrNum(props.pad, 16);
    let wrap = __vrPad(inner, pad);
    pc.call("add_child", [wrap]);
    container = inner;
    outer = pc;
  } else {
    // view / div / column / vstack / section / …  → a vertical box
    box = GD.create("VBoxContainer");
    box.set("theme_override_constants/separation", GInt(__vrPx(__vrNum(props.gap, 12))));
    container = box;
    outer = box;
  }

  // Optional padding wrapper for the simple box containers. Scroll handles its
  // pad internally (its container is already parented to the ScrollContainer).
  if (props.pad != null && tag != "panel" && tag != "card" && tag != "scroll") {
    let wrap = __vrPad(container, __vrNum(props.pad, 0));
    outer = wrap;
  }

  inst.node = outer;
  inst.container = container;

  if (props.grow == true || props.expand == true) {
    outer.set("size_flags_horizontal", GInt(3));
    outer.set("size_flags_vertical", GInt(3));
  }
  __vrApplyStyle(inst, props.style);
}

function __vrPad(inner, pad) {
  if (pad == null || pad <= 0) {
    return inner;
  }
  let m = GD.create("MarginContainer");
  m.set("theme_override_constants/margin_left", GInt(pad));
  m.set("theme_override_constants/margin_top", GInt(pad));
  m.set("theme_override_constants/margin_right", GInt(pad));
  m.set("theme_override_constants/margin_bottom", GInt(pad));
  m.call("add_child", [inner]);
  return m;
}

// ---- text props (shared by text/heading/caption/icon) ----------------------

function __vrApplyTextProps(inst, oldProps, props, defaultSize, dim) {
  let t = VUI.theme();
  let l = inst.node;
  l.set("text", __vrTextOf(props));
  l.set("theme_override_font_sizes/font_size", GInt(__vrNum(props.size, defaultSize)));
  let color = __vrColor(props.color);
  if (color == null) {
    color = t.text;
    if (dim == true || props.dim == true) {
      color = t.textDim;
    }
    if (props.faint == true) {
      color = t.textFaint;
    }
  }
  l.set("theme_override_colors/font_color", color);
  // Explicit app font on every label (weight variant or regular) — theme
  // inheritance alone can miss, and the emoji fallback rides on this font.
  let wf = VUI.fonts();
  if (props.weight == "bold" && wf.bold != null) {
    l.set("theme_override_fonts/font", wf.bold);
  } else if (props.weight == "medium" && wf.medium != null) {
    l.set("theme_override_fonts/font", wf.medium);
  } else if (wf.regular != null) {
    l.set("theme_override_fonts/font", wf.regular);
  }
  if (props.align == "center") {
    l.set("horizontal_alignment", GInt(1));
  } else if (props.align == "right") {
    l.set("horizontal_alignment", GInt(2));
  } else if (props.align == "left") {
    l.set("horizontal_alignment", GInt(0));
  }
  if (props.wrap == true) {
    l.set("autowrap_mode", GInt(3));
    l.set("size_flags_horizontal", GInt(3));
  }
  if (props.grow == true || props.expand == true) {
    l.set("size_flags_horizontal", GInt(3));
  }
}

// ---- button ----------------------------------------------------------------

function __vrCreateButton(inst, props, t) {
  let b = GD.create("Button");
  inst.node = b;
  inst.container = null;
  b.set("focus_mode", GInt(0));
  __vrStyleButton(b, props, t);
  b.set("text", __vrTextOf(props));
  b.set("theme_override_font_sizes/font_size", GInt(__vrNum(props.fontSize, t.fontS)));
  let bFont = VUI.fonts();
  if (bFont.medium != null) {
    b.set("theme_override_fonts/font", bFont.medium);
  }
  if (props.disabled == true) {
    b.set("disabled", true);
  }
  __vrSetMinSize(b, __vrNum(props.minWidth, 0.0), __vrNum(props.height, t.controlHeight));
  if (props.wide == true || props.grow == true) {
    b.set("size_flags_horizontal", GInt(3));
  }
  // Stable signal binding: the closure reads the CURRENT prop off `inst`.
  b.connect("pressed", (a) => {
    let p = inst.props;
    __vrCall0(p.onPress);
    __vrCall0(p.onClick);
    __vrCall0(p.onTap);
  });
}

function __vrStyleButton(b, props, t) {
  // One source of truth: the shared Material button styler in ui.js.
  VUI.buttonStyle(b, props.kind, { radius: props.radius, padX: props.padX });
}

// ---- field (text input) ----------------------------------------------------

function __vrCreateField(inst, props, t) {
  let e = GD.create("LineEdit");
  inst.node = e;
  inst.container = null;
  inst.fieldValue = "" + (props.value ?? props.defaultValue ?? "");
  if (props.placeholder != null) {
    e.set("placeholder_text", props.placeholder);
  }
  if (inst.fieldValue != "") {
    e.set("text", inst.fieldValue);
  }
  if (props.obscure == true || props.type == "password") {
    e.set("secret", true);
  }
  e.set("size_flags_horizontal", GInt(3));
  VUI.fieldStyle(e);
  if (props.height != null) {
    __vrSetMinSize(e, 0.0, __vrNum(props.height, t.fieldHeight));
  }
  e.connect("text_changed", (a) => {
    inst.fieldValue = a[0];
    __vrCall(inst.props.onChange, a[0]);
    __vrCall(inst.props.onChanged, a[0]);
  });
  e.connect("text_submitted", (a) => {
    inst.fieldValue = a[0];
    __vrCall(inst.props.onSubmit, a[0]);
  });
}

// ---- textarea (multiline input) ---------------------------------------------

function __vrCreateTextArea(inst, props, t) {
  let e = GD.create("TextEdit");
  inst.node = e;
  inst.container = null;
  inst.fieldValue = "" + (props.value ?? props.defaultValue ?? "");
  if (props.placeholder != null) {
    e.set("placeholder_text", props.placeholder);
  }
  if (inst.fieldValue != "") {
    e.set("text", inst.fieldValue);
  }
  e.set("wrap_mode", GInt(1)); // TextEdit.LINE_WRAPPING_BOUNDARY
  __vrSetMinSize(e, 0.0, __vrNum(props.height, 120.0));
  e.set("size_flags_horizontal", GInt(3));
  VUI.textareaStyle(e);
  e.connect("text_changed", (a) => {
    let v = inst.node.get("text");
    inst.fieldValue = "" + v;
    __vrCall(inst.props.onChange, inst.fieldValue);
    __vrCall(inst.props.onChanged, inst.fieldValue);
  });
}

// ---- select / dropdown -------------------------------------------------------

function __vrApplySelectItems(inst, props, t) {
  let e = inst.node;
  e.call("clear");
  let items = props.options ?? props.items ?? [];
  inst.selectValues = [];
  for (let i = 0; i < items.length; i++) {
    let it = items[i];
    let label = it;
    let value = it;
    if (__isType(it, "map")) {
      label = it.label ?? ("" + it.value);
      value = it.value ?? it.label;
    }
    e.call("add_item", ["" + label, GInt(i)]);
    inst.selectValues.push(value);
  }
  let idx = __vrNum(props.index, -1);
  if (idx < 0 && props.value != null) {
    for (let i = 0; i < inst.selectValues.length; i++) {
      if (inst.selectValues[i] == props.value) {
        idx = i;
      }
    }
  }
  if (idx >= 0) {
    e.call("select", [GInt(idx)]);
  }
}

function __vrCreateSelect(inst, props, t) {
  let e = GD.create("OptionButton");
  inst.node = e;
  inst.container = null;
  e.set("focus_mode", GInt(0));
  VUI.dropdownStyle(e);
  __vrSetMinSize(e, __vrNum(props.minWidth, 0.0), __vrNum(props.height, t.fieldHeight));
  if (props.wide == true || props.grow == true) {
    e.set("size_flags_horizontal", GInt(3));
  }
  __vrApplySelectItems(inst, props, t);
  e.connect("item_selected", (a) => {
    let i = a[0];
    let value = null;
    if (inst.selectValues != null && i >= 0 && i < inst.selectValues.length) {
      value = inst.selectValues[i];
    }
    __vrCall(inst.props.onChange, value);
    __vrCall(inst.props.onSelect, i);
  });
}

// ---- richtext (BBCode) --------------------------------------------------------

function __vrCreateRichText(inst, props, t) {
  let l = GD.create("RichTextLabel");
  inst.node = l;
  inst.container = null;
  l.set("bbcode_enabled", true);
  l.set("fit_content", true);
  l.set("text", props.markup ?? __vrTextOf(props));
  l.set("theme_override_font_sizes/normal_font_size", GInt(__vrNum(props.size, t.fontM)));
  l.set("theme_override_colors/default_color", __vrColor(props.color) ?? t.text);
  l.set("size_flags_horizontal", GInt(3));
  if (props.height != null) {
    __vrSetMinSize(l, 0.0, __vrNum(props.height, 0.0));
  }
}

// ---- image -----------------------------------------------------------------

function __vrCreateImage(inst, props, t) {
  let r = GD.create("TextureRect");
  inst.node = r;
  inst.container = null;
  r.set("expand_mode", GInt(1));
  r.set("stretch_mode", GInt(5));
  let src = props.src ?? props.url;
  if (src != null) {
    let tex = GD.load(src);
    if (!GD.isError(tex)) {
      r.set("texture", tex);
    }
  }
  __vrSetMinSize(r, __vrNum(props.width, 0.0), __vrNum(props.height, 0.0));
}

// ---- progress --------------------------------------------------------------

function __vrCreateProgress(inst, props, t) {
  let p = GD.create("ProgressBar");
  inst.node = p;
  inst.container = null;
  p.set("min_value", GFloat(0.0));
  p.set("max_value", GFloat(__vrNum(props.max, 100.0)));
  p.set("value", GFloat(__vrNum(props.value, 0.0)));
  p.set("show_percentage", false);
  __vrSetMinSize(p, 0.0, __vrNum(props.height, 6.0));
  p.set("size_flags_horizontal", GInt(3));
  p.set(
    "theme_override_styles/background",
    VUI.styleBox({ bg: t.surfaceContainerHighest, radius: t.radiusFull })
  );
  p.set(
    "theme_override_styles/fill",
    VUI.styleBox({ bg: __vrColor(props.color) ?? t.primary, radius: t.radiusFull })
  );
}

// ---- slider ----------------------------------------------------------------

function __vrCreateSlider(inst, props, t) {
  let s = GD.create("HSlider");
  inst.node = s;
  inst.container = null;
  s.set("min_value", GFloat(__vrNum(props.min, 0.0)));
  s.set("max_value", GFloat(__vrNum(props.max, 100.0)));
  s.set("step", GFloat(__vrNum(props.step, 1.0)));
  s.set("value", GFloat(__vrNum(props.value, 0.0)));
  s.set("focus_mode", GInt(0));
  VUI.sliderStyle(s);
  s.set("size_flags_horizontal", GInt(3));
  s.connect("value_changed", (a) => {
    __vrCall(inst.props.onChange, a[0]);
    __vrCall(inst.props.onChanged, a[0]);
  });
}

// ---- switch / checkbox -----------------------------------------------------

function __vrCreateSwitch(inst, props, t) {
  // The Material switch from the kit (pill track + animated knob); the handle
  // is kept on the instance so prop updates can drive it.
  let handle = VUI.toggle({
    value: props.checked == true || props.value == true,
    onChanged: (on) => {
      __vrCall(inst.props.onChange, on);
      __vrCall(inst.props.onChanged, on);
    },
  });
  let label = __vrTextOf(props);
  if (label != "") {
    let rowBox = GD.create("HBoxContainer");
    rowBox.set("theme_override_constants/separation", GInt(12));
    let lab = GD.create("Label");
    lab.set("text", label);
    lab.set("theme_override_font_sizes/font_size", GInt(t.fontS));
    lab.set("theme_override_colors/font_color", t.onSurface);
    lab.set("vertical_alignment", GInt(1));
    lab.set("size_flags_horizontal", GInt(3));
    rowBox.call("add_child", [lab]);
    rowBox.call("add_child", [handle.node]);
    inst.node = rowBox;
  } else {
    inst.node = handle.node;
  }
  inst.container = null;
  inst.toggleHandle = handle;
}

function __vrCreateCheckbox(inst, props, t) {
  // The Material checkbox from the kit.
  let handle = VUI.checkbox({
    value: props.checked == true || props.value == true,
    label: __vrTextOf(props),
    onChanged: (on) => {
      __vrCall(inst.props.onChange, on);
      __vrCall(inst.props.onChanged, on);
    },
  });
  inst.node = handle.node;
  inst.container = null;
  inst.toggleHandle = handle;
}

// ---- divider ---------------------------------------------------------------

function __vrCreateDivider(inst, props, t) {
  let d = GD.create("Panel");
  inst.node = d;
  inst.container = null;
  if (props.vertical == true) {
    __vrSetMinSize(d, __vrNum(props.thickness, 1.0), 8.0);
    d.set("size_flags_vertical", GInt(3));
  } else {
    __vrSetMinSize(d, 0.0, __vrNum(props.thickness, 1.0));
    d.set("size_flags_horizontal", GInt(3));
  }
  d.set("mouse_filter", GInt(2));
  d.set("theme_override_styles/panel", VUI.styleBox({ bg: __vrColor(props.color) ?? t.outlineVariant, radius: 1 }));
}

// ---------------------------------------------------------------------------
// driver update: patch a host node's props in place
// ---------------------------------------------------------------------------

function __vrDriverUpdate(inst, oldProps, props) {
  let tag = inst.tag;
  let t = VUI.theme();

  if (__vrIs3DTag(tag)) {
    __vrUpdate3D(inst, oldProps, props);
    return;
  }

  if (__vrIsContainerTag(tag)) {
    if (props.grow == true || props.expand == true) {
      inst.node.set("size_flags_horizontal", GInt(3));
      inst.node.set("size_flags_vertical", GInt(3));
    }
    if (tag == "grid" && props.cols != oldProps.cols) {
      inst.container.set("columns", GInt(__vrNum(props.cols, 2)));
    }
    __vrApplyStyle(inst, props.style);
    return;
  }

  if (tag == "text" || tag == "span" || tag == "p" || tag == "label" || tag == "paragraph") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontM, false);
    return;
  }
  if (tag == "heading" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "title") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontXL, false);
    return;
  }
  if (tag == "caption" || tag == "small" || tag == "muted") {
    __vrApplyTextProps(inst, oldProps, props, VUI.theme().fontXS, true);
    return;
  }
  if (tag == "icon") {
    __vrApplyTextProps(inst, oldProps, props, __vrNum(props.size, t.fontL), false);
    return;
  }
  if (tag == "button") {
    inst.node.set("text", __vrTextOf(props));
    if (props.kind != oldProps.kind) {
      __vrStyleButton(inst.node, props, t);
    }
    if (props.disabled != oldProps.disabled) {
      inst.node.set("disabled", props.disabled == true);
    }
    return;
  }
  if (tag == "input" || tag == "field" || tag == "textinput" || tag == "textarea") {
    // Controlled input: push value when the prop diverges from the widget.
    if (props.value != null && ("" + props.value) != inst.fieldValue) {
      inst.fieldValue = "" + props.value;
      inst.node.set("text", inst.fieldValue);
    }
    if (props.placeholder != oldProps.placeholder && props.placeholder != null) {
      inst.node.set("placeholder_text", props.placeholder);
    }
    // Keep secrecy in sync on reuse (a reconciled password field must not
    // leave the next occupant masked, and vice versa).
    let secret = props.obscure == true || props.type == "password";
    let oldSecret = oldProps.obscure == true || oldProps.type == "password";
    if (secret != oldSecret) {
      inst.node.set("secret", secret);
    }
    return;
  }
  if (tag == "select" || tag == "dropdown" || tag == "option") {
    if (props.options != oldProps.options || props.items != oldProps.items || props.index != oldProps.index || props.value != oldProps.value) {
      __vrApplySelectItems(inst, props, t);
    }
    return;
  }
  if (tag == "richtext") {
    inst.node.set("text", props.markup ?? __vrTextOf(props));
    return;
  }
  if (tag == "image" || tag == "img") {
    let src = props.src ?? props.url;
    let osrc = oldProps.src ?? oldProps.url;
    if (src != null && src != osrc) {
      let tex = GD.load(src);
      if (!GD.isError(tex)) {
        inst.node.set("texture", tex);
      }
    }
    return;
  }
  if (tag == "progress") {
    inst.node.set("max_value", GFloat(__vrNum(props.max, 100.0)));
    inst.node.set("value", GFloat(__vrNum(props.value, 0.0)));
    return;
  }
  if (tag == "slider") {
    inst.node.set("max_value", GFloat(__vrNum(props.max, 100.0)));
    inst.node.set("min_value", GFloat(__vrNum(props.min, 0.0)));
    if (props.value != oldProps.value) {
      inst.node.set("value", GFloat(__vrNum(props.value, 0.0)));
    }
    return;
  }
  if (tag == "chip") {
    if (inst.chipHandle != null && props.selected != oldProps.selected) {
      inst.chipHandle.setSelected(props.selected == true);
    }
    return;
  }
  if (tag == "switch" || tag == "toggle" || tag == "checkbox") {
    let on = props.checked == true || props.value == true;
    if (inst.toggleHandle != null) {
      if (tag == "checkbox") {
        if (inst.toggleHandle.isChecked() != on) {
          inst.toggleHandle.setChecked(on);
        }
      } else {
        if (inst.toggleHandle.isOn() != on) {
          inst.toggleHandle.setOn(on);
        }
      }
    }
    return;
  }
}

// ===========================================================================
// PUBLIC API — the React namespace + the VictorClient renderer entry points
// ===========================================================================

var React = {
  createElement: createElement,
  Fragment: __VR_FRAGMENT,
  StrictMode: __VR_FRAGMENT,
  useState: useState,
  useReducer: useReducer,
  useEffect: useEffect,
  useLayoutEffect: useLayoutEffect,
  useInsertionEffect: useInsertionEffect,
  useRef: useRef,
  useMemo: useMemo,
  useCallback: useCallback,
  useContext: useContext,
  createContext: createContext,
  useImperativeHandle: useImperativeHandle,
  useId: useId,
  useSyncExternalStore: useSyncExternalStore,
  useTransition: useTransition,
  useDeferredValue: useDeferredValue,
  useDebugValue: useDebugValue,
  useFrame: useFrame,
  useViewport: useViewport,
  memo: memo,
  forwardRef: forwardRef,
};

// Render an element tree into an existing Godot container node (a GObj that
// accepts add_child). Returns a root handle with update()/unmount().
function __vrRenderRoot(element, container) {
  let root = {
    kind: "roothost",
    node: container,
    container: container,
    attached: [],
    childInstances: [],
    hostContainer: null,
    alive: true,
    element: null,
  };
  root.hostContainer = root;
  __vrReconcileChildren(root, __vrNormalize(element), root);
  __vrSyncFrom(root);
  __vrScheduleEffects();
  return {
    root: root,
    render: (next) => {
      __vrReconcileChildren(root, __vrNormalize(next), root);
      __vrSyncFrom(root);
      __vrScheduleEffects();
    },
    unmount: () => {
      let cs = root.childInstances;
      for (let i = 0; i < cs.length; i++) {
        __vrUnmount(cs[i]);
      }
      root.childInstances = [];
      __vrSyncFrom(root);
    },
  };
}

// The ReactDOM-equivalent client surface.
var VictorClient = {
  // createRoot(container).render(<App/>)  — the React 18 root API.
  createRoot: (container) => {
    let node = __vuiNode(container);
    let handle = null;
    return {
      render: (element) => {
        if (handle == null) {
          handle = __vrRenderRoot(element, node);
        } else {
          handle.render(element);
        }
      },
      unmount: () => {
        if (handle != null) {
          handle.unmount();
        }
      },
    };
  },

  // Legacy render(<App/>, container).
  render: (element, container) => {
    return __vrRenderRoot(element, __vuiNode(container));
  },

  // The one-call bootstrap the Next.js template's entry uses: set the theme,
  // create the full-screen VUI app (CanvasLayer + page), and mount the React
  // tree into it. Returns { app, root } so callers can reach the VUI app.
  mountApp: (element, options) => {
    let o = options;
    if (o == null) {
      o = {};
    }
    if (o.theme == "light") {
      VUI.use(VUI.themeLight());
    } else {
      VUI.use(VUI.themeDark());
    }
    let app = VUI.app(o);
    // A vertical mount box fills the page so React children stack naturally.
    let mount = GD.create("VBoxContainer");
    mount.set("theme_override_constants/separation", GInt(0));
    app.push(mount);
    let handle = __vrRenderRoot(element, mount);
    return { app: app, root: handle, mount: mount };
  },
};

// A tiny convenience namespace for Victor-specific extras a React app may want
// (theme access, colour parsing, the raw engine + kit if it drops down a level).
var Victor = {
  theme: () => {
    return VUI.theme();
  },
  useTheme: () => {
    // dark by default; the theme object is a plain value
    return VUI.theme();
  },
  color: (v) => {
    return __vrColor(v);
  },
  toast: (msg, o) => {
    VUI.toast(msg, o);
  },
  dialog: (o) => {
    VUI.dialog(o);
  },
  onFrame: (cb) => {
    __vrInstallFrame();
    __vrFrameCbs.push(cb);
  },
  useFrame: useFrame,
  useViewport: useViewport,
  metrics: () => {
    return VUI.metrics();
  },
  // 3D building blocks for imperative use (inside useFrame, refs, escape hatch).
  g3: () => {
    return G3;
  },
  interval: (ms, cb) => {
    return GTimer.periodic(ms, cb);
  },
  timeout: (ms, cb) => {
    return GTimer.after(ms, cb);
  },
};

// ---------------------------------------------------------------------------
// primitive components — capitalised host wrappers so a component tree reads
// like React Native (`<View>`, `<Text>`, `<Button>` …) as well as web tags.
// ---------------------------------------------------------------------------

function View(props) { return jsx("view", props); }
function Row(props) { return jsx("row", props); }
function Column(props) { return jsx("column", props); }
function Stack(props) { return jsx("stack", props); }
function Scroll(props) { return jsx("scroll", props); }
function Center(props) { return jsx("center", props); }
function Panel(props) { return jsx("panel", props); }
function Card(props) { return jsx("card", props); }
function Grid(props) { return jsx("grid", props); }
function Text(props) { return jsx("text", props); }
function Heading(props) { return jsx("heading", props); }
function Caption(props) { return jsx("caption", props); }
function Icon(props) { return jsx("icon", props); }
function Button(props) { return jsx("button", props); }
function TextInput(props) { return jsx("input", props); }
function Image(props) { return jsx("image", props); }
function Progress(props) { return jsx("progress", props); }
function Slider(props) { return jsx("slider", props); }
function Switch(props) { return jsx("switch", props); }
function Checkbox(props) { return jsx("checkbox", props); }
function Divider(props) { return jsx("divider", props); }
function Spacer(props) { return jsx("spacer", props); }

function TextArea(props) { return jsx("textarea", props); }
function Chip(props) { return jsx("chip", props); }
function BadgePill(props) { return jsx("badge", props); }
function Avatar(props) { return jsx("avatar", props); }
function Fab(props) { return jsx("fab", props); }
function ListTile(props) { return jsx("tile", props); }
function Select(props) { return jsx("select", props); }
function RichText(props) { return jsx("richtext", props); }

// 3D primitives (the 2D<->3D bridge and the Node3D family).
function Scene3D(props) { return jsx("scene3d", props); }
function GltfModel(props) { return jsx("gltf", props); }
function Node3D(props) { return jsx("node3d", props); }
function Mesh(props) { return jsx("mesh", props); }
function Box(props) { return jsx("box", props); }
function Sphere(props) { return jsx("sphere", props); }
function Cylinder(props) { return jsx("cylinder", props); }
function Capsule(props) { return jsx("capsule", props); }
function Plane3D(props) { return jsx("plane3d", props); }
function Torus(props) { return jsx("torus", props); }
function Camera3D(props) { return jsx("camera3d", props); }
function DirectionalLight(props) { return jsx("directionallight", props); }
function OmniLight(props) { return jsx("omnilight", props); }
function SpotLight(props) { return jsx("spotlight", props); }
function Environment3D(props) { return jsx("environment", props); }
function StaticBody3D(props) { return jsx("staticbody3d", props); }
function Area3D(props) { return jsx("area3d", props); }
function CollisionShape3D(props) { return jsx("collisionshape3d", props); }
