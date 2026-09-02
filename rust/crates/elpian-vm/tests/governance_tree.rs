//! The VM tree's governance invariants, exercised through the public `api`.
//!
//! `sdk::hierarchy` unit-tests the intersection arithmetic on pure data. These
//! tests check the part that actually protects a super app: that the *public
//! API* cannot be used to hand a mini app more authority than its parent holds,
//! and that a revoke reaches every descendant at once.
//!
//! The invariant, in the hierarchy module's own words: "A parent that lacks a
//! permission can never confer it."

use elpian_vm::api;
use elpian_vm::api::{Capability, CapabilitySet, ResourceLimits};
use serde_json::json;

/// A do-nothing program — these tests are about policy, not execution.
fn trivial_program() -> String {
    json!({
        "type": "program",
        "body": [{
            "type": "definition",
            "data": {
                "leftSide": { "type": "identifier", "data": { "name": "x" } },
                "rightSide": { "type": "i64", "data": { "value": 1 } }
            }
        }]
    })
    .to_string()
}

fn make(id: &str) {
    assert!(
        api::create_vm_from_ast(id.to_string(), trivial_program()),
        "{id} should compile"
    );
}

fn cleanup(ids: &[&str]) {
    for id in ids {
        api::destroy_vm(id.to_string());
    }
}

#[test]
fn a_parent_that_lacks_a_capability_cannot_confer_it() {
    let (parent, child) = ("gov-noconfer-parent", "gov-noconfer-child");
    make(parent);
    make(child);
    assert!(api::adopt_vm(parent, child));

    // The parent gives up the network for its whole branch.
    assert!(api::set_capability(parent, Capability::Network, false));
    assert!(!api::effective_capabilities(child).is_allowed(Capability::Network));

    // Now try to hand it back to the child directly. This is the escape that
    // used to work: `set_capability` wrote straight into the child's executor,
    // bypassing the intersection entirely.
    api::set_capability(child, Capability::Network, true);

    assert!(
        api::local_capabilities(child).is_allowed(Capability::Network),
        "the grant is recorded locally"
    );
    assert!(
        !api::effective_capabilities(child).is_allowed(Capability::Network),
        "but it must stay ineffective while the parent denies it"
    );
    assert!(
        !api::capability_allows(child, "net.fetch"),
        "and the executor — the thing that actually gates askHost — must agree"
    );

    cleanup(&[parent, child]);
}

#[test]
fn the_bulk_setter_cannot_widen_past_an_ancestor_either() {
    let (parent, child) = ("gov-bulk-parent", "gov-bulk-child");
    make(parent);
    make(child);
    assert!(api::adopt_vm(parent, child));

    assert!(api::set_capability(parent, Capability::Storage, false));

    // `allow_all` is the widest set expressible. It must still be clipped.
    api::set_capabilities(child, CapabilitySet::allow_all());

    assert!(
        !api::capability_allows(child, "fs.read"),
        "a wholesale allow_all must not escape the parent's denial"
    );
    assert!(
        api::capability_allows(child, "net.fetch"),
        "capabilities the parent still holds are unaffected"
    );

    cleanup(&[parent, child]);
}

#[test]
fn a_revoke_reaches_the_whole_descendant_subtree_at_once() {
    let (root, mid, leaf) = ("gov-deep-root", "gov-deep-mid", "gov-deep-leaf");
    make(root);
    make(mid);
    make(leaf);
    assert!(api::adopt_vm(root, mid));
    assert!(api::adopt_vm(mid, leaf));

    assert!(api::capability_allows(leaf, "fs.read"));

    // Revoke two levels above the leaf.
    assert!(api::set_capability(root, Capability::Storage, false));

    for id in [root, mid, leaf] {
        assert!(
            !api::capability_allows(id, "fs.read"),
            "{id} should have lost storage the moment the root did"
        );
    }

    // And granting it back at the root restores the branch, because none of
    // the descendants ever revoked it locally.
    assert!(api::set_capability(root, Capability::Storage, true));
    for id in [root, mid, leaf] {
        assert!(
            api::capability_allows(id, "fs.read"),
            "{id} should regain storage when the root grants it again"
        );
    }

    cleanup(&[root, mid, leaf]);
}

#[test]
fn adoption_clips_a_child_that_was_wider_than_its_new_parent() {
    let (parent, child) = ("gov-adopt-parent", "gov-adopt-child");
    make(parent);
    make(child);

    // Both start wide open; the parent then closes the network. The child is
    // still standalone, so it keeps its own full set.
    assert!(api::set_capability(parent, Capability::Network, false));
    assert!(api::capability_allows(child, "net.fetch"));

    // Adoption must immediately clip it to the new ancestor path.
    assert!(api::adopt_vm(parent, child));
    assert!(
        !api::capability_allows(child, "net.fetch"),
        "adoption must apply the parent's denials at once, not at the next toggle"
    );

    cleanup(&[parent, child]);
}

#[test]
fn a_standalone_vm_keeps_full_authority() {
    // A VM with no parent has no ancestors to intersect with, so it is
    // governed only by what the host sets on it directly.
    let id = "gov-standalone";
    make(id);

    assert!(api::capability_allows(id, "net.fetch"));
    assert!(api::set_capability(id, Capability::Network, false));
    assert!(!api::capability_allows(id, "net.fetch"));
    assert!(api::set_capability(id, Capability::Network, true));
    assert!(api::capability_allows(id, "net.fetch"));

    cleanup(&[id]);
}

// ---- Cost: a parent pays for its children, and bounds them ------------------
//
// The other half of the tree contract. A child mini app's execution is counted
// against its parent's budget as well as its own, and a parent may cap its
// children directly — so a parent has full control of what its children can
// spend, and cannot escape the bill by pushing work down into them.

/// A program that burns instructions in a loop, so usage is observable.
fn busy_program(iterations: i64) -> String {
    json!({
        "type": "program",
        "body": [
            { "type": "definition", "data": {
                "leftSide": { "type": "identifier", "data": { "name": "i" } },
                "rightSide": { "type": "i64", "data": { "value": 0 } } } },
            { "type": "loopStmt", "data": {
                "condition": { "type": "arithmetic", "data": {
                    "operation": "<",
                    "operand1": { "type": "identifier", "data": { "name": "i" } },
                    "operand2": { "type": "i64", "data": { "value": iterations } } } },
                "body": [
                    { "type": "assignment", "data": {
                        "leftSide": { "type": "identifier", "data": { "name": "i" } },
                        "rightSide": { "type": "arithmetic", "data": {
                            "operation": "+",
                            "operand1": { "type": "identifier", "data": { "name": "i" } },
                            "operand2": { "type": "i64", "data": { "value": 1 } } } } } }
                ] } }
        ]
    })
    .to_string()
}

fn make_busy(id: &str, iterations: i64) {
    assert!(
        api::create_vm_from_ast(id.to_string(), busy_program(iterations)),
        "{id} should compile"
    );
}

#[test]
fn a_childs_execution_is_counted_against_its_parent() {
    let (parent, child) = ("gov-cost-parent", "gov-cost-child");
    make_busy(parent, 10);
    make_busy(child, 400);
    assert!(api::adopt_vm(parent, child));

    api::execute_vm(parent.to_string());
    api::execute_vm(child.to_string());

    let own = api::usage(parent).expect("parent usage").instructions;
    let subtree = api::subtree_usage(parent)
        .expect("subtree usage")
        .instructions;
    let child_own = api::usage(child).expect("child usage").instructions;

    assert!(
        child_own > 0,
        "the child should have executed something to count"
    );
    assert_eq!(
        subtree,
        own + child_own,
        "a parent is accountable for its own work plus its whole subtree's"
    );
    assert!(
        subtree > own,
        "pushing work into a child must not hide it from the parent's bill"
    );

    cleanup(&[parent, child]);
}

#[test]
fn a_parent_can_cap_its_child_directly() {
    let (parent, child) = ("gov-cap-parent", "gov-cap-child");
    make_busy(parent, 1);
    make_busy(child, 100_000);
    assert!(api::adopt_vm(parent, child));

    // The parent bounds what the child may spend.
    let mut tight = ResourceLimits::unlimited();
    tight.max_instructions = Some(500);
    assert!(api::set_limits(child, tight));

    api::execute_vm(child.to_string());

    let reason = api::trap_reason(child).expect("the child should have hit its ceiling");
    assert!(
        reason.contains("instruction"),
        "the trap should name the budget it broke, got {reason:?}"
    );
    assert!(
        api::usage(child).expect("usage").instructions <= 600,
        "the child must be stopped near its ceiling, not far past it"
    );

    cleanup(&[parent, child]);
}

#[test]
fn a_subtree_blowing_the_parents_budget_takes_the_branch_down() {
    let (parent, child) = ("gov-budget-parent", "gov-budget-child");
    make_busy(parent, 1);
    make_busy(child, 5_000);
    assert!(api::adopt_vm(parent, child));

    // The parent's own budget is small; the child's work counts against it.
    let mut parent_limits = ResourceLimits::unlimited();
    parent_limits.max_instructions = Some(200);
    assert!(api::set_limits(parent, parent_limits));

    api::execute_vm(child.to_string());

    let violations = api::enforce_tree_budgets();
    let hit = violations
        .iter()
        .find(|(id, _, _)| id == parent)
        .expect("the parent's aggregate should have broken its own budget");

    assert_eq!(hit.1, "instructions");
    assert!(
        hit.2.iter().any(|id| id == child),
        "the whole branch goes down together, child included: {:?}",
        hit.2
    );
    assert!(
        !api::vm_exists(child.to_string()),
        "the child must not outlive the branch it bankrupted"
    );

    cleanup(&[parent, child]);
}
