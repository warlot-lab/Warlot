/// Exposes compaction: open a plan, name the configs it replaces, register the
/// receipt.
///
/// Three calls rather than one, composed inside a single programmable
/// transaction, for the reason renewal is one call per config: Move cannot take a
/// vector of mutable references and a compaction has to *read* every predecessor
/// to refuse a cross-user or mixed-policy one. The plan that carries them between
/// the calls has no abilities, so it cannot outlive the transaction, cannot be
/// stored and cannot be dropped ,  a transaction that opens one and does not
/// register it does not commit at all. Nothing pending is ever left on chain.
///
/// A worked call sequence:
///
/// ```
/// plan = plan_compaction(sys, &new_quilt_config)
/// supersede(&mut plan, &old_config_1)
/// supersede(&mut plan, &old_config_2)
/// register_layout(sys, &mut new_quilt_config, plan, 1, 1, paths, hashes, clock)
/// ```
///
/// Then, and only then, the owner verifies the new quilt and withdraws the old
/// configs themselves. Nothing here deletes anything, and nothing here can.
module warlot::entry_compaction;

// === Imports ===

use sui::clock::Clock;
use warlot::{
    admin_cap::AdminCap,
    blob_config::{Self, BlobConfig},
    compaction::{Self, CompactionPlan},
    operator::OperatorAuth,
    system_config::SystemConfig,
    user,
};

// === Public functions ===

/// Open a compaction against the config the new content was stored under.
///
/// Permissionless, and it has to be: it reads two public fields off a shared
/// object and produces a value that cannot be stored, transferred or dropped.
/// The authority is checked where the state changes, at `register_layout`, which
/// is the only call that can consume what this returns.
public fun plan_compaction(system_cfg: &SystemConfig, target: &BlobConfig): CompactionPlan {
    system_cfg.assert_version();

    compaction::plan(target)
}

/// Name `config` as one of the configs this compaction replaces.
///
/// Refused unless `config` shares the target's owner, storage term and renewal
/// mandate. Those are the two properties a quilt cannot express any other way:
/// Walrus deletes and extends a quilt whole, so a quilt spanning two owners has
/// no participant who can delete, and a quilt spanning two terms has no term it
/// can be renewed under.
public fun supersede(plan: &mut CompactionPlan, config: &BlobConfig) {
    compaction::supersede(plan, config);
}

/// Write the compaction's receipt onto its target.
///
/// Requires `can_compact` on the target's owner, or the sender being that owner.
/// The bit delegates the additive half of a compaction and nothing else: this
/// call destroys nothing, retires nothing and re-parents nothing, and the
/// superseded configs stay exactly as renewable afterwards as they were before.
///
/// `kind` is `0` for raw blobs and `1` for a quilt, and a quilt is checked
/// against the custody rather than believed. `generation` must exceed every
/// generation the compaction supersedes. Both commitments are derived from what
/// the contract read, never from an argument.
public fun register_layout(
    system_cfg: &SystemConfig,
    target: &mut BlobConfig,
    plan: CompactionPlan,
    kind: u8,
    generation: u32,
    paths: vector<vector<u8>>,
    content_hashes: vector<vector<u8>>,
    clock: &Clock,
    ctx: &TxContext,
) {
    system_cfg.assert_version();

    register(
        system_cfg,
        target,
        plan,
        kind,
        generation,
        paths,
        content_hashes,
        option::none(),
        clock,
        ctx,
    )
}

/// The same registration, made on the strength of an operator credential rather
/// than a grant against the sender's address.
///
/// This is the path a background compaction service takes. It is deliberately the
/// widest thing an operator may do to stored content and it is still additive:
/// the operator writes the new quilt and the receipt, and the owner is the only
/// address that can then release what the receipt says was replaced.
public fun register_layout_as_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    target: &mut BlobConfig,
    plan: CompactionPlan,
    kind: u8,
    generation: u32,
    paths: vector<vector<u8>>,
    content_hashes: vector<vector<u8>>,
    clock: &Clock,
    ctx: &TxContext,
) {
    system_cfg.assert_version();

    let auth = system_cfg.authorise_operator(admin_cap, clock.timestamp_ms());

    register(
        system_cfg,
        target,
        plan,
        kind,
        generation,
        paths,
        content_hashes,
        option::some(auth),
        clock,
        ctx,
    )
}

// === Private functions ===

/// Check the compaction bit against the target's owner, then write the receipt.
fun register(
    system_cfg: &SystemConfig,
    target: &mut BlobConfig,
    plan: CompactionPlan,
    kind: u8,
    generation: u32,
    paths: vector<vector<u8>>,
    content_hashes: vector<vector<u8>>,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &TxContext,
) {
    let owner = blob_config::owner(target);
    let owners_obj = user::get_user(system_cfg, owner);

    user::check_permission_can_compact(owners_obj, operator, ctx);

    compaction::register(
        object::id(system_cfg),
        target,
        plan,
        kind,
        generation,
        paths,
        content_hashes,
        clock.timestamp_ms(),
        ctx.sender(),
    );
}
