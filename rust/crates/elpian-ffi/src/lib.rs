//! # elpian-ffi — the native library Flutter loads
//!
//! Produces `libelpian_vm.{so,dll,a}` and exports three surfaces:
//!
//!   * [`abi`] — creating, running and resuming a VM, plus the whole
//!     governance control plane (limits, meters, capabilities, lifecycle, the
//!     spawn tree).
//!   * [`manager`] — the multi-VM manager, so a *guest* can spawn child mini
//!     apps with `askHost("vm.spawn", …)` and steer them.
//!   * a `HostSurface` for Flutter, so the manager knows how to reach it.
//!
//! ## Why it is a separate package
//!
//! The ABI used to live inside `elpian-vm` as `api::ffi`. That was fine until
//! the manager needed to be reachable from it: `elpian-runtime` depends on
//! `elpian-vm`, so an ABI inside `elpian-vm` could never call into the runtime
//! without a dependency cycle. Splitting it out breaks the cycle, and keeping
//! the artifact named `elpian_vm` means the Dart bindings did not change.

pub mod abi;
pub mod manager;

pub use manager::FlutterSurface;
