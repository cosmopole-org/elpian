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
//! * [`app`] — what "one mini app" is: its functions, grants, limits, secrets
//!   and network mode.
//! * [`runtime`] — registered apps, and running one of their functions.
//! * [`httpcore`] — a small blocking HTTP/1.1 server with a bounded pool.
//! * [`gateway`] — the four routes a device talks to.
//! * [`component`] — the payload a server component returns, and the cache in
//!   front of it.
//! * [`egress`] — the broker: the only way out, and the rules it applies.
//! * [`fetch`] — performing the request the broker allowed, and auditing it.
//! * [`pool`] — loading instances on demand, unloading them when nothing needs
//!   them, and the cost meters.
//! * [`policy`] — manifest ∩ grant, ported from Dart and checked against a
//!   corpus both languages read.
//! * [`registry`] — what apps exist, at what versions, and where their bytecode
//!   lives.

pub mod app;
pub mod appfs;
pub mod component;
pub mod egress;
pub mod fetch;
pub mod gateway;
pub mod httpcore;
pub mod hostcall;
pub mod invoke;
pub mod policy;
pub mod pool;
pub mod registry;
pub mod posture;
pub mod runtime;
pub mod services;
pub mod state;

pub use app::{AppDefinition, FunctionKind, NetworkMode};
pub use hostcall::{HostCall, HostServices};
pub use component::{ComponentPayload, PayloadError, RenderCache};
pub use egress::{decide, DenyReason, EgressDecision};
pub use fetch::{fetch, EgressRecord, FetchError, FetchLimits, FetchResponse};
pub use policy::{Grant, Manifest, Policy};
pub use registry::{AppRecord, RegistryError, RegistryStore, VersionRecord};
pub use pool::{InstancePool, Meters, PoolConfig};
pub use runtime::{AppRuntime, CallError, Invocation};
pub use invoke::{invoke, InvokeLimits, Outcome};
pub use posture::{server_capabilities, SERVER_DENIED, SERVER_GRANTABLE};
