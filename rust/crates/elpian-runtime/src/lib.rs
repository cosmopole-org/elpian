//! # elpian-runtime — a tree of governed VMs sharing one host
//!
//! One embedding hosts not a single guest but a **tree** of them. The root VM
//! runs the host's own program; any VM holding the `vm_manage` capability can
//! spawn children with `askHost("vm.spawn", …)` and holds full control of each
//! one — lifecycle, resource limits, capability permissions and messaging.
//!
//! ## Why this crate exists
//!
//! All of this lived inside `elpian-godot-capi`, the C ABI the Godot
//! GDExtension embeds. Nothing about a tree of governed VMs is specific to
//! Godot — the same manager already forwarded `flutter.op` and `rn.op` seams
//! verbatim — but because it sat inside the Godot crate, the Flutter host
//! could not reach it. Flutter linked the VM directly and got creation and
//! execution with no manager at all, so a mini app running under Flutter could
//! not spawn a child mini app from its own code, however well the VM tree
//! underneath supported it.
//!
//! The Godot-specific parts turned out to be five small things, now behind
//! [`HostSurface`]:
//!
//!   * composing the guest program with the right prelude,
//!   * the op-seam names a UI operation crosses on,
//!   * the guest function names an event or callback is delivered to,
//!   * verifying that an assigned sandbox node lies inside its parent's, and
//!   * granting a child access to one handle.
//!
//! ## The tree rules
//!
//! Backed by `elpian_vm::sdk::hierarchy`, enforced in the VM rather than here:
//!
//! * **Lifecycle binding** — terminating a VM terminates its entire descendant
//!   subtree; a parent's death takes all children along.
//! * **Aggregate budgets** — a parent's usage is its own plus its whole
//!   descendant subtree. If the aggregate blows the parent's own limits the
//!   *whole branch* is terminated together. A hung child first traps on its own
//!   per-turn instruction cap and the parent is notified; a parent that never
//!   cleans up eventually pays with the branch.
//! * **Permission intersection** — a VM's effective capabilities are the AND of
//!   the local grants along its ancestor path. Granting a child something the
//!   parent lacks is inert; a revoke anywhere is pushed to the whole affected
//!   subtree at once.
//!
//! ## The sandbox
//!
//! Every spawned VM is assigned a node in the shared host surface, chosen by
//! its parent and verified to lie inside the parent's own sandbox. All of the
//! VM's surface access is confined to that node's subtree: the manager stamps
//! every forwarded op with the calling VM's sandbox root and namespaces every
//! callback id into that VM's own space, so a child cannot address a sibling's
//! nodes or receive a sibling's events.
//!
//! ## Threading
//!
//! A manager and its bridge belong to ONE thread — the host's UI thread. The
//! `Send` asserted in a few places is satisfied by construction: the embedder
//! never migrates the manager across threads.

use serde_json::Value;

pub mod manager;

pub use manager::{BridgeFn, GuestLang, VmManager, ROOT_VM};

/// What the embedding host provides to the multi-VM manager.
///
/// Everything the manager needs that differs between a Godot scene, a Flutter
/// widget tree and a React Native view tree. Implementations are small: the
/// Godot one is a dozen lines over the preludes and op names it already had.
pub trait HostSurface {
    /// Compose the final guest program: the host's prelude, then the user
    /// source. The manager never parses either; it only hands the result to
    /// the compiler.
    fn compose(&self, lang: GuestLang, user_source: &str) -> String;

    /// The op-seam prefix this host reads, without a trailing dot — `"godot"`,
    /// `"flutter"`, `"rn"`. The manager sanitizes and forwards
    /// `<prefix>.op` and `<prefix>.batch`.
    ///
    /// Ops for *other* known prefixes are still sanitized and forwarded, so one
    /// host can drive several surfaces (a Flutter widget tree containing an
    /// embedded 3D scene, for instance).
    fn op_prefix(&self) -> &str;

    /// The guest function a namespaced callback is delivered to.
    fn dispatch_fn(&self) -> &str;

    /// The guest function a broadcast host event is delivered to.
    fn event_fn(&self) -> &str;

    /// Whether `node` lies inside `sandbox` — the containment check that makes
    /// a child's assigned node safe to grant.
    ///
    /// Only the host knows its own tree, so the manager asks. `sandbox == 0`
    /// means the caller is unsandboxed (the root), which permits any node.
    ///
    /// The default answers "yes" for a host with no tree to check, which is
    /// the honest answer for a surface where nodes are not nested. A host that
    /// *does* nest must override it: returning true unconditionally there would
    /// let a child escape its parent's subtree.
    fn verify_containment(
        &self,
        _bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        _node: i64,
        _sandbox: i64,
    ) -> bool {
        true
    }

    /// Give VM `vm` access to `handle` inside `sandbox`. Returns whether the
    /// host accepted the grant.
    ///
    /// The default declines, because a host that has not implemented granting
    /// cannot honour it and a silent success would be a lie about what the
    /// child can reach.
    fn grant_handle(
        &self,
        _bridge: &mut dyn FnMut(&str, &[Value]) -> Option<Value>,
        _vm: u64,
        _handle: i64,
        _sandbox: i64,
    ) -> bool {
        false
    }
}
