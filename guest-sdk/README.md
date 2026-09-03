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
  gui.js           the GUI SDK — state, rendering, scoping, widgets, styling,
                   Scene3D and Canvas in one import. Start here.
  godot.js         GD / GObj / G3 — the reflective Godot surface, plus VMs
  ui.js            VUI, the imperative widget toolkit (superseded by gui.js)
  react.js         the React-compatible runtime (superseded by gui.js)
  flutter.js       FL — drives an embedded Flutter engine over flutter.op
  net.js           HTTP, WebSocket and Socket.IO over Godot primitives
  caspar.js        the Caspar signed binary action protocol

dart/   Dart preludes, compiled by dart2elpian
  flutter.dart     a Flutter-shaped widget library in the compiled subset
  godot.dart       the Dart twin of godot.js
  demo_app.dart    a worked example, exercised by dart/tests/flutter_app.rs

docs/   Design notes for the larger preludes
```

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

`gui.js` is the SDK a mini app should import. It sits on top of `godot.js`,
`flutter.js`, `ui.js` and `react.js` — importing it pulls the whole chain, so a
guest writes one import line and gets one vocabulary, while each layer stays
its own file with its own tests.

It exists because `ui.js` and `react.js` each kept their own list of what
widgets existed: VUI's imperative factories on one side, the reconciler's
driver tags on the other, with nothing holding the two sets in step. A widget
added to one was simply missing from the other. (Their *bodies* were never so
divided — the driver styles through `VUI.styleBox` and delegates several
widgets to the kit outright — which is why the fix is one list rather than one
implementation.)

In `gui.js` a widget is one registry entry and both surfaces are generated from
it: the declarative `Button({...})` and the imperative `GUI.button({...})`.
`widget_parity.rs` checks the two build the same node, per widget.

`ui.js` and `react.js` remain importable on their own. New code should use
`gui.js`.

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
