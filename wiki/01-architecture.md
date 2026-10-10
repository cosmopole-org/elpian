# 01 — Architecture

## The core idea

Elpian exists to **ship application logic as data**. A program is compiled to
bytecode at build time, delivered like an asset (over HTTP, from disk, embedded
in a binary), and executed by an interpreter that never generates machine code.

Three consequences follow, and they explain almost every design decision in the
system:

1. **It is legal on iOS.** Apple forbids downloading and executing new
   *native* code. An interpreter walking a bytecode array is not native code
   generation, so an Elpian app can update its own logic without an App Store
   round-trip.
2. **It runs on the web.** The same VM compiles to WASM (`wasm-bindgen`), so a
   program built once runs natively and in a browser with identical semantics.
3. **It is sandboxable by construction.** The guest has exactly one way to
   affect the world — `askHost(name, payload)` — so capability gating and
   resource metering need to be enforced at exactly one seam. See
   [`03-governance.md`](03-governance.md).

## The layers

```
┌───────────────────────────────────────────────────────────────────────┐
│  L5  Application code — TypeScript / JavaScript / Dart subset         │
│      src/client.ts, src/server.ts, packages/*                         │
├───────────────────────────────────────────────────────────────────────┤
│  L4  Toolchain (Rust, build time)                                     │
│      oxc: parse TS → strip types → JS                                 │
│      cli: resolve imports, bundle modules into one source            │
│      js2elpian: JS → Elpian AST JSON → bytecode (.elpian.bc)          │
├───────────────────────────────────────────────────────────────────────┤
│  L3  Elpian VM (Rust) — rust/crates/elpian-vm/src/sdk/                                 │
│      program.rs   decode bytecode once into an addressable op list    │
│      executor.rs  the pausing interpreter (6.5k lines)                │
│      stdlib/      ~200 universal builtins (math, string, list, map)   │
│      limits/capabilities/hierarchy/lifecycle — governance             │
├───────────────────────────────────────────────────────────────────────┤
│  L2  Embedding surface                                                │
│      elpian-ffi    native (Android, iOS, macOS, Linux, Windows)       │
│      elpian-wasm   web (wasm-bindgen)                                 │
│      elpian-host (elpiand)  the server that runs server-function VMs  │
├───────────────────────────────────────────────────────────────────────┤
│  L1  Hosts — one of two modes, same node format and host-call API     │
│   Flutter host — elpian_ui (flutter/lib/)                             │
│      ElpianVmWidget  owns a VM instance, pumps host calls             │
│      ElpianEngine    JSON UI tree → Flutter widgets (161 tags)        │
│      CSS engine      201 style properties, stylesheets, media queries │
│      EventDispatcher 40+ event types → back into the VM               │
│      Canvas2D / Scene3D      — drawing and embedded Godot 3D          │
│   Native hosts — native/ (Kotlin, Swift, TypeScript ports of one      │
│      engine): lowering → reconcile → layout → compositor → platform   │
│      views (Android Views, UIKit, the DOM; Expo over all three)       │
└───────────────────────────────────────────────────────────────────────┘
```

The two host modes are interchangeable from the guest's point of view: both
lower the same JSON nodes (HTML and Flutter widget sets), apply the same CSS,
answer the same `askHost` catalog and run the same runtimes. The native hosts
are described in [`23-native-hosts.md`](23-native-hosts.md).

### Why the split matters (for writing correct code)

The **VM knows nothing about UI**. It has no widget concept, no CSS, no DOM. All
of that lives in the host (Flutter or native). The guest's only UI power is: build a JSON
tree and hand it to `askHost("render", json)`. If a widget prop does not appear
in that JSON, the host cannot know about it.

The **host knows nothing about your language**. It never sees TypeScript. By the
time anything runs, your code is bytecode. So a TS feature that the compiler
cannot lower (see [`04-languages.md`](04-languages.md)) does not "degrade" — it
fails the build with `JavaScript is outside the Elpian subset`.

## Execution model: pausing + `askHost`

The VM is a **coroutine**. `askHost(apiName, payload)` *suspends* it, hands the
request to the embedder, and *resumes* it with the reply.

```
guest              VM (Rust)                       host (Flutter / native / server)
  │                    │                                   │
  │ askHost("render",…)│                                   │
  ├───────────────────▶│  set reserved_host_call           │
  │                    │  return VmExecResult {            │
  │                    │    has_host_call: true,           │
  │                    │    host_call_data: "{…}"          │
  │                    ├──────────────────────────────────▶│ parse, act
  │                    │                                   │ (build widgets)
  │                    │◀──────────────────────────────────┤ continue_execution(
  │◀───────────────────┤  resume with typed value          │   machineId, reply)
  │ (askHost returns)  │                                   │
```

**Internalize this: a host call is a suspension point.** Events and callbacks
are delivered as *separate resumed turns*, not synchronously inside the call that
triggered them. A click does not "return into" the render that drew the button;
it is a fresh `execute_vm_func_with_input(machineId, "increment", eventJson)`.

Guest-side state therefore lives in **module-level variables** that persist
across turns for the lifetime of the VM instance. That is why the counter
template works:

```ts
let count: number = 0;                       // lives in the VM instance
function increment() { count = count + 1; render(view()); }
```

...and why **server** functions must not rely on module-level state unless
the host keeps their instance warm: `elpiand` (`rust/crates/elpian-host`) may
give a function a fresh instance per call (see
[`19-server-functions.md`](19-server-functions.md)).

## Repo map (what lives where)

```
elpian/
├── flutter/                   the Flutter host package (`elpian_ui`)
│   ├── lib/
│   │   ├── elpian_ui.dart     public barrel — everything exported
│   │   └── src/
│   │       ├── vm/            VM integration: widget, runtimes, host handlers
│   │       │   ├── elpian_vm_widget.dart   the main embedding widget
│   │       │   ├── elpian_vm.dart          native FFI client
│   │       │   ├── wasm_vm.dart            web/WASM client
│   │       │   ├── quickjs_vm*.dart        alternative QuickJS runtime
│   │       │   ├── host_handler.dart       core host-call handling
│   │       │   ├── host_api_catalog.dart   the API-name allowlist (generated)
│   │       │   ├── governance/             host-side governor
│   │       │   └── ffi/                    VM bindings (native + web)
│   │       ├── core/          engine, widget registry, events, DOM, resources
│   │       ├── models/        ElpianNode, CSSStyle
│   │       ├── css/           parser, properties, stylesheet, JSON stylesheets
│   │       ├── widgets/       60+ Flutter widget builders
│   │       ├── html_widgets/  70+ HTML tag builders
│   │       ├── canvas/        2D canvas API + widget
│   │       ├── godot/         embedded Godot 3D: Scene3D, controller, ops
│   │       ├── scope/         re-render boundaries: the contract, patch, helpers
│   │       ├── integrations/  Next.js bridge + server widget
│   │       ├── fullstack/     server components and the fullstack client
│   │       ├── superapp/      governed mini apps (manifest + grants)
│   │       ├── parser/        JSON → node parsing
│   │       ├── stream/        streaming widget
│   │       └── diagnostics/   diagnostics helpers
│   ├── rust_builder/          Flutter FFI plugin: builds/links libelpian_vm
│   ├── example/               a full Flutter example app
│   └── test/                  widget/layout/VM tests (executable specs)
├── native/                    the native hosts of the same mini apps
│   ├── web/                   @elpian/web: the engine in TypeScript (src/)
│   │                          + its DOM host (src/dom/)
│   ├── android/               elpian-core (Kotlin engine) + elpian (Views host)
│   ├── ios/                   ElpianCore (Swift engine) + Elpian (UIKit host)
│   ├── expo/                  @elpian/expo: <ElpianView> for Expo / React Native
│   └── assets/                fonts shared by every native host
├── rust/                      Cargo workspace; every crate under crates/
│   └── crates/
│       ├── elpian-vm/         the VM: src/sdk/ (executor, compiler, program,
│       │                      stdlib, governance), src/api.rs (public API)
│       ├── elpian-ffi/        C ABI (+ JNI) — libelpian_vm for Flutter,
│       │                      Android and iOS
│       ├── elpian-wasm/       the wasm-bindgen browser VM
│       ├── js2elpian/         JS → Elpian AST → bytecode
│       ├── dart2elpian/       Dart subset → JS subset
│       ├── elpian-dart-runtime/  dart:* host surface + Flutter widget layer
│       ├── elpian-runtime/    host-neutral multi-VM manager
│       ├── elpian-host/       the server host (`elpiand`): server functions,
│       │                      policy, pool, registry
│       ├── elpian-pkg/        `.elpianpkg` packaging
│       ├── elpian-crypto/     signing / hashing helpers
│       └── capi/              elpian-godot-capi, linked by the GDExtension
├── guest-sdk/                 the libraries guests are written against
├── godot/                     the embedded Godot engine (Flutter plugin; its
│   │                          engine-side sources are reused by native/android)
│   ├── android/               Kotlin — platform view, op queue, Godot fragment
│   ├── ios/                   Swift — platform view, op queue, runtime seam
│   ├── web/                   the Godot web-export glue
│   └── godot-project/         runs inside Godot: OpSink.gd + the GDExtension
├── cli/                       the `elpian` CLI — its own crate, inside this repo
│   ├── rust/main.rs           the entire CLI in one file
│   ├── elpian_client/         the Flutter web shell it serves (renderer
│   │                          `flutter`; `native` uses native/web instead)
│   └── README.md
├── samples/                   sample mini apps
├── fullstack/                 the fullstack design plan and status
├── bench/                     performance harnesses + reports
├── scripts/                   e2e / smoke / doc-snippet checks
└── wiki/                      this documentation
```

> **Note on the CLI's location.** The CLI is a *separate crate* that happens to
> live in this repository, not part of the `elpian_ui` package. Its
> `elpian_client` web shell depends on `elpian_ui` by relative path
> (`path: ../../flutter`), and its `Cargo.toml` resolves `js2elpian` at
> `../rust/crates/js2elpian`. With the `native` renderer it builds
> `native/web` with npm. Everything it needs is in this repository — **no
> sibling checkout is required.**

## The three delivery stories (choose deliberately)

| Story | Where the VM runs | What you get | Use it when |
|---|---|---|---|
| **Client** | In the browser (WASM), in a Flutter app, or in a native host | A UI-producing VM whose `render` output becomes Flutter widgets or native views | Interactive apps, dynamic UIs, hot-updatable screens |
| **Server** | In `elpiand` (native Rust) | `POST /__elpian/api/<fn>` with a JSON body → JSON result | Pure functions, computed responses, untrusted user logic |
| **Fullstack** | Both, from one project | A client VM in the page plus a server VM behind the same origin | Apps that need both a UI and server logic |

These map exactly to the CLI's `--template client|server|fullstack`; see
[`06-templates.md`](06-templates.md).

## Runtimes, one semantics

On the Flutter host, `ElpianRuntime` (`flutter/lib/src/vm/runtime_kind.dart`)
selects the execution backend:

```dart
enum ElpianRuntime { elpian, quickJs, wasm }
```

- `elpian` — the native Rust VM through FFI. Used on Android/iOS/desktop.
- `wasm` — the same Rust VM compiled to WASM. Used on the web.
- `quickJs` — an alternative QuickJS-based runtime (a real JS engine), for
  programs that need JS semantics beyond the Elpian subset. It is *not* the
  bytecode path, and it does not get the VM's governance.

`ElpianVmWidget` picks a runtime and falls back across the three
(`_vm ?? _quickJsVm ?? _wasmVm`) when routing calls.

The native hosts take the same choice as the `runtime` option of a `miniapp`
session (`elpian`, `quickjs`, `wasm`): the Elpian VM over JNI (Android), the C
ABI (iOS) or wasm-bindgen (web); QuickJS on Android and the web,
JavaScriptCore on iOS; and a WebAssembly engine (Chicory, WasmKit, the
browser's). See [`23-native-hosts.md`](23-native-hosts.md).

## Where to go next

- The VM's actual semantics: [`02-elpian-vm.md`](02-elpian-vm.md)
- Sandboxing and multi-VM: [`03-governance.md`](03-governance.md)
- What your source language may contain: [`04-languages.md`](04-languages.md)
- Getting a project running: [`05-cli.md`](05-cli.md)
- Hosting natively (Android, iOS, web, Expo): [`23-native-hosts.md`](23-native-hosts.md)
