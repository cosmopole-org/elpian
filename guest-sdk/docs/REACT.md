# VReact — React on the Elpian VM

`react.js` is the third guest library in the Victor stack, composed after
`godot.js` (the engine bridge) and `ui.js` (the VUI widget kit). It turns the
Elpian VM into a **React renderer whose "DOM" is the retained Godot scene
graph** — the runtime that a compiled Next.js-on-Victor program (see
`../../../templates/victor-nextjs/`) runs on.

```
  import 'godot.js';
  import 'ui.js';
  import 'react.js';
```

## What it is — and why it is not a port of React

VReact is a faithful, from-scratch reimplementation of React's *programming
model*: the element factory, function components, the full hook surface, and a
keyed reconciler that mutates retained host nodes. It is **not** a port of
Facebook's `react` + `react-reconciler` packages.

Those packages cannot run here. `js2elpian` compiles a deliberate JavaScript
**subset** to no-JIT Elpian bytecode (see the subset chapter in
`victor/js2elpian/src/lib.rs`): no spread/rest, no destructuring, no template
literals, no `typeof`/`instanceof`/`try`, no prototypes, `Map`/`Set`, generators
or `Object.*`/`Array.*` statics. React's implementation depends on all of them.

So VReact stands to React exactly as **Preact** does: the same public API and
semantics, an independent tiny core. A component written against VReact *is*
ordinary React — the rules of hooks, the deps arrays, and the reconciliation
guarantees all hold. This is the "well-engineered, don't-reinvent-the-model"
answer given the hard constraint that the reconciler itself must be expressible
in the subset and run on the VM with no privileged access.

## The rendering model

React's host config here targets Godot `Control` nodes instead of the DOM:

- Every intrinsic element (`"column"`, `"text"`, `"button"`, `"input"`, … plus
  web aliases `"div"`, `"span"`, `"img"`, …) is a **host driver** that creates a
  real retained Godot node, patches its properties on update, and routes its
  signals back into event props.
- The reconciler diffs the element tree on each render and applies the minimal
  node mutations. Godot paints the retained scene; the VM only reacts.
- Event handlers are bound **once** through a stable indirection: the baked
  signal closure reads the *current* prop off the persistent instance, so
  re-renders never re-wire signals.
- Children of a host are flattened (descending through components and fragments)
  into an ordered list of child nodes, and the host container is synced to that
  list — kept nodes are reused (preserving their internal state), removed nodes
  are freed.
- `setState`/`dispatch` mark the owning instance dirty and schedule a microtask
  flush (`__later`, the VM event-loop seam); the flush re-renders dirty
  components and re-syncs the nearest host container. Effects run after commit.

## Public surface

- `React` namespace + top-level hooks: `useState`, `useReducer`, `useEffect`,
  `useLayoutEffect`, `useInsertionEffect`, `useRef`, `useMemo`, `useCallback`,
  `useContext`, `createContext`, `useImperativeHandle`, `useId`,
  `useSyncExternalStore`, `useTransition`, `useDeferredValue`, `useDebugValue`,
  `memo`, `forwardRef`, `Fragment`, `StrictMode`.
- `_jsx` / `_jsxs` / `_jsxDEV` / `_Fragment` — the automatic-JSX-runtime entry
  points Babel lowers to (so a build never emits variadic `createElement`).
- `VictorClient` — the ReactDOM-equivalent: `createRoot(container).render(el)`,
  `render(el, container)`, and `mountApp(el, options)` (creates the VUI app and
  mounts the tree into it — what the generated entry calls).
- `Victor` — extras: `theme()`, `color()`, `toast()`, `dialog()`, `onFrame()`,
  `interval()`, `timeout()`.
- Capitalised primitives: `View`, `Row`, `Column`, `Stack`, `Scroll`, `Center`,
  `Panel`, `Card`, `Grid`, `Text`, `Heading`, `Caption`, `Icon`, `Button`,
  `TextInput`, `Image`, `Progress`, `Slider`, `Switch`, `Checkbox`, `Divider`,
  `Spacer` — and 3D: `Scene3D`, `Node3D`, `Mesh`, `Box`, `Sphere`, `Cylinder`,
  `Capsule`, `Plane3D`, `Torus`, `Camera3D`, `DirectionalLight`, `OmniLight`,
  `SpotLight`, `Environment3D`, `StaticBody3D`, `Area3D`, `CollisionShape3D`.
- `useFrame(delta => …)` — a per-frame callback (react-three-fiber idiom) fanned
  out from a single `GD.onProcess`, always calling the latest closure via a ref.

## Mixed 2D + 3D

Victor renders with Godot, so 3D is first-class. VReact adds a `Node3D`-family of
host drivers plus the `<scene3d>` element — a `SubViewportContainer` + `SubViewport`
(built by `G3.viewport` in `godot.js`) that embeds a real 3D world inside the 2D
Control tree. Inside a `<scene3d>` you place `<camera3d>`, lights, an
`<environment>`, meshes (`<box>`, `<sphere>`, `<plane3d>`, …) and `<node3d>`
groups; transforms are props (`position`, `rotation` in degrees, `scale`,
`visible`), materials are props (`color`, `emission`, `metallic`, `roughness`).
Refs on 3D elements yield the live Godot node (`GObj`) to drive imperatively in
`useFrame`. `<node type="AnyGodotClass" />` is a reflective escape hatch to any
engine class the named tags don't cover. The 3D vocabulary lives in the `G3`
namespace in `godot.js`, so raw JS guests (no React) get the same helpers.

## Documented subset caveats

These are consequences of the VM, called out where they leak:

1. **No first-class null.** An absent value reads as `0` and `x == null` is also
   true for a numeric `0`. A literal numeric `0` therefore does not render as a
   text child (React would render `"0"`) — use `"" + n`. Every other value
   renders normally.
2. **Deps use `==`** (the VM lowers `===` to it): scalar value identity and
   object reference identity — the contract apps rely on.
3. **One provider per context.** A single `<Context.Provider>` per context is
   supported app-wide (the value lives on the context object and consumers
   subscribe); nesting two providers of the *same* context with different values
   is not. Distinct contexts nest freely.
4. **Out-of-bounds array reads don't return null**, so the runtime tracks hook
   slots by list length, never by a null check — a rule any subset code touching
   arrays must follow.

## Tests

`victor/bridge/capi/tests/run_react_demo.rs` compiles the runtime + the demo
(`victor/bridge/project/scripts/react_demo.js`) in the subset and runs it against
a mock engine: it asserts the mounted Control-node op stream, then presses the
counter and verifies the `setState` → re-render → node-patch round-trip and the
`useEffect` (+ cleanup) firing over the bridge.
