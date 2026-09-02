//! # dart — the optional Dart/Flutter host surface for the Elpian VM
//!
//! A Dart/Flutter runtime layer on top of the [Elpian VM](../elpian_vm/). Elpian
//! is a **no-JIT** AST/bytecode interpreter: it never generates native machine
//! code, so it is valid for the iOS App Store (Guideline 2.5.2 / no W^X
//! violation) and compiles to `wasm32`. That makes it a legal execution layer
//! for dynamically-delivered application code on *every* Flutter target,
//! including the two the Dart VM cannot serve dynamically (iOS and web).
//!
//! ## What this crate is
//!
//! The Flutter framework is inseparable from the Dart runtime's **foundational
//! ("group 3") libraries** — `dart:ui`, `dart:typed_data`, `dart:isolate`,
//! `dart:io`, `dart:ffi` — which in stock Flutter are *native* functions bound
//! into the Dart isolate by the C++ engine, not Dart source. To run Flutter
//! logic on Elpian those surfaces must be re-provided to the guest. This crate
//! provides them as **host-bridge services** over Elpian's `askHost` pause/
//! resume seam, each gated by a two-layer capability + resource governor.
//!
//! ```text
//!  guest code ──askHost("dart:ui/Canvas.drawRect",[…])──▶ DartRuntime
//!                                                          ├─ governance (caps + limits)
//!                                                          ├─ dart:ui       (SceneRecorder)
//!                                                          ├─ dart:typed_data (TypedDataStore)
//!                                                          └─ …             (isolate/io/ffi: planned)
//!            ◀──────────── reply value (or thrown error) ──┘
//! ```
//!
//! ## Phase status (see `elpian/README.md` for the full roadmap)
//!
//! * **Implemented & tested:** the driver + two-layer governor, the Dart numeric
//!   tower ([`value`]), `dart:typed_data` (`ByteData` get/set + endianness), and
//!   a `dart:ui` `PictureRecorder`/`Canvas`/`Picture` slice that records a
//!   serializable scene tree for a native rasterizer.
//! * **Planned:** the Dart→Elpian AST front-end, reified generics/type checks,
//!   the `async`/microtask/`Zone` scheduler, `dart:isolate`, `dart:io`, and the
//!   remainder of the `dart:ui` surface. These are specified, not yet built.
//!
//! Nothing here claims to run the unmodified Flutter framework kernel today; it
//! is the foundation that a Dart front-end + framework port targets.

// The entire Dart/Flutter host surface is gated behind the `dart` feature — the
// `--include-dart` switch. With the feature off (`--no-default-features`) the
// crate compiles to nothing, so a VM build that does not want the Dart extras
// pays for none of them. The VM itself carries no Dart language semantics:
// Dart-specific surface (`~/`, `??`, `is`/`as` type names, member spellings)
// is lowered by dart2elpian at compile time onto the VM's universal primitives
// (the `intDiv` builtin, the neutral null-coalescing opcode, neutral type-tag
// names, universal stdlib names), which are always available regardless of
// this feature.

#[cfg(feature = "dart")]
pub mod async_loop;
#[cfg(feature = "dart")]
pub mod binding;
#[cfg(feature = "dart")]
pub mod bundle;
#[cfg(feature = "dart")]
pub mod core;
#[cfg(feature = "dart")]
pub mod dart_ui;
#[cfg(feature = "dart")]
pub mod governance;
#[cfg(feature = "dart")]
pub mod isolate;
#[cfg(feature = "dart")]
pub mod runtime;
#[cfg(feature = "dart")]
pub mod scene_diff;
#[cfg(feature = "dart")]
pub mod sha256;
#[cfg(feature = "dart")]
pub mod typed_data;
#[cfg(feature = "dart")]
// wasm_api is a C ABI for running the VM in a browser as a
// wasm32-unknown-unknown module (see its module docs). Emitting it on native
// targets exports `elpian_init` into every cdylib, which collides with the
// VM's own native FFI entry point of the same name — a real duplicate-symbol
// link error, not a warning. Gate it to the target it was written for, which
// `target_arch = "wasm32"` alone does not: that also matches
// wasm32-unknown-emscripten, the target the Godot web GDExtension links.
#[cfg(all(target_arch = "wasm32", target_os = "unknown"))]
pub mod wasm_api;
#[cfg(feature = "dart")]
pub mod widgets;

#[cfg(feature = "dart")]
pub use core::Clock;
#[cfg(feature = "dart")]
pub use governance::{DartCapability, DartCapabilitySet, ResourceMeter};
#[cfg(feature = "dart")]
pub use runtime::{DartError, DartRuntime};
