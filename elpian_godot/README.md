# elpian_godot

The embedded **Godot 4** engine behind Elpian's `Scene3D` widget.

`elpian_ui` ships the whole Dart API — the `Scene3D` widget, `GodotSceneController`,
the op protocol and the scene DSL — and degrades to a placeholder when no engine
is present. Adding *this* package to an app supplies the engine.

It is a separate package on purpose: the Godot library AAR is ~21 MB, and an app
with no 3D should not pay for it.

## Architecture

```
Flutter (Dart)                    │ this package (Kotlin)      │ Godot 4
────────────────────────────────  │ ────────────────────────── │ ─────────────────
GodotController                   │                            │
  ├ allocates handles             │                            │
  ├ batches ops per frame         │                            │
  └ MethodChannel elpian/godot/ops├─▶ OpQueue (synchronized)   │
                                  │        ▲            │      │
Scene3D widget                    │        │            └─────▶│ ElpianGodotBridge
  └ AndroidView elpian/godot/…    ├─▶ GodotSurfaceView         │   .pollOps()  ← per frame
                                  │     └ ElpianGodotFragment ─┼─▶ OpSink.gd
EventChannel elpian/godot/events  │◀── SignalRelay ────────────┤   └ ElpianScene3D
  └ signal callbacks              │                            │      .exec_op_json()
                                  │                            │      (reflective, ClassDB)
```

The **op vocabulary is identical** to the one Victor's React Native host and the
C++ `GodotController` already speak, so the engine-side interpreter — the
`elpian_godot` GDExtension — is reused **verbatim**. Only the transport differs.

### What changed from Victor's React Native port

| | React Native | Flutter (here) |
|---|---|---|
| Transport | JSI (`globalThis.__ElpianGodot`) | `MethodChannel` |
| Op queue | C++ + JNI (`ElpianGodotJsi.cpp`, 188 lines) | Kotlin `OpQueue` |
| View | `ExpoView` | `PlatformView` |
| Signals | JSI callback | `EventChannel` |
| iOS queue | shared C++ | Swift `GodotOpQueue` |
| Engine side | `OpSink.gd` + GDExtension | **unchanged**, plus batch/reply shapes |

Dropping JSI removes the C++ layer and its ABI entirely — a method channel
already lands on the platform thread, which is all the queue needs.

## Build steps (not automated here)

Three artifacts are **not** checked in:

1. **The Godot library AAR** → `android/libs/godot-lib.template_release.aar`
   Take the one from `victor/react-native/modules/elpian-godot/android/libs/`, or
   build it from a Godot 4 source checkout
   (`scons platform=android target=template_release`, then `./gradlew generateGodotTemplates`).

2. **The `elpian_godot` GDExtension** — the reflective `ElpianScene3D` op
   interpreter. Built from Victor's `bridge/extension`; drop the resulting
   `.so` files beside `godot-project/elpian_godot.gdextension`.

3. **The packed op-sink project** → `android/src/main/assets/godot/embed.pck`
   Open `godot-project/` in the Godot 4 editor and export with the preset in
   `export_presets.cfg`, or headless:
   ```sh
   godot --headless --path godot-project --export-pack "Android" \
         ../android/src/main/assets/godot/embed.pck
   ```

### Host app requirement

The Godot fragment needs a `FragmentActivity`, so the app's `MainActivity` must
extend `FlutterFragmentActivity` rather than `FlutterActivity`:

```kotlin
class MainActivity : FlutterFragmentActivity()
```

Without it the plugin logs a warning and `Scene3D` shows its placeholder — it
does not crash.

## iOS

Implemented — see [`ios/README.md`](ios/README.md). Same channels, same op
protocol, same degradation. The one structural difference:

* **Android pulls** — the embedded engine owns its render thread, so `OpSink.gd`
  calls `pollOps()` each frame.
* **iOS pushes** — the runtime is driven from the host run loop, so a
  `CADisplayLink` drains the queue into `GodotRuntimeHost.opSink`.

`GodotRuntimeHost` is plain function hooks, so this package takes no build
dependency on the Godot runtime: an app without it still compiles and runs, with
`Scene3D` showing its placeholder.

## Status

The Dart side is complete and tested (28 tests). **The native side in this
package has not been compiled or run** — it was written without an Android SDK,
NDK, Godot editor, Xcode or macOS host available. Treat the Kotlin, the Swift and
the `.gd` changes as a reviewed port that still needs its first build.
