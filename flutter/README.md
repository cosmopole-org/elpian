# elpian_ui — the Flutter host

The Flutter package that hosts Elpian mini apps: it turns the JSON node trees a
mini app emits (or a VM's `render` host calls, a stream, a Next.js server) into
Flutter widgets on Android, iOS, web, macOS, Linux and Windows.

It is one of two host modes. The other is the **native hosts** in
[`../native/`](../native/) — Kotlin / Android Views, Swift / UIKit, the DOM
(`@elpian/web`) and Expo — which run the same mini apps without Flutter. See
[`../wiki/23-native-hosts.md`](../wiki/23-native-hosts.md).

| Path | What |
|---|---|
| `lib/elpian_ui.dart` | Public barrel (`elpian_runtime.dart`, `elpian_governance.dart`, `elpian_godot.dart` are narrower entry points) |
| `lib/src/` | Engine, widget registry, CSS, events, DOM API, canvas, Godot `Scene3D`, scope, Next.js / fullstack adapters, VM clients |
| `rust_builder/` | The FFI plugin that builds and links `libelpian_vm` — see its [README](rust_builder/README.md) |
| `assets/web_runtime/` | The WASM VM loader and the QuickJS web runtime |
| `example/` | The demo app (`lib/examples/*.dart`) |
| `test/` | Widget, layout, CSS, VM and integration tests |

```yaml
dependencies:
  elpian_ui:
    path: ./path/to/elpian/flutter
```

```sh
flutter test                                   # from flutter/
cd example && flutter run -t lib/examples/landing_page_example.dart
```

Usage, examples and the full documentation: the [root README](../README.md)
and [`../wiki/`](../wiki/).
