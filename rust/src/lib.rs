//! # elpian-vm
//!
//! The Elpian AST-based bytecode virtual machine, ported from the Elpian
//! project for use as the application logic core of the Elpa framework.
//!
//! ## Pipeline
//!
//! ```text
//! source language ──(front-end crate)──▶ Elpian AST JSON
//!           ──(compiler::compile_ast)───────────────▶ bytecode (Vec<u8>)
//!           ──(program::DecodedProgram::decode)──────▶ in-memory operation list
//!           ──(executor)──────────────────────────────▶ execution + host calls
//! ```
//!
//! This crate is **purely the executor**: it ingests Elpian AST JSON
//! ([`api::create_vm_from_ast`]) or prebuilt bytecode
//! ([`api::create_vm_from_bytecode`]) and runs it. The *language* front-ends live
//! in their own crates — `js2elpian` (JavaScript → AST) and `dart2elpian`
//! (Dart → AST) — so the VM has no notion of any source language; every
//! front-end converges on the shared `from ast` path.
//!
//! The front-end (source → bytecode) can run **ahead of time**: a tool compiles
//! the program to bytecode once at build time (e.g. `js2elpian::compile_js_to_bytecode`),
//! and the deployed app loads the bytecode straight into a VM
//! (`api::create_vm_from_bytecode`) — no parsing or AST work at startup. The
//! executor then decodes the bytecode **once**, at construction, into an
//! addressable in-memory list of operation objects (see [`sdk::program`]) and
//! traverses that on every step instead of re-parsing the raw bytes, so a
//! program that re-runs its render path every frame pays the decode cost only
//! once.
//!
//! The VM is a *pausing* interpreter: when user code calls
//! `askHost(apiName, payload)` it suspends and hands a host-call request back
//! to the embedder. The embedder (the Elpa runtime) services the call —
//! crucially `askHost("render", uiTree)` — and resumes the VM with
//! [`api::continue_execution`].
//!
//! This crate is renderer-agnostic. It knows nothing about wgpu; it only emits
//! host-call requests as JSON. The `elpa-runtime` crate wires those requests to
//! the `elpa-renderer`.
//!
//! See `PLAN.md` at the repository root for the full architecture.

pub mod api;
pub mod sdk;

pub use sdk::data::Val;
pub use sdk::vm::VM;
