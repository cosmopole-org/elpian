# 23 — Native hosts: Android, iOS, Web and Expo

Elpian mini apps were first hosted by Flutter (`flutter/`). `native/` hosts the
**same** mini apps, the same widget sets (the HTML elements and the Flutter
widgets), the same CSS, canvas, animations, Godot `Scene3D` and runtimes,
rendered with each platform's own UI toolkit:

| Platform | Engine (the "core") | Renders to | Runtimes |
|---|---|---|---|
| Android | Kotlin, `native/android/elpian-core` (pure JVM) | Android Views (`native/android/elpian`) | Elpian VM (Rust, JNI), QuickJS, WASM (Chicory), Godot |
| iOS | Swift, `native/ios/Sources/ElpianCore` | UIKit (`native/ios/Sources/Elpian`) | Elpian VM (Rust, C ABI), JavaScriptCore, WASM (WasmKit), Godot |
| Web | TypeScript, `native/core` | the DOM (`native/web`) | Elpian VM (wasm-bindgen), QuickJS (emscripten), WebAssembly, Godot web export |
| Expo / React Native | the three above | via `native/expo` | — |

Android and iOS do **not** use JavaScript as glue: their cores are Kotlin and
Swift ports of the TypeScript engine, file for file. JavaScript only runs
*inside* the sandboxes of JavaScript mini apps (QuickJS on Android,
JavaScriptCore on iOS), exactly as on Flutter.

## How a core works

All three cores are the same pipeline, a port of Flutter's:

1. **Lowering** — an Elpian node tree (`{type, props, style, children, events}`)
   from JSON, a VM's `render` host call, a stream or a Next.js server is turned
   into widget descriptors by the widget registry (`widgets/html`,
   `widgets/flutter`, `widgets/animation`, `widgets/nextjs`), after CSS
   cascade (`css/stylesheet`), inline styles and the CSS parser.
2. **Reconciling** — descriptors are matched to long-lived render objects by
   type and key (`render/reconciler`), so state (scroll offsets, animations,
   focus, text input) survives re-renders.
3. **Layout** — Flutter's box protocol: flex (with CSS shrink and baseline),
   wrap, stack/positioned, CSS grid, tables (colspan/rowspan, border-collapse),
   scroll views, intrinsic sizing, aspect ratio, fitted boxes, image maps.
4. **Compositing** — painting objects become platform views; the compositor
   diffs them into a minimal list of view operations (`create`, `update`,
   `move`, `remove`, `command`) over 17 primitive view kinds: `view`, `text`,
   `image`, `scroll`, `textInput`, `checkbox`, `radio`, `switch`, `slider`,
   `select`, `progress`, `canvas`, `scene3d`, `video`, `audio`, `web`,
   `native`.
5. **Rendering** — the platform host applies those operations with native
   views and reports events (`tap`, drags, scroll, input, …) back, which the
   core routes through the Elpian event system (capture/target/bubble) to the
   mini app.

The decoration model (backgrounds, Flutter-accurate gradients, images, per-side
borders, elliptical radii, box shadows with Flutter's blur sigma, clips,
transforms, opacity, CSS filters, backdrop filters, shader masks, blend modes)
and the canvas command set (paths, arcs, curves, text, images, gradients,
patterns, dashes, shadows, compositing, transforms, image data — see
[11 — Canvas and 3D](11-canvas-and-3d.md)) are implemented natively on each
platform: CSS + Canvas2D on the web, `android.graphics` on Android, Core
Animation + CoreGraphics on iOS.

## Sessions

Every host exposes the same session kinds through the core's
`SessionRegistry` (`bridge/sessions`):

| kind | what it hosts | main options |
|---|---|---|
| `json` | a static Elpian view tree | `view`, `stylesheet` |
| `miniapp` | a sandboxed mini app | `runtime` (`elpian`, `quickjs`, `wasm`), `code` / `astJson` / `bytecodeBase64`, `entryFunction`, `entryInput`, `stylesheet` |
| `superapp` | a governed mini app with a manifest and grants | `manifest`, `grant`, `source` |
| `stream` | NDJSON / SSE streamed UI | `url`, `method`, `headers`, `body` |
| `nextjs` | a Next.js server's Elpian payloads | `serverBaseUrl`, `route`, auth options |
| `server` | Elpian server components with islands | `baseUrl`, `component`, `args` |

Session methods (`navigate`, `back`, `refresh`, `callFunction`, `push`,
`patch`, `usage`, `state`, `pause`, `resume`, `terminate`, …) and events
(`ready`, `error`, `println`, `updateApp`, `routeChanged`, `result`, …) have
the same names on every platform.

## Android

```kotlin
// build.gradle: implementation("dev.elpian:elpian-android:1.0.0")
//               coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
Elpian.install(applicationContext)          // once, on the main thread

val view = ElpianHostView(context)          // a FrameLayout
setContentView(view)
view.on("println") { Log.i("app", it.toString()) }
view.open("miniapp", mapOf(
    "runtime" to "quickjs",
    "code" to jsSource,
    "entryFunction" to "main",
))
lifecycleScope.launch { val usage = view.call("usage") }
```

* `native/android/scripts/build-rust.sh` builds `libelpian_vm.so` (the Elpian
  VM with its JNI exports, `elpian-ffi --features jni`) for every ABI; without
  it the `elpian` runtime reports itself unavailable.
* Godot is opt-in (`-Pelpian.godot=true`, see `godot/README.md`).
* `gradle publish` writes `dev.elpian:elpian-core` / `elpian-android` to
  `native/android/build/repo` (or `-Pelpian.repo=<dir>`).
* Tests: `gradle :elpian-core:test` (the core on the JVM, with layout numbers
  checked against the TypeScript engine) and `gradle :elpian:testDebugUnitTest`
  (Robolectric: sessions rendered into real Views end to end).

## iOS

```swift
// Swift Package: native/ios, product "Elpian"
_ = Elpian.install()                        // once, on the main thread

let view = ElpianHostView(frame: .zero)     // a UIView
view.on("println") { print($0 ?? "") }
view.open(kind: "miniapp", options: ["runtime": "quickjs", "code": jsSource, "entryFunction": "main"])
let usage = try await view.call("usage")
```

* `native/ios/scripts/build-rust.sh` builds `ElpianVM.xcframework` (the Elpian
  VM's C ABI, `rust/crates/elpian-ffi/include/elpian_vm.h`).
* `ElpianCore` is pure Swift + Foundation and is tested on Linux and macOS
  (`swift test`); the UIKit host compiles for iOS only.

## Web

```js
import { installElpian, mountElpian } from '@elpian/web';
installElpian({ assetBase: '/node_modules/@elpian/web/assets/' });
const app = await mountElpian(document.getElementById('app'), 'miniapp', { runtime: 'quickjs', code, entryFunction: 'main' });
app.on('println', console.log);
```

or declaratively: `<elpian-view kind="nextjs" options='{"serverBaseUrl":"…","route":"/"}'></elpian-view>`.
Every session event is also dispatched on the element as `elpian:<event>` and
as `elpian:event` (`{event, payload}`).

## Expo / React Native

```tsx
// app.json: { "expo": { "plugins": ["@elpian/expo"] } }
import { ElpianView, type ElpianViewHandle } from '@elpian/expo';

const ref = useRef<ElpianViewHandle>(null);
<ElpianView
  ref={ref}
  style={{ flex: 1 }}
  kind="miniapp"
  options={{ runtime: 'elpian', astJson, entryFunction: 'main' }}
  onEvent={({ event, payload }) => console.log(event, payload)}
/>;
await ref.current?.call('callFunction', 'onTap', '{}');
```

`ElpianView` is the native `ElpianHostView` on Android and iOS and the DOM host
on web. On Expo web, run `npx elpian-expo-web-assets` once to copy the
web host's fonts and runtime files into `public/elpian` (or call
`configureElpianWeb({ assetBase })` to serve them from elsewhere); plain JSON
views render without them. The config plugin adds the package's Maven repository and core library
desugaring to the Android app; `npm run prepare-native` (run on `prepack`)
stages the Android libraries and the iOS sources into the package.

## Differences between platforms

The cores are ports of one engine and are tested against it, so layout and
semantics match. What differs is what the platform toolkit can draw:

* **Android** — CSS `filter: blur()` and drop-shadow filters need API 31+;
  `backdrop-filter` is a software blur of a reduced-resolution snapshot;
  word spacing needs API 29+ and font weights other than regular/bold API 28+.
* **QuickJS on Android** — a mini app whose completion value is `null` reads
  as `undefined` (a limitation of the binding).
* **Godot** — signals from Godot back to the host have no sender on the Godot
  side yet (as on Flutter); `AndroidGodotBinding.deliverSignal` is ready for it.
