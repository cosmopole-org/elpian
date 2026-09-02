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
│      api/ffi.rs    native (Android, iOS, macOS, Linux, Windows)       │
│      api/wasm.rs   web (wasm-bindgen)                                 │
│      bin/elpian-server.rs  HTTP server that runs server-side VMs      │
├───────────────────────────────────────────────────────────────────────┤
│  L1  Flutter host — elpian_ui (lib/)                                  │
│      ElpianVmWidget  owns a VM instance, pumps host calls             │
│      ElpianEngine    JSON UI tree → Flutter widgets (161 tags)        │
│      CSS engine      201 style properties, stylesheets, media queries │
│      EventDispatcher 40+ event types → back into the VM               │
│      Canvas2D / Scene3D      — drawing and embedded Godot 3D          │
└───────────────────────────────────────────────────────────────────────┘
```

### Why the split matters (for writing correct code)

The **VM knows nothing about UI**. It has no widget concept, no CSS, no DOM. All
of that lives in the Flutter host. The guest's only UI power is: build a JSON
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
guest              VM (Rust)                       host (Flutter / server)
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

...and why the **server** template's functions must be self-contained: the HTTP
server creates a fresh VM per request and destroys it afterwards
(`rust/crates/elpian-vm/src/bin/elpian-server.rs`), so nothing carries over between requests.

## Repo map (what lives where)

```
elpian/                        the Flutter host package (`elpian_ui`) + the VM
├── lib/
│   ├── elpian_ui.dart         public barrel — everything exported
│   └── src/
│       ├── vm/                VM integration: widget, runtimes, host handlers
│       │   ├── elpian_vm_widget.dart   the main embedding widget (823 lines)
│       │   ├── elpian_vm.dart          native FFI client
│       │   ├── wasm_vm.dart            web/WASM client
│       │   ├── quickjs_vm*.dart        alternative QuickJS runtime
│       │   ├── host_handler.dart       core host-call handling
│       │   ├── host_api_catalog.dart   the API-name allowlist (107 names)
│       │   ├── scoped_components.dart  per-component re-render boundaries
│       │   └── frb_generated/          flutter_rust_bridge bindings
│       ├── core/              engine, widget registry, events, DOM, resources
│       ├── models/            ElpianNode, CSSStyle
│       ├── css/               parser, properties, stylesheet, JSON stylesheets
│       ├── widgets/           60+ Flutter widget builders
│       ├── html_widgets/      70+ HTML tag builders
│       ├── canvas/            2D canvas API + widget
│       ├── godot/             embedded Godot 3D: Scene3D, controller, ops
│       ├── scope/             re-render boundaries: the contract, patch, helpers
│       ├── integrations/      Next.js bridge + server widget
│       ├── parser/            JSON → node parsing
│       ├── stream/            streaming widget
│       └── diagnostics/       diagnostics helpers
├── rust/                      the Elpian VM (`elpian-vm`) + a Cargo workspace
│   ├── js2elpian/             JS → Elpian AST → bytecode
│   ├── dart2elpian/           Dart subset → JS subset
│   ├── dart/                  Dart/Flutter runtime extras
│   ├── capi/                  elpian-godot-capi, linked by the GDExtension
│   ├── prelude/               guest preludes (godot.js, ui.js, net.js, …)
│   ├── src/sdk/               executor, compiler, program, stdlib, governance
│   ├── src/api.rs             the public VM API (create/execute/govern)
│   ├── src/api/{ffi,wasm}.rs  native and web embedding surfaces
│   └── src/bin/elpian-server.rs  the HTTP server VM
├── rust_builder/              Flutter plugin: the native VM library
├── godot/                     Flutter plugin: the embedded Godot engine
│   ├── android/               Kotlin — platform view, op queue, Godot fragment
│   ├── ios/                   Swift — platform view, op queue, runtime seam
│   └── godot-project/         runs inside Godot: OpSink.gd + the GDExtension
├── cli/                       the `elpian` CLI — its own crate, inside this repo
│   ├── rust/main.rs           the entire CLI in one file
│   ├── elpian_client/         the standalone Flutter web shell it serves
│   └── README.md
├── example/                   a full Flutter example app
├── test/                      60+ widget/layout/VM tests (executable specs)
├── bench/                     performance harnesses + reports
├── wiki/                      this documentation
└── *.md                       deep reference docs (VM_LOGIC.md is the big one)

victor/                        a sibling project — only the GDExtension C++
                               source (bridge/extension) is still needed, and
                               only to build the Godot binaries.
```

> **Note on the CLI's location.** The CLI is a *separate crate* that happens to
> live in this repository, not part of the `elpian_ui` package. Its
> `elpian_client` web shell depends on `elpian_ui` by relative path
> (`path: ../..`), and its `Cargo.toml` resolves `js2elpian` at
> `../rust/crates/js2elpian`. Everything it needs is in this repository — **no sibling
> checkout is required.**

## The three delivery stories (choose deliberately)

| Story | Where the VM runs | What you get | Use it when |
|---|---|---|---|
| **Client** | In the browser (WASM) or in a native Flutter app | A UI-producing VM whose `render` output becomes Flutter widgets | Interactive apps, dynamic UIs, hot-updatable screens |
| **Server** | In `elpian-server` (native Rust), one fresh VM per HTTP request | `POST /__elpian/api/<fn>` with a JSON body → JSON result | Pure functions, computed responses, untrusted user logic |
| **Fullstack** | Both, from one project | A client VM in the page plus a server VM behind the same origin | Apps that need both a UI and server logic |

These map exactly to the CLI's `--template client|server|fullstack`; see
[`06-templates.md`](06-templates.md).

## Two runtimes, one semantics

`ElpianRuntime` (`lib/src/vm/runtime_kind.dart`) selects the execution backend:

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

## Where to go next

- The VM's actual semantics: [`02-elpian-vm.md`](02-elpian-vm.md)
- Sandboxing and multi-VM: [`03-governance.md`](03-governance.md)
- What your source language may contain: [`04-languages.md`](04-languages.md)
- Getting a project running: [`05-cli.md`](05-cli.md)
