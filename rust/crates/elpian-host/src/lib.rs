//! # elpian-host
//!
//! The server side of an Elpian mini app: it runs the app's server-function
//! VMs, services their host calls, and governs what they may do.
//!
//! ## What this replaces
//!
//! `elpian-server` created a VM per request, ran it, and returned HTTP 501 the
//! moment the guest called the host — so a server function could not log, read
//! the clock, keep state, or touch a file. There was also no object anywhere
//! meaning "one mini app": the server knew about a single bytecode blob.
//!
//! ## The shape
//!
//! * [`posture`] — what a server function may do, written positively from
//!   deny-all rather than derived from the client's set.
//! * [`hostcall`] — the envelope, and the trait a host implements to answer one.
//! * [`invoke`] — the loop that drives one invocation and services its calls.
//! * [`state`] — durable per-app key/value state (`kv.*`) and declared secrets.
//! * [`appfs`] — the app-rooted filesystem (`fs.*`), confined and charged.
//! * [`services`] — the real [`HostServices`] implementation wiring those up.

pub mod appfs;
pub mod hostcall;
pub mod invoke;
pub mod posture;
pub mod services;
pub mod state;

pub use hostcall::{HostCall, HostServices};
pub use invoke::{invoke, InvokeLimits, Outcome};
pub use posture::{server_capabilities, SERVER_DENIED, SERVER_GRANTABLE};
