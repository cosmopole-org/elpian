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
  godot.js         GD / GObj / G3 — the reflective Godot surface, plus VMs
  ui.js            widget toolkit over Godot Control nodes
  react.js         React-compatible runtime targeting the UI kit
  reactnative.js   React Native / Expo widget trees + embedded Scene3D
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

## Editing

The preludes are embedded at compile time with `include_str!`, so a change here
needs a Rust rebuild to take effect:

- `js/*` and `dart/godot.dart` → `rust/capi/src/lib.rs`
- `dart/flutter.dart` → `rust/dart/src/widgets.rs`
- `dart/demo_app.dart` → `rust/dart/tests/flutter_app.rs`
