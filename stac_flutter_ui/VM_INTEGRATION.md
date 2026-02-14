# Elpian VM - Flutter Rust Bridge Integration

This document describes how the Elpian Rust VM sandbox is integrated into
the `stac_flutter_ui` Flutter library via Flutter Rust Bridge (FRB).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 Flutter / Dart                       │
│                                                      │
│  ┌──────────────────┐    ┌──────────────────────┐   │
│  │  ElpianVmWidget  │───▶│     StacEngine        │   │
│  │  (orchestrator)   │    │  (renders JSON→Widget)│   │
│  └──────────────────┘    └──────────────────────┘   │
│          │                         ▲                 │
│          │                         │ viewJson        │
│          ▼                         │                 │
│  ┌──────────────────┐    ┌──────────────────────┐   │
│  │    ElpianVm      │───▶│    HostHandler        │   │
│  │  (Dart wrapper)   │    │  (routes host calls)  │   │
│  └──────────────────┘    └──────────────────────┘   │
│          │                                           │
├──────────┼───────────── FFI / WASM ─────────────────┤
│          ▼                                           │
│  ┌──────────────────────────────────────────────┐   │
│  │              Rust VM (elpian_vm)               │   │
│  │                                                │   │
│  │  ┌───────────┐  ┌──────────┐  ┌───────────┐  │   │
│  │  │  Compiler  │  │ Executor │  │  Context   │  │   │
│  │  │ (AST→BC)   │  │ (VM loop)│  │ (scopes)   │  │   │
│  │  └───────────┘  └──────────┘  └───────────┘  │   │
│  │                                                │   │
│  │  Host calls: render, updateApp, println, ...   │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## How It Works

1. **VM Creation**: Dart creates a Rust VM instance via FRB, providing
   either source code or a pre-compiled AST.

2. **Execution**: The VM compiles code to bytecode and executes it.
   When the VM code calls `askHost("render", viewJson)`, the VM pauses
   and returns the host call to Dart.

3. **Host Call Routing**: The `HostHandler` on the Dart side receives
   the `render` call, parses the view JSON, and passes it to `StacEngine`.

4. **Rendering**: `StacEngine.renderFromJson()` converts the JSON view
   tree into Flutter widgets using the 200+ registered widget builders.

5. **Continuation**: After processing the host call, Dart sends a
   response back to the Rust VM, which resumes execution.

## Platform Support

| Platform | Mechanism | Status |
|----------|-----------|--------|
| Android  | FFI (NDK) | Configured via rust_builder |
| iOS      | FFI (staticlib) | Configured via CocoaPods |
| macOS    | FFI (staticlib) | Configured via CocoaPods |
| Linux    | FFI (cdylib) | Configured via CMake |
| Windows  | FFI (cdylib) | Configured via CMake |
| Web      | WASM | Supported via FRB WASM compilation |

## Setup

### Prerequisites

- Rust toolchain (`rustup`)
- Flutter SDK (>=3.0.0)
- `flutter_rust_bridge_codegen` CLI tool

### Install FRB Codegen

```bash
cargo install flutter_rust_bridge_codegen
```

### For mobile cross-compilation targets:

```bash
# Android
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android

# iOS
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim

# Web (WASM)
rustup target add wasm32-unknown-unknown
```

### Generate Bindings

```bash
cd stac_flutter_ui
flutter_rust_bridge_codegen generate
```

This will:
1. Parse `rust/src/api/mod.rs` for public functions
2. Generate Dart bindings in `lib/src/vm/frb_generated/`
3. Generate Rust FFI glue code
4. Handle platform-specific compilation setup

### Run the App

```bash
flutter run
```

## Usage

### Basic Widget

```dart
ElpianVmWidget(
  machineId: 'my-app',
  code: r\'''
    def view = {
      "type": "Column",
      "children": [
        {"type": "Text", "props": {"text": "Hello from VM!"}},
        {"type": "Button", "props": {"text": "Click me"}}
      ]
    }
    askHost("render", view)
  \''',
)
```

### With Controller

```dart
final controller = ElpianVmController();

ElpianVmScope(
  controller: controller,
  machineId: 'my-app',
  code: myCode,
  onPrintln: (msg) => print('VM: $msg'),
  onUpdateApp: (data) => handleUpdate(data),
)

// Later, call VM functions from Dart:
await controller.callFunction('onButtonClick');
```

### From AST JSON

```dart
ElpianVmWidget.fromAst(
  machineId: 'my-app',
  astJson: '{"type":"program","body":[...]}',
)
```

### Custom Host Handlers

```dart
ElpianVmWidget(
  machineId: 'my-app',
  code: myCode,
  hostHandlers: {
    'customApi': (apiName, payload) async {
      // Handle custom API calls from the VM
      return '{"type":"string","data":{"value":"response"}}';
    },
  },
)
```

## VM Code Reference

### Available Host Functions

- `askHost("render", viewJson)` - Render a view tree
- `askHost("updateApp", data)` - Send update data to Flutter
- `askHost("println", message)` - Print to debug console
- `askHost("stringify", value)` - Convert value to string

### Supported Value Types

| Type | Code | Example |
|------|------|---------|
| null | 0 | `null` |
| i16 | 1 | `42` |
| i32 | 2 | `100000` |
| i64 | 3 | `9999999999` |
| f32 | 4 | `3.14` |
| f64 | 5 | `3.14159265` |
| bool | 6 | `true` |
| string | 7 | `"hello"` |
| object | 8 | `{ "key": "value" }` |
| array | 9 | `[1, 2, 3]` |
| function | 10 | `func foo() { ... }` |

### JSON Response Format

When returning values from host handlers, use the typed format:

```json
{"type": "string", "data": {"value": "hello"}}
{"type": "i16", "data": {"value": 42}}
{"type": "bool", "data": {"value": true}}
```

## File Structure

```
stac_flutter_ui/
├── rust/                              # Rust VM crate
│   ├── Cargo.toml                     # FRB-compatible Rust config
│   └── src/
│       ├── lib.rs                     # Crate root
│       ├── api/
│       │   └── mod.rs                 # FRB public API (create/execute/continue)
│       └── sdk/
│           ├── mod.rs                 # SDK module exports
│           ├── vm.rs                  # VM instance manager
│           ├── compiler.rs            # AST/code → bytecode compiler
│           ├── executor.rs            # Bytecode interpreter
│           ├── context.rs             # Variable scope management
│           └── data.rs                # Type system (Val, Object, Array, etc.)
├── rust_builder/                      # FRB build integration
│   ├── pubspec.yaml                   # Flutter plugin for native build
│   ├── android/                       # Android NDK config
│   ├── ios/                           # iOS CocoaPods config
│   ├── macos/                         # macOS CocoaPods config
│   ├── linux/                         # Linux CMake config
│   └── windows/                       # Windows CMake config
├── lib/src/vm/                        # Dart VM integration
│   ├── elpian_vm.dart                 # Dart VM wrapper
│   ├── elpian_vm_widget.dart          # Flutter widget + controller
│   ├── host_handler.dart              # Host call → StacEngine bridge
│   └── frb_generated/
│       └── api.dart                   # FRB generated bindings (stub/generated)
├── flutter_rust_bridge.yaml           # FRB codegen configuration
└── pubspec.yaml                       # Flutter deps (includes FRB + rust_builder)
```
