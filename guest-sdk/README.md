# Guest SDK

The libraries a **mini app** is written against.

This is the public authoring surface of the platform: what someone building a
mini app imports, not what the runtime is built from. It used to live inside
`rust/prelude/` and `rust/dart/flutter/` — invisible in the repository layout,
and picked up by the Flutter analyzer as if it were host code, which produced
361 unfixable diagnostics and drowned out real findings.

None of it is Rust. It is compiled *by* the Rust front-ends (`js2elpian`,
`dart2elpian`) and embedded into them with `include_str!`, which is why it sat
there.

## Layout

```
js/     JavaScript preludes, compiled by js2elpian
  gui.js           the GUI SDK, entire. GD/GObj (the reflective Godot surface),
                   FL (the embedded Flutter engine), VUI (theme, typography,
                   metrics, imperative widgets), VReact (elements, hooks,
                   scheduler, reconciler), the widget registry, the component
                   model, Scene3D and Canvas. One import.
  net.js           HTTP, WebSocket and Socket.IO over Godot primitives
  caspar.js        the Caspar signed binary action protocol

dart/   Dart preludes, compiled by dart2elpian
  gui.dart         the GUI SDK for Dart, entire. GD/GObj (the reflective Godot
                   surface), the Flutter-shaped widget library, the unified
                   Color, Canvas + CanvasController, Scene3DController, the
                   theme tokens and the GUI namespace. One import.
  demo_app.dart    a worked example, exercised by tests/flutter_app.rs

docs/   Design notes for the larger preludes
```

## Entry points

An `import` line is a marker the composer resolves; there is no module system.
Every import, and what it composes ahead of the program:

| import | pulls | composed source |
| --- | --- | --- |
| `gui.js` | the SDK | 323 KB → 378 KB bytecode |
| `net.js` | the SDK + net | 339 KB |
| `caspar.js` | the SDK + caspar | 344 KB |

**`gui.js` is the door.** It was five files — `godot.js`, `flutter.js`,
`ui.js`, `react.js` and a `gui.js` layered over them — and a mini app imported
some combination. They are one file now and the other four are deleted: there
is no import chain to resolve, no question about which prelude a symbol comes
from, and no way for two layers to hold different ideas about the same widget.

`net.js` and `caspar.js` are clients, not alternatives. They reach the engine
through `GD`, so importing either composes the SDK beneath it — a networking
guest that never draws a widget still carries the reconciler. That is the price
of one self-contained file, and it is a real one: a prelude is compiled into
bytecode when the VM is created, and its top-level statements run before the
guest's first line, inside the same instruction budget the governor meters the
mini app against. `prelude_cost.rs` pins what that costs so it cannot grow
unnoticed.

## These files are not host code

They are written in the subset the Elpian front-ends compile, and they call VM
intrinsics — `askHost`, `__cbReg`, `__vmNotify` — that do not exist in the Dart
or JavaScript SDKs. Analysing them as ordinary Dart cannot succeed, so
`analysis_options.yaml` at the repository root excludes this directory. They are
checked by the front-end compilers' own test suites instead:

```bash
cd rust
cargo test -p dart2elpian     # dart/ preludes
cargo test -p js2elpian       # js/ preludes
cargo test -p dart            # the Flutter widget layer end to end
```

## gui.js and what it replaced

`gui.js` is the SDK a mini app imports. It was assembled from `godot.js`,
`flutter.js`, `ui.js` and `react.js`, which are gone — their contents are
sections §1–§4 of the file, with their own chapter documentation intact.

The merge exists because `ui.js` and `react.js` each kept their own list of
what widgets existed: VUI's imperative factories on one side, the reconciler's
driver tags on the other, with nothing holding the two sets in step. A widget
added to one was simply missing from the other. (Their *bodies* were never so
divided — the driver styles through `VUI.styleBox` and delegates several
widgets to the kit outright — which is why the fix is one list rather than one
implementation.)

In `gui.js` a widget is one registry entry and both surfaces are generated from
it: the declarative `Button({...})` and the imperative `GUI.button({...})`.
`widget_parity.rs` checks the two build the same node, per widget.

## gui.dart

The same move on the Dart side. It was two libraries that never met:
`godot.dart`, the engine transport building a *retained* Godot scene graph over
`godot.op`, and `flutter.dart`, a Flutter-shaped widget library with its own
two-phase layout painting *immediately* through `dart:ui`. Two rendering
models, two composers in two different Rust crates, and no program could use
both. They are one file now and the two are deleted.

The two backends stay two backends, because they genuinely render differently.
What they now share is a namespace, a value-type layer and a composer:

| | what it is | when to reach for it |
| --- | --- | --- |
| widget layer | `StatelessWidget`, `StatefulWidget`, `setState`, `runApp` | the default; ordinary Flutter, painted through `dart:ui` |
| engine layer | `GD.create`, `GObj`, `Scene3DController` | 3D, shaders, physics, or any Godot class at all |

`Color` is the one type the merge had to reconcile: the engine's was four
doubles matching Godot's, the widget layer's a packed `0xAARRGGBB` int matching
Flutter's, and both spellings are written all over existing guests. The merged
type answers to both — the unnamed constructor dispatches on arity, which is
unambiguous because the two forms never shared one:

```dart
Color(0xFF2196F3)             // Flutter: one packed ARGB int
Color(1.0, 0.5, 0.25, 1.0)    // Godot:   r, g, b, a
```

Two front-end defects surfaced during the merge and are fixed or pinned:
`dart2elpian` emitted a named constructor as a bare static that constructed
nothing and returned nothing (`named_constructors.rs`), and a getter silently
stops being called if *any* class in the program declares a field of that name
(`getter_shadowing.rs`) — which is exactly what merging two libraries causes.

### Class components

A class component is handed over explicitly:

```js
class Counter extends Component {
  constructor(props) { super(props); this.state = { n: 0 }; }
  render() { return Text({ children: "" + this.state.n }); }
}
const CounterC = GUI.component(Counter);
```

The wrap is not decoration. A class in this subset is not an object: its
statics resolve *by name at compile time*, so the moment it is passed as a
value there is nothing left to identify it by. `Type.prototype` is null, a
class object cannot be assigned to, and `instanceof` needs an instance that
cannot be constructed speculatively without running a function component's
hooks. `crates/js2elpian/tests/subset_features.rs` records all of it, and each
test there fails the day the front-end grows the feature — which is the signal
to simplify this away.

## Editing

The preludes are embedded at compile time with `include_str!`, so a change here
needs a Rust rebuild to take effect:

- `js/*` (including `gui.js`) and `dart/godot.dart` → `rust/crates/capi/src/lib.rs`
- `dart/flutter.dart` → `rust/dart/src/widgets.rs`
- `dart/demo_app.dart` → `rust/dart/tests/flutter_app.rs`
