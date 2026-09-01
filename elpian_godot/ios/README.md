# elpian_godot — iOS

The iOS twin of the Android module. Same channels, same op protocol, same
graceful degradation; only the drain direction differs.

## Files

| File | Role |
|---|---|
| `Classes/ElpianGodotPlugin.swift` | Method channel, event channel, view factory |
| `Classes/GodotOpQueue.swift` | The thread-safe op queue (Swift twin of `OpQueue.kt`) |
| `Classes/GodotSurfaceView.swift` | The platform view + `CADisplayLink` drain, and `GodotRuntimeHost` |
| `elpian_godot.podspec` | Pod definition |

## Android pulls, iOS pushes — and why

On Android the embedded engine owns its own render thread, so `OpSink.gd` *pulls*
each frame through `ElpianGodotBridge.pollOps()`. On iOS the runtime is driven
from the host's run loop, so a `CADisplayLink` drains the queue and *pushes* each
batch into `GodotRuntimeHost.opSink`.

The **protocol is identical** either way — the same message envelopes, the same
handle allocation, the same reply slots. Only who calls whom differs.

## Linking a runtime

`GodotRuntimeHost` is the seam. A host app (or a future runtime pod) sets:

```swift
GodotRuntimeHost.attach  = { view, surfaceId in /* render into `view` */ }
GodotRuntimeHost.opSink  = { batchJson in /* exec_op_json on each op */ }
GodotRuntimeHost.release = { surfaceId in /* tear down the viewport */ }
GodotRuntimeHost.onSignal = { cbId, argsJson in /* a signal fired */ }
// and calls GodotRuntimeHost.reply(requestId, payload) for awaited batches
```

It is deliberately plain function hooks rather than a protocol so this package
takes **no build dependency** on the runtime: an app without it still compiles,
links and runs, with `Scene3D` showing its placeholder.

## The two binary artifacts

1. **`libgodot.ios`** — Godot 4 built as an embeddable iOS library:
   ```sh
   scons platform=ios target=template_release library_type=static_library arch=arm64
   ```
   The counterpart of `android/libs/godot-lib.template_release.aar`.

2. **The `elpian_godot` GDExtension for iOS** — the reflective `ElpianScene3D`
   op interpreter (from Victor's `bridge/extension`) built for `arm64` iOS.

Drop both into the host app's Xcode project and wire `GodotRuntimeHost`.

## Status

**Not compiled.** Written without Xcode, an iOS SDK or a macOS host available.
The Swift is a reviewed port that still needs its first build.
