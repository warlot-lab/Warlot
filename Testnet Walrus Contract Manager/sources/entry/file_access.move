/// Sets an inner file's terms for delegates: who may write it, who is refused,
/// and which credentials it no longer accepts.
module warlot::entry_file_access;

// === Imports ===

use sui::clock::Clock;
use warlot::{
    deny_list,
    inner_file::InnerFile,
    system_config::SystemConfig,
    user,
    writer_pass,
};

// === Errors ===

#[error]
const ENotFileOwner: vector<u8> = b"NOT THE OWNER OF THIS FILE";
#[error]
const ENotDenied: vector<u8> = b"THIS WRITER IS NOT DENIED ON THIS FILE";
#[error]
const ENoAddBlobGrant: vector<u8> =
    b"AN ADMIN PASS CANNOT BE MINTED TO AN ADDRESS THAT MAY NOT STORE FOR THE OWNER";

// === Public functions ===

/// Replace this file's terms for system operators.
///
/// Owner-only and gated on the sender, not on a pass. A pass that could flip
/// these would let an operator that has been shut out re-admit itself, and the
/// bypass bit an admin sets on an operator's slot cannot reach past this one: a
/// write skips the draft queue only if the slot and the file both say so, so
/// refusing here is final.
///
/// The three bits are taken together because they are one statement about one
/// file, and the fifth spelling ,  admitting operators while opening neither
/// route ,  is refused rather than stored. This is also the call that undoes what
/// `create_file_as_operator` opens: a file created by an operator is born writable
/// by it, and narrowing that is the owner's act.
public fun set_operator_policy(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    operators_may_draft: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), ENotFileOwner);

    inner_file.set_operator_policy(
        operators_allowed,
        operators_may_bypass_draft,
        operators_may_draft,
        object::id(system_cfg),
        ctx.sender(),
    );
}

/// Deny `writer`, who is not already denied, until `period` ,  or indefinitely
/// when `period` is zero.
///
/// Refuses a writer who already holds a denial; moving an existing deadline is
/// `redeny_writer`. The two are separate so that reaching for the blunt
/// instrument cannot quietly shorten a denial the owner meant to leave alone.
public fun deny_writer(
    system_cfg: &SystemConfig,
    file: &mut InnerFile,
    writer: address,
    period: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);
    let now_ms = clock.timestamp_ms();
    let system_id = object::id(system_cfg);
    let file_id = object::id(file);
    // Read before the borrow: attaching the list on first use takes `ctx`
    // mutably, and the sender cannot be read out of it while it is held.
    let denied_by = ctx.sender();
    let deny_obj = deny_list::borrow_mut_or_attach(file.uid_mut(), ctx);
    deny_list::deny(deny_obj, writer, period, now_ms, system_id, file_id, denied_by);
}

/// Move `writer`'s existing denial to `period`, or to indefinite when zero.
///
/// Refuses a writer who holds no denial, so moving a deadline cannot silently
/// make one. A file with no deny list denies nobody, and is refused for the same
/// reason rather than being given one to hold the change in.
public fun redeny_writer(
    system_cfg: &SystemConfig,
    file: &mut InnerFile,
    writer: address,
    period: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);
    assert!(file.has_deny_list(), ENotDenied);

    let now_ms = clock.timestamp_ms();
    let system_id = object::id(system_cfg);
    let file_id = object::id(file);
    let denied_by = ctx.sender();
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::redeny(deny_obj, writer, period, now_ms, system_id, file_id, denied_by);
}

/// Lift `writer`'s denial.
public fun remove_deny_writer(
    system_cfg: &SystemConfig,
    file: &mut InnerFile,
    writer: address,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);

    // A file that has never denied anybody denies this writer too, so there is
    // nothing to lift and no reason to give the file a deny list to hold it in.
    if (!file.has_deny_list()) return;

    let system_id = object::id(system_cfg);
    let file_id = object::id(file);
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::undeny(deny_obj, writer, system_id, file_id, ctx.sender());
}

/// Revoke the pass `pass_id`, permanently.
///
/// A pass is an owned object living in its holder's account, so the owner of the
/// file cannot reach it and cannot destroy it. The record kept on the file is
/// therefore the whole of the mechanism: the pass survives in the delegate's
/// account and stops being accepted. Denying the delegate's address is the
/// blunter instrument and does not replace this one ,  a pass can be handed on,
/// and an address can hold more than one.
///
/// The record is keyed by `ID` and is blind to what the id names, so this is also
/// how an owner refuses one operator's capability on one file without waiting for
/// the admin to retire its slot everywhere.
public fun revoke_pass(
    system_cfg: &SystemConfig,
    file: &mut InnerFile,
    pass_id: ID,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);
    let system_id = object::id(system_cfg);
    let file_id = object::id(file);
    let revoked_by = ctx.sender();
    let deny_obj = deny_list::borrow_mut_or_attach(file.uid_mut(), ctx);
    deny_list::revoke_pass(deny_obj, pass_id, system_id, file_id, revoked_by);
}

/// Revoke several passes on one file in one transaction.
///
/// An owner who has decided a delegate is finished usually has more than one id
/// to refuse: a pass can be handed on, and an address can hold several. Doing
/// that one transaction at a time leaves a window in which some of them still
/// write.
///
/// The deny list is attached once for the whole batch rather than once per id,
/// and an id already refused is passed over by `revoke_pass` itself, so a caller
/// resubmitting a list it is unsure of is not an error.
public fun revoke_passes(
    system_cfg: &SystemConfig,
    file: &mut InnerFile,
    pass_ids: vector<ID>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);

    let system_id = object::id(system_cfg);
    let file_id = object::id(file);
    let revoked_by = ctx.sender();
    let deny_obj = deny_list::borrow_mut_or_attach(file.uid_mut(), ctx);

    // Bounded by the ids the transaction carries.
    pass_ids.do!(|pass_id| deny_list::revoke_pass(
        deny_obj,
        pass_id,
        system_id,
        file_id,
        revoked_by,
    ));
}

/// Mint a writer pass for `writer`, with or without the draft-queue bypass.
///
/// An **admin** pass is refused unless `writer` may already store blobs under the
/// file's owner. A pass that writes straight into a file's history cannot do so
/// alone ,  the store underneath it checks `add_blob` as well ,  so an admin pass
/// minted to an address without that grant is a pass that fails at its first use
/// and says nothing about why at the mint. Failing here is legible; failing at
/// the first write is not.
///
/// A **draft-only** pass is refused nothing. A queued write is custodied by
/// whoever pushed it, so it stores under the sender's own address, where the
/// check returns at once. Requiring a grant on the owner's account for that pass
/// would hand a draft-only collaborator authority to store under the owner's
/// address ,  strictly more than the pass they are being given can use, and the
/// opposite of what coupling the two was for.
///
/// It is a refusal and never an auto-grant. Conferring `add_blob` on the
/// recipient would widen a delegation past what the caller asked for, so the
/// order is load-bearing where it applies: grant `add_blob`, then mint the admin
/// pass.
public fun create_pass(
    system_cfg: &SystemConfig,
    file: &InnerFile,
    writer: address,
    duration: u64,
    admin_pass: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(file.owner() == ctx.sender(), ENotFileOwner);

    if (admin_pass) {
        let owners_obj = user::get_user(system_cfg, file.owner());
        assert!(user::grants_add_blob(owners_obj, writer), ENoAddBlobGrant);
    };

    let pass = writer_pass::new(object::id(file), duration, admin_pass, ctx);

    writer_pass::transfer_to(pass, writer, object::id(system_cfg), ctx);
}
