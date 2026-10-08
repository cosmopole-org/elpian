# Elpian native hosts

Elpian mini apps — the HTML and Flutter widget sets, CSS, canvas, animations,
Godot `Scene3D`, and the Elpian VM / QuickJS / WASM runtimes — hosted by each
platform's own UI toolkit:

| Folder | What |
|---|---|
| `core/` | The TypeScript engine (web host only) |
| `web/` | `@elpian/web`: the DOM host, Canvas2D painter, Godot web, runtimes |
| `android/` | `elpian-core` (Kotlin engine, pure JVM) and `elpian` (Android Views host, engines) |
| `ios/` | `ElpianCore` (Swift engine) and `Elpian` (UIKit host, engines) |
| `expo/` | `@elpian/expo`: `<ElpianView>` for Expo / React Native |
| `assets/` | Fonts shared by every host |

Android and iOS run Kotlin and Swift ports of the engine — no JavaScript glue.
See [wiki/23-native-hosts.md](../wiki/23-native-hosts.md) for the architecture,
the session kinds, per-platform usage and the platform differences.

```sh
npm ci && npm test                         # core + web (Chromium)
(cd android && gradle :elpian-core:test :elpian:testDebugUnitTest)
(cd ios && swift test)
```
