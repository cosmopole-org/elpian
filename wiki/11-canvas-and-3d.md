# 11 — Canvas 2D and the embedded Godot `Scene3D`

Elpian has two rendering surfaces beyond the widget tree: a 2D canvas drawn by
Flutter's own engine, and **`Scene3D`, an embedded Godot 4 engine**.

> **This chapter changed.** Elpian previously had two in-house 3D renderers — a
> Bevy (Rust/GPU) bridge and a pure-Dart software renderer, reached through
> `BevyScene` / `Bevy3D` / `GameScene` / `Game3D`. **Both are gone.** 3D is now a
> real Godot engine embedded as a widget, adapted from Victor's React Native
> integration. The only 3D tag is `Scene3D` (alias `scene3d`).

---

# Canvas 2D

An HTML5-Canvas-shaped API over Flutter's Skia engine. Two ways to drive it: a
command list in a node, or imperative host calls.

## As a node

```json
{
  "type": "Canvas",
  "props": {
    "width": 400,
    "height": 300,
    "commands": [
      { "type": "fillStyle", "params": { "color": "#FF0000" } },
      { "type": "fillRect",  "params": { "x": 50, "y": 50, "width": 100, "height": 80 } }
    ]
  }
}
```

Use `CachedCanvas` instead of `Canvas` when the drawing is static — it caches the
rasterised result.

## As host calls

68 canvas API names are registered (`VmHostApiCatalog.canvasApiNames`):

**Context** — `canvas.ctx.create` `ctx.dispose` `ctx.clear` `ctx.setSize`
`ctx.addCommand(s)` `addCommand(s)` `clear` `getCommands`

**Paths** — `beginPath` `closePath` `moveTo` `lineTo` `quadraticCurveTo`
`bezierCurveTo` `arc` `arcTo` `ellipse` `rect` `roundRect` `circle`

**Shapes** — `fillRect` `strokeRect` `clearRect` `fillCircle` `strokeCircle`
`fillPolygon` `strokePolygon` `fill` `stroke` `clip`

**Text** — `fillText` `strokeText` `setFont` `setTextAlign` `setTextBaseline`

**Images** — `drawImage` `drawImageRect` `putImageData` `getImageData`
`createImageData`

**Transforms/state** — `save` `restore` `translate` `rotate` `scale` `transform`
`setTransform` `resetTransform`

**Style** — `setFillStyle` `setStrokeStyle` `setLineWidth` `setLineCap`
`setLineJoin` `setMiterLimit` `setLineDash` `setLineDashOffset` `setShadowBlur`
`setShadowColor` `setShadowOffsetX` `setShadowOffsetY` `setGlobalAlpha`
`setGlobalCompositeOperation`

**Gradients** — `createLinearGradient` `createRadialGradient` `addColorStop`
`createPattern`

From Dart: `CanvasBuilder().fillStyle('#FF0000').fillRect(50, 50, 100, 80).build()`,
plus `CanvasPresets` (`star`, `polygon`, `arrow`).

---

# `Scene3D` — embedded Godot

## Why Godot, reflectively

Elpian does **not** wrap Godot's API by hand. The engine side runs a *reflective*
interpreter (`ElpianScene3D::exec_op_json`, the `elpian_godot` GDExtension) that
addresses the engine **by name** through `ClassDB`. Coverage is therefore
complete by construction — every node class, method, property, signal, singleton
and constant, including ones added in future Godot versions — and the Dart side
only transports ops and marshals values.

The op vocabulary is identical to Victor's, so the C++ interpreter is reused
verbatim; only the transport differs (Flutter platform channels here, JSI there).

```
Dart                                  │ Kotlin                │ Godot 4
GodotController                       │                       │
  ├ allocates handles                 │                       │
  ├ batches ops per frame             │                       │
  └ MethodChannel elpian/godot/ops ──▶│ OpQueue ─ pollOps() ─▶│ OpSink.gd
Scene3D → AndroidView/UiKitView ─────▶│ GodotSurfaceView      │  └ ElpianScene3D
EventChannel elpian/godot/events ◀────│ SignalRelay           │     .exec_op_json()
```

## The two ways to drive it

### 1. Declaratively — the JSON DSL

```dart
Scene3D(
  initialScene: const {
    'environment': {'bg': '#0d1117', 'ambient': '#8894b0'},
    'camera':      {'position': [0, 3, 8], 'rotation': [-18, 0, 0], 'fov': 55},
    'lights':  [ {'type': 'directional', 'energy': 1.3, 'shadow': true,
                  'rotation': [-50, -30, 0]} ],
    'nodes':   [ {'type': 'mesh', 'shape': 'torus', 'id': 'ring',
                  'color': '#6699ff', 'position': [0, 1, 0],
                  'children': [ {'type': 'mesh', 'shape': 'sphere', 'id': 'bead'} ]} ],
  },
  onReady: (scene) => scene.require('ring').set('scale', const Vector3(1.4, 1.4, 1.4)),
)
```

| Key | Meaning |
|---|---|
| `environment` | `bg`, `ambient`, `ambientEnergy` |
| `camera` | `position`, `rotation` (degrees), `fov`, `current`, `id` |
| `lights[]` | `type`: `directional` (default) \| `omni`/`point` \| `spot`; `color`, `energy`, `shadow`, `range`, `angle` |
| `nodes[]` | `type`: `mesh` \| `node`/`group` \| `camera` \| `light` \| **any ClassDB class name** |
| on any node | `id`, `position`, `rotation`, `scale`, `visible`, `props`, `children` |
| on a `mesh` | `shape`: `box` `sphere` `cylinder` `capsule` `plane` `prism` `torus`; `color`, `metallic`, `roughness`, `emission`, `size`, `radius`, `height`, … |

Colours accept `#RGB`, `#RRGGBB`, `#RRGGBBAA` or `[r,g,b(,a)]` in 0..1.

A `type` the DSL does not recognise is taken as a **raw ClassDB class name**, so
the DSL reaches the whole engine rather than a curated list:

```json
{ "type": "CSGBox3D", "id": "csg", "props": { "size": [2, 1, 2] } }
```

The whole build is issued inside one batch — a scene of any size costs one
crossing.

### 2. Imperatively — the controller

```dart
final controller = GodotSceneController();

Scene3D(controller: controller, initialScene: {...});

// later — the full reflective API
final godot = controller.godot;
final crate = godot.create('RigidBody3D');        // ANY ClassDB class
crate.set('mass', const GFloat(2.5));
crate.setAll({'position': const Vector3(0, 5, 0), 'freeze': false});
crate.connect('body_entered', (args) => debugPrint('hit: $args'));
godot.mount(crate);

final input = godot.input();                       // any singleton
final pressed = await input.call('is_action_pressed', ['ui_accept']);
```

## `GodotObject` — every engine object

| Method | Does |
|---|---|
| `call(m, [args])` | Call any method, awaiting the result |
| `callVoid(m, [args])` | Call any method, no round trip — the hot path |
| `get(p)` / `set(p, v)` | Read / write any property |
| `setAll({...})` | Several properties in one op |
| `getIndexed(path)` / `setIndexed(path, v)` | Nested sub-property (`position:x`) |
| `connect(sig, cb, {flags})` / `disconnect(sig, id)` | Any signal ↔ a Dart closure |
| `signal(name)` / `emitSignal(name, [args])` | Signals as values |
| `addChild` / `removeChild` / `addChildren` | Tree |
| `queueFree()` / `freeNow()` / `release()` | Lifetime |

## `GodotController` — the engine facade

`create` · `createWith` · `singleton` · `tree` · `load` · `mount` · `constant` ·
`eval` · `classes` · `classInfo` · `audit` · `stats` · `callable` ·
`beginBatch`/`endBatch`/`flush` · `attachSurface`/`detachSurface`, plus the named
singletons `renderingServer` `physicsServer3D` `physicsServer2D` `audioServer`
`displayServer` `input` `engine` `os` `time` `projectSettings` `resourceLoader`.

## `g3` — the 3D convenience layer

`controller.g3` composes the reflective bridge into the nodes every scene needs:

```dart
g3.node(position:, rotation:, scale:, visible:)
g3.mesh(shape, options: {...}, material:)     // MeshInstance3D + primitive + material
g3.primitive(shape, options: {...})           // the mesh resource alone
g3.material(color:, metallic:, roughness:, emission:, emissionEnergy:, transparency:)
g3.camera(fov:, current:, position:, rotation:)
g3.dirLight(...) · g3.omniLight(...) · g3.spotLight(...)
g3.environment(bg:, ambient:, ambientEnergy:)
g3.instanceScene(path)                        // a PackedScene / imported .glb
g3.setTransform(node, position:, rotation:, scale:, visible:)
```

`position` / `rotation` / `scale` each accept a `Vector3`, an `[x, y, z]` list,
or a scalar (uniform). Rotation is in **degrees**.

## Value types and the int/float rule

`Vector2/2i/3/3i/4/4i` · `GodotColor` · `Rect2/2i` · `Plane` · `Quaternion` ·
`AABB` · `Basis` · `Transform2D/3D` · `Projection` · `StringName` · `NodePath` ·
`GRid` · `GSignal` · `GCallable` · `GDict` · `Packed` · `GInt` · `GFloat`.

> **`Color` is `GodotColor` here.** Flutter's `Color` is ubiquitous; a second
> `Color` from the barrel would shadow it in every consumer.

A Dart `num` is ambiguous at the boundary. Bare numbers marshal by Dart type
(`int` → int, `double` → float), which is usually right — but where an API
demands a specific one (enums, indices, flags, counts, font sizes) be explicit:

```dart
node.set('theme_override_font_sizes/font_size', const GInt(18));
mesh.set('radius', const GFloat(1));
```

**Number misbehaviour at the boundary is almost always this.**

## Performance: batching

Ops are batched automatically and flushed once per frame, so building a hundred
nodes is *one* crossing, not a hundred. Handles are allocated Dart-side, so
creates and writes never wait for a reply — only genuine reads do, and a read
flushes pending writes first so ordering holds.

```dart
godot.beginBatch();
for (var i = 0; i < 500; i++) { /* create, set, mount … */ }
await godot.endBatch();          // ONE crossing
```

Prefer `callVoid` over `call` when you do not need the return value.

## Degradation — this is load-bearing

Where no Godot artifact is present (web today, desktop, a debug build without the
plugin, any test), the binding resolves to `MockGodotBinding`: ops are recorded,
handles are minted, and the widget renders a placeholder. **A `Scene3D` is safe
to put in any tree** — the surrounding 2D app is unaffected. `controller.isLive`
tells you which you have.

## Layout interaction

A subtree containing `Scene3D` / `scene3d` makes its root **viewport-locked**: it
is never wrapped in a document scroll view, because a scene cannot be measured
for intrinsic height. Give a scene an explicit size or an `aspectRatio`, and put
scrolling UI *beside* it rather than around it.

## Taps

`clickable: true` reports taps to `ElpianSceneTaps.handler` with the node's
props — the hook `NextjsServerWidget` uses to turn a 3D tap into navigation.

## From a guest program

The `Scene3D` tag is registered, so a VM guest emits it like any other node:

```ts
el('Scene3D', {
  width: 400, height: 300,
  initialScene: {
    environment: { bg: '#0d1117' },
    camera: { position: [0, 3, 8] },
    lights: [{ type: 'directional', shadow: true }],
    nodes: [{ type: 'mesh', shape: 'box', color: '#6699ff' }],
  },
}, [])
```

## Getting a real engine

`elpian_ui` ships the Dart side only. The engine lives in the **`elpian_godot`**
package at the repo root; depend on it from your app:

```yaml
dependencies:
  elpian_ui:    { path: ../ }
  elpian_godot: { path: ../godot }   # ← turns the placeholder into a viewport
```

It is deliberately *not* a dependency of `elpian_ui`: the Godot library AAR is
~21 MB and an app with no 3D should not pay for it. The example app depends on
it; a plain `elpian_ui` consumer does not.

Three binary artifacts must exist before anything renders — the Godot library
AAR, the `elpian_godot` GDExtension, and the packed op-sink project.
`.github/workflows/build_godot_artifacts.yml` builds all three as one bundle
(downloading the AAR from the official Godot release rather than building the
engine), and `build_showcase.yml` restores it. When the bundle is absent the
build still succeeds and ships the placeholder.

See the plugin's README for the by-hand recipe and for the
`FlutterFragmentActivity` requirement.

**Status:** the Dart side is complete and tested; the native side of
`elpian_godot` has not yet been compiled. iOS is not implemented — `Scene3D`
returns its placeholder there.
