# Elpian — the complete wiki (an agent skill)

This `wiki/` is a **skill**: a set of Markdown files that together let any AI
agent (or human) understand the Elpian system well enough to write programs on
it, drive its CLI, and build/run/deploy them **without mistakes**. Each file
documents one subsystem in depth, with the real API surface, working examples,
and the exact pitfalls to avoid.

> **If you read nothing else, read [`14-gotchas.md`](14-gotchas.md) first.** It
> is the concentrated list of mistakes that *look* fine but break at runtime.

## What Elpian is (one paragraph)

Elpian runs **dynamically-delivered application code with no JIT and no
ahead-of-time native compilation**. You write **TypeScript** (or JavaScript, or
a Dart subset); a Rust toolchain compiles it to **Elpian bytecode**; and a
sandboxed **Rust VM** — a pausing AST/bytecode interpreter — executes it inside
a host. The host is a **Flutter application** (`elpian_ui`), which turns a JSON
UI tree the guest emits into real Flutter widgets: 60+ Flutter widgets, 70+ HTML
tags, a 150+ property CSS engine, a 2D canvas, and an embedded Godot 4 engine
reached as a `Scene3D` widget. Because nothing generates machine code at runtime, the same program is legal on iOS and
runs on the web. The guest reaches the outside world through exactly one seam,
`askHost(name, payload)`, which is where capability gating and resource metering
are enforced.

```
 Your program (TypeScript / JavaScript / Dart subset)
   │  oxc  (strips TS types)  →  js2elpian  →  Elpian AST JSON  →  bytecode
   ▼
 Elpian VM  (Rust; pausing interpreter; suspends on askHost(name, payload))
   │  askHost("render", viewJson) / "println" / "dom.*" / "canvas.*" / timers …
   ▼
 Host: Flutter app (elpian_ui)
        ├─ ElpianEngine        — JSON UI tree → Flutter widget tree (161 tags)
        ├─ CSS + stylesheets   — 201 style properties, classes, media queries
        ├─ EventDispatcher     — 40+ event types routed back into the VM
        ├─ Canvas2D / Scene3D  — drawing + embedded Godot 3D
        └─ Governance          — capabilities, resource meters, the VM tree
```

## The files

| File | Read it when you need to… |
|---|---|
| [`01-architecture.md`](01-architecture.md) | Understand the whole system, its layers, the repo map, and the no-JIT rationale. |
| [`02-elpian-vm.md`](02-elpian-vm.md) | Know how the VM executes: the typed value envelope, the AST/bytecode pipeline, `askHost`, run states, traps, the universal stdlib. |
| [`03-governance.md`](03-governance.md) | Sandbox untrusted code: capabilities, resource limits and meters, the multi-VM tree, aggregate accounting, lifecycle control. |
| [`04-languages.md`](04-languages.md) | Write guest code — the exact supported surface of TypeScript, JavaScript and Dart, and what is *not* supported. |
| [`05-cli.md`](05-cli.md) | Drive the `elpian` CLI: `create`, `run install`, `run build`, `run dev`, config files, the package system. |
| [`06-templates.md`](06-templates.md) | Understand the four project templates — client, server, fullstack, showcase — and what each generates. |
| [`07-ui-model.md`](07-ui-model.md) | Emit UI from a guest program: the node JSON shape, `props` vs `events`, the render loop, scoped re-render. |
| [`08-widgets.md`](08-widgets.md) | Pick a tag: the complete catalog of 161 registered widgets and HTML elements with their props. |
| [`09-styling.md`](09-styling.md) | Style it: the CSS property surface, JSON stylesheets, classes, variables, media queries, keyframes. |
| [`10-events.md`](10-events.md) | Handle input: the 40+ event types, phases, propagation, and how a click reaches a VM function. |
| [`11-canvas-and-3d.md`](11-canvas-and-3d.md) | Draw: the 2D canvas command API, and the embedded Godot `Scene3D` — its DSL, controller, and the reflective op protocol. |
| [`12-host-apis.md`](12-host-apis.md) | Call the host: the full `askHost` API catalog (core, timers, DOM, canvas) and writing custom handlers. |
| [`13-recipes.md`](13-recipes.md) | Copy working patterns: a counter, a form, a fetch-and-list, a server endpoint, a sandboxed child VM. |
| [`14-gotchas.md`](14-gotchas.md) | **The mistakes to never make.** Read this before writing code. |
| [`15-ast-reference.md`](15-ast-reference.md) | Look up an AST node, an operator, or the VM's Dart/FFI surface. |
| [`16-widget-reference.md`](16-widget-reference.md) | Look up a widget prop, an HTML element, or a CSS property. |
| [`17-nextjs-integration.md`](17-nextjs-integration.md) | Render Next.js server payloads — request modes, navigation, `clientComp`. |

## How an agent should use this skill

1. **Building an app?** Start at [`05-cli.md`](05-cli.md) (scaffold + build +
   run), then [`06-templates.md`](06-templates.md) to pick client / server /
   fullstack.
2. **Writing guest code?** [`04-languages.md`](04-languages.md) for what the
   compiler accepts, [`07-ui-model.md`](07-ui-model.md) for the render contract,
   [`08-widgets.md`](08-widgets.md) + [`09-styling.md`](09-styling.md) for the
   UI surface, [`10-events.md`](10-events.md) for interaction.
3. **Embedding the VM in your own Flutter app?**
   [`02-elpian-vm.md`](02-elpian-vm.md) + [`12-host-apis.md`](12-host-apis.md).
4. **Running untrusted code?** [`03-governance.md`](03-governance.md) is the
   whole story — capabilities, meters, and the VM tree.
5. **Read [`14-gotchas.md`](14-gotchas.md).** Most first-try failures are there.

## Source-of-truth pointers

This wiki is written to be correct, but **the code is the ultimate authority**.
Exhaustive lists (every widget prop, every CSS property) live in the source:

- **VM (Rust):** `rust/crates/elpian-vm/src/sdk/` — `executor.rs` (the interpreter), `compiler.rs`
  (AST→bytecode), `program.rs` (decode), `limits.rs`, `capabilities.rs`,
  `hierarchy.rs`, `lifecycle.rs`, `stdlib/mod.rs`; public API in `rust/crates/elpian-vm/src/api.rs`.
- **VM embedding:** `rust/crates/elpian-ffi/src/abi.rs` (native), `rust/crates/elpian-wasm/src/lib.rs` (web),
  `rust/crates/elpian-vm/src/bin/elpian-server.rs` (the HTTP server VM).
- **Flutter host:** `lib/src/vm/` (widget + runtimes + host handlers),
  `lib/src/core/` (engine, registry, events, DOM), `lib/src/widgets/`,
  `lib/src/html_widgets/`, `lib/src/css/`, `lib/src/canvas/`, `lib/src/godot/`. Public surface: `lib/elpian_ui.dart`.
- **Compilers:** `rust/crates/js2elpian/src/lib.rs` (JS→AST→bytecode),
  `rust/crates/dart2elpian/src/lib.rs` (Dart→JS subset) — vendored in-repo.
- **CLI:** `cli/rust/main.rs` (single file), `cli/README.md`.
- **Web shell:** `cli/elpian_client/` (the standalone Flutter project
  the CLI builds and serves).
- **The old root-level documents are gone.** What was still true in them was
  folded in here: `VM_LOGIC.md` → chapter 15, `2D_GRAPHICS.md` → chapter 16,
  `NEXTJS_INTEGRATION.md` → chapter 17, and the guidance sections of
  `EVENT_SYSTEM.md` / `JSON_STYLESHEET.md` into chapters 10 and 9. The rest
  described removed subsystems (Bevy, the Dart 3D renderer, the TPS demo) or was
  superseded.
- **Embedded Godot (native side):** `godot/` — the Android and iOS
  platform views, the op queues, and the Godot-side `OpSink.gd`. A separate
  plugin package so an app with no 3D does not carry the ~21 MB Godot AAR.
- **Tests as executable specs:** `test/` (60+ files — layout, CSS, scope,
  Godot ops/DSL, events, Next.js integration).
