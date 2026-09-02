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

## The three binary artifacts

They are **not** checked in — they are large, reproducible from pinned upstream
versions, and `.gitignore`d so a local build cannot commit them by accident.

**CI builds them for you:** `.github/workflows/build_godot_artifacts.yml`
produces all three as one bundle, which `build_showcase.yml` restores. That
workflow runs on its own cadence — a Godot bump or an interpreter change — not
on every push, because rebuilding them each time would add ~15 minutes for
nothing.

That workflow produces **two** bundles — `godot-artifacts-android` (the three
artifacts below) and `godot-artifacts-web` (an HTML5 export of the same op-sink
project) — and `build_showcase.yml` restores whichever its job needs.

When a bundle is absent, the build still succeeds and ships the placeholder.
That is deliberate: it is what any un-provisioned build gets, so CI keeps
proving the degradation path works.

To build them by hand:

1. **The Godot library AAR** → `android/libs/godot-lib.template_release.aar`
   **Do not build the engine from source.** It is an unmodified upstream
   release; a source build takes ~an hour to reproduce a binary Godot already
   publishes. The Android library ships inside the official export templates as
   `android_source.zip` — unzip it and run `./gradlew :lib:assembleTemplateRelease`.
   (Victor's checked-in copy under
   `victor/react-native/modules/elpian-godot/android/libs/` is the same artifact.)

2. **The `elpian_godot` GDExtension** → `godot-project/bin/`
   The reflective `ElpianScene3D` op interpreter, built from Victor's
   `bridge/extension`:

   ```sh
   scons platform=android target=template_release arch=arm64 \
     elpian_capi=../../target/aarch64-linux-android/release/libelpian_godot.a
   scons platform=linux target=template_release   # ← also required, see below
   ```

   Two traps:

   * `SConstruct` globs every `src/*.cpp`, including the ElpianVM node, so the
     Rust C-ABI static library (`cargo build -p elpian-godot-capi`) is needed
     even though Elpian only uses the `ElpianScene3D` half — `OpSink.gd` runs
     the op interpreter with no VM, because the single VM lives in the Flutter
     app.
   * **A host-platform build is required too.** The headless editor loads the
     `.gdextension` during import and export, so `linux.x86_64` must exist or
     the export aborts with what looks like a project error.

   `elpian_godot.gdextension` declares six library slots (four Android ABIs,
   linux, web). Build what you ship or trim the file — a missing slot for a
   platform you target fails at runtime, not at build time.

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

## Web

Implemented. Same op protocol, same degradation, a different transport again:
there is no plugin singleton to call back through, so all three directions meet
on `window`.

```
Flutter (Dart)                     │ the page                    │ Godot 4 (wasm)
─────────────────────────────────  │ ─────────────────────────── │ ────────────────
WebGodotBinding                    │                             │
  ├ push JSON per message          ├─▶ __elpianGodotQueue        │
  │                                │      └ __elpianGodotDrain() ├─▶ OpSink.gd
  └ poll for replies               │◀── __elpianGodotReplies ────┤   (JavaScriptBridge)
Scene3D widget                     │      ▲ __elpianGodotReply() │
  └ HtmlElementView ───────────────├─▶ __elpianGodotSurface(id)  │
                                   │      └ <canvas> ────────────┼─▶ the engine's
                                   │                             │   render target
```

Three pieces, all required:

1. **The export** — `build_godot_artifacts.yml`'s `web` job, which needs the
   GDExtension compiled to wasm32 and the *extensions-support* export template.
2. **The glue** — [`web/elpian_godot_web.js`](web/elpian_godot_web.js), loaded
   by a `<script>` in `<head>`. It installs the hooks synchronously at parse and
   boots the engine on the first surface request, into the canvas Flutter put in
   the platform-view slot.
3. **The binding** — resolved automatically by the conditional import in
   `lib/src/godot/godot_binding.dart`; nothing has to be installed by hand.

Presence of `window.__elpianGodotDrain` *is* the liveness signal that makes
`Scene3D` swap its placeholder for a viewport, so the glue is only shipped when
there is an engine for it to boot — and it removes the hook again if the engine
fails to start.

Two limits worth knowing:

* **One `Scene3D` per page.** A Godot web export drives a single canvas; a
  second surface gets an empty element and a console warning.
* **`isLive` is read at build time.** The glue is loaded before Flutter boots,
  so this is a non-issue in practice, but an engine that arrives *after* the
  first `Scene3D` builds will not light it up until something else rebuilds it.

The Dart↔page contract is covered by `test/godot_web_transport_test.dart`, which
runs in a real browser with no engine present and is executed by CI.

## Status

The Dart side is complete and tested (28 tests). **The native side in this
package has not been compiled or run** — it was written without an Android SDK,
NDK, Godot editor, Xcode or macOS host available. Treat the Kotlin, the Swift and
the `.gd` changes as a reviewed port that still needs its first build.
