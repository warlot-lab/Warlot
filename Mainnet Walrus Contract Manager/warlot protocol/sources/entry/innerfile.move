/// Creates an inner file, writes to it, merges a draft, and mints or revokes a pass.
module warlot::entry_innerfile;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    admin_cap::AdminCap,
    blob_config::{Self, BlobConfig},
    credential::{Self, Credential},
    deny_list,
    draft,
    eviction,
    file_data::{Self, FileData},
    inner_file::{Self, InnerFile},
    operator::{Self, OperatorAuth},
    project_object::{Self, ProjectHolder},
    store,
    system_config::SystemConfig,
    user,
    writer_pass::{Self, WriterPass},
};

// === Errors ===

#[error]
const ACCESSDENIED: vector<u8> = b"invalid writer pass";
#[error]
const INVALIDACCESS: vector<u8> = b"Invalid access";
#[error]
const ENotFileOwner: vector<u8> = b"NOT THE OWNER OF THIS FILE";
#[error]
const EInvalidPassDuration: vector<u8> = b"A DELEGATED PASS MUST EXPIRE AT A FUTURE TIMESTAMP";
#[error]
const ENotOwnersConfig: vector<u8> = b"THIS CONFIG IS NOT HELD BY THE OWNER OF THIS FILE";
#[error]
const EWrongDraftConfig: vector<u8> = b"THIS CONFIG IS NOT THE ONE THE MERGED DRAFT NAMES";
#[error]
const ENoAddBlobGrant: vector<u8> =
    b"A WRITER PASS CANNOT BE MINTED TO AN ADDRESS THAT MAY NOT STORE FOR THE OWNER";
#[error]
const ENotDenied: vector<u8> = b"THIS WRITER IS NOT DENIED ON THIS FILE";

// === Public functions ===

/// Store `blobs` as a file's first revision, share the file, and hand the owner
/// a non-decaying pass. When `should_include_pass` is set and the caller is not
/// the owner, the caller is given one that expires at `pass_duration`.
///
/// `pass_duration` is a timestamp in ms and is read only on that branch. It must
/// be in the future, which is also what keeps it away from the sentinel that
/// marks a pass non-decaying: a delegate acting on someone else's behalf is
/// given authority with an end date, never authority without one.
///
/// `operators_allowed` and `operators_may_bypass_draft` are the owner's terms for
/// system operators on this one file, taken here so a file can be born closed
/// rather than needing a second transaction to shut it. Open is the ordinary
/// answer, because admitting operators at all is a decision the account owner
/// already made when they granted the role; these are the per-file escape hatch
/// from it.
public fun create_file(
    system_cfg: &SystemConfig,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    create_file_core(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        option::none(),
        should_include_pass,
        pass_duration,
        ctx,
    )
}

/// The same creation, made on the strength of an operator credential rather than
/// a grant against the sender's address.
///
/// It mints the operator no pass. The owner's own non-decaying pass is minted
/// either way ,  it always was, on both sides of `should_include_pass` ,  and an
/// operator does not need one: the credential is what authorises the write, and a
/// pass minted to a rotating key would have to be re-minted per file per key,
/// which is the cost this whole path exists to remove.
public fun create_file_as_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    let auth = authorise_operator(system_cfg, admin_cap, clock);

    create_file_core(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        option::some(auth),
        false,
        0,
        ctx,
    )
}

/// Create a file and name it as `project_id`'s database.
public fun initialize_project_file(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    system_cfg: &SystemConfig,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let new_inner_file_id = create_file_core(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        option::none(),
        should_include_pass,
        pass_duration,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, option::none(), ctx);

    project_object::init_db(project_holder, project_id, new_inner_file_id, owner);
}

/// The same initialisation, made on the strength of an operator credential.
public fun initialize_project_file_as_operator(
    project_holder: &mut ProjectHolder,
    project_id: ID,
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = authorise_operator(system_cfg, admin_cap, clock);

    let new_inner_file_id = create_file_core(
        system_cfg,
        owner,
        writers_length,
        track_back_length,
        blobs,
        epoch_set,
        cycle_end,
        clock,
        commit,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        option::some(auth),
        false,
        0,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, option::some(auth), ctx);

    project_object::init_db(project_holder, project_id, new_inner_file_id, owner);
}

/// Replace this file's terms for system operators.
///
/// Owner-only and gated on the sender, not on a pass. A pass that could flip
/// these would let an operator that has been shut out re-admit itself, and the
/// bypass bit an admin sets on an operator's slot cannot reach past this one: a
/// write skips the draft queue only if the slot and the file both say so, so
/// refusing here is final.
public fun set_operator_policy(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), ENotFileOwner);

    inner_file.set_operator_policy(
        operators_allowed,
        operators_may_bypass_draft,
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

/// Write straight into the file's history, bypassing the draft queue.
///
/// Changes made this way cannot be reversed except through the rollback window.
///
/// `evicted` carries the config named by the revision this write pushes out of
/// the window, and is empty when the window still has room. See
/// `eviction::advance_history` for when each is required.
///
/// Owner-only, so it has no operator sibling: the owner check is strictly
/// stronger than any credential could be, and an operator that could satisfy it
/// would be the file's owner.
public fun force_write_innerfile(
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);

    let file_data: FileData = process_blob(
        system_cfg,
        blobs,
        inner_file.epoch_set(),
        inner_file.cycle_end(),
        inner_file.owner(),
        commit,
        ctx.sender(),
        option::none(),
        clock,
        ctx,
    );

    eviction::advance_history(inner_file, file_data, evicted, clock, object::id(system_cfg));
}

/// Write to the file, either as a draft awaiting the owner's merge or, with an
/// admin pass, straight into the file's history.
///
/// `issue` is an opaque reference to whatever the draft resolves, recorded in
/// the audit trail because it is part of what the owner agreed to when merging.
/// Nothing on chain interprets it: the tracker it used to name was three objects
/// per file that no reachable function ever wrote to.
public fun write_(
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    write_core(
        inner_file,
        credential::from_pass(writer_pass),
        writer_pass.has_admin_privilege(),
        to_draft,
        issue,
        clock,
        system_cfg,
        blobs,
        commit,
        evicted,
        option::none(),
        ctx,
    )
}

/// The same write, made on the strength of an operator credential rather than a
/// pass minted on this file.
///
/// The only one of the seven pass-taking calls that gains a sibling. The other
/// six assert that the sender is the file's owner, so a credential adds nothing
/// to them: an operator that could satisfy that assert would be the owner.
///
/// `to_draft` is a request rather than an instruction here. An operator asking to
/// skip the queue is routed into it anyway unless its own slot **and** this file
/// both carry the bypass ,  the owner's refusal is not something an admin can
/// grant its way past. A pass without the privilege is refused outright instead,
/// which is the behaviour that path has always had and keeps.
///
/// A write that ends in the queue is custodied by whoever pushed it, exactly as a
/// pass holder's draft is, so the routing carries the storage cost away from the
/// owner along with the content. That means a signing key whose writes can be
/// queued must itself be a registered user. A key that always bypasses never
/// stores under its own address and needs no registration at all.
public fun write_as_operator(
    inner_file: &mut InnerFile,
    admin_cap: &AdminCap,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let auth = authorise_operator(system_cfg, admin_cap, clock);
    inner_file.verify_operator(ctx.sender(), &auth, clock);

    let may_bypass = auth.auth_may_bypass_draft() && inner_file.operators_may_bypass_draft();

    write_core(
        inner_file,
        credential::from_operator(admin_cap),
        may_bypass,
        to_draft,
        issue,
        clock,
        system_cfg,
        blobs,
        commit,
        evicted,
        option::some(auth),
        ctx,
    )
}

/// Record a revision as the file's known-good fallback.
///
/// The config is named by the object rather than by its id, so that the fallback
/// cannot be pointed at content the file's owner does not hold. A fallback is the
/// state the owner intends to return to; one that names somebody else's content
/// is a fallback that can be withdrawn out from under them.
public fun set_root_change(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    commit: vector<u8>,
    config: &BlobConfig,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);
    assert!(blob_config::owner(config) == inner_file.owner(), ENotOwnersConfig);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);
    let file_data: FileData = file_data::create_file_data(
        commit,
        ctx.sender(),
        blob_config::config_id(config),
    );

    let displaced = inner_file.swap_root_change(file_data, system_id);

    if (displaced.is_some()) {
        eviction::discard(displaced.destroy_some(), file_id, system_id);
    } else {
        displaced.destroy_none();
    }
}

/// Drop the file's known-good fallback.
///
/// The content it named is left alone. It is the file owner's already, it is a
/// shared object they can reach by id, and withdrawal is the one call that
/// releases it ,  so the fallback's removal announces the config and stops there
/// rather than deciding on the owner's behalf that the content is finished with.
public fun remove_root_change(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);

    eviction::discard(
        inner_file.extract_root_change(system_id, ctx.sender()),
        file_id,
        system_id,
    );
}

/// Merge a draft into the file's history.
///
/// `merge_latest` ignores `draft_index` and takes the most recently pinned draft,
/// which is what its name says and the opposite of what it used to do.
///
/// `draft_config` is the config the merged draft names. Merging re-parents it to
/// the file's owner in the same transaction that accepts the content, because an
/// approval that leaves the content custodied and funded by the proposer is not an
/// approval ,  the owner's authoritative history would depend on the writer's
/// mandate, and the writer could withdraw it back out again.
public fun merge_draft_into_file(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    draft_config: &mut BlobConfig,
    draft_index: u64,
    merge_latest: bool,
    evicted: vector<BlobConfig>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let owner = inner_file.owner();
    let system_id = object::id(system_cfg);
    let file_id = object::id(inner_file);
    let merged_by = ctx.sender();
    let draft_holder = inner_file.get_draft_holder();

    let file_data: FileData = {
        if (merge_latest) {
            draft::fetch_and_delete_latest_draft(
                draft_holder,
                clock,
                system_id,
                file_id,
                merged_by,
            )
        } else {
            draft::resolve_draft_to_file(
                draft_holder,
                draft_index,
                clock,
                system_id,
                file_id,
                merged_by,
            )
        }
    };

    assert!(
        blob_config::config_id(draft_config) == file_data.blob_config_id(),
        EWrongDraftConfig,
    );
    blob_config::transfer_ownership(draft_config, system_id, owner);

    eviction::advance_history(inner_file, file_data, evicted, clock, system_id);
}

/// Delete one draft.
///
/// The rejected revision's content stays with the writer who proposed it. The
/// event names the config so they can reclaim it.
public fun delete_draft(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    draft_index: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);
    let deleted_by = ctx.sender();
    let draft_holder = inner_file.get_draft_holder();

    let proposed = draft::delete_draft(
        draft_holder,
        draft_index,
        clock,
        system_id,
        file_id,
        deleted_by,
    );

    eviction::discard(option::destroy_some(proposed), file_id, system_id);
}

/// Delete the drafts this file holds at indices `[from_index, to_index)`.
///
/// The range is the caller's, so one call costs what they asked it to cost. The
/// previous form walked every index the file had ever issued, which meant a file
/// with enough drafts could never clear them again.
public fun clear_drafts(
    system_cfg: &SystemConfig,
    inner_file: &mut InnerFile,
    writer_pass: &WriterPass,
    from_index: u64,
    to_index: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let file_id = object::id(inner_file);
    let system_id = object::id(system_cfg);
    let deleted_by = ctx.sender();
    let draft_holder = inner_file.get_draft_holder();

    let mut revisions = draft::clear_drafts(
        draft_holder,
        from_index,
        to_index,
        clock,
        system_id,
        file_id,
        deleted_by,
    );

    // Bounded by the range above, one entry per draft that was present in it.
    while (!revisions.is_empty()) {
        eviction::discard(revisions.pop_back(), file_id, system_id);
    };

    revisions.destroy_empty();
}

/// Mint a writer pass for `writer`, with or without the draft-queue bypass.
///
/// Refused unless `writer` may already store blobs under the file's owner. A pass
/// alone cannot write into a file's history ,  the store underneath it checks
/// `add_blob` as well ,  so a pass minted to an address without that grant is a
/// pass that fails at its first use and says nothing about why at the mint.
/// Failing here is legible; failing at the first write is not.
///
/// It is a refusal and never an auto-grant. Conferring `add_blob` on the
/// recipient would widen a delegation past what the caller asked for, so the
/// order is load-bearing: grant `add_blob`, then mint.
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

    let owners_obj = user::get_user(system_cfg, file.owner());
    assert!(user::grants_add_blob(owners_obj, writer), ENoAddBlobGrant);

    let pass = writer_pass::new(object::id(file), duration, admin_pass, ctx);

    writer_pass::transfer_to(pass, writer, object::id(system_cfg), ctx);
}

// === Private functions ===

/// Abort unless the sender holds a live operator credential for this system, and
/// hand back the proof that they do.
fun authorise_operator(
    system_cfg: &SystemConfig,
    admin_cap: &AdminCap,
    clock: &Clock,
): OperatorAuth {
    operator::authorise(
        system_cfg.operator_set(),
        admin_cap,
        object::id(system_cfg),
        clock.timestamp_ms(),
    )
}

/// Store `blobs` as a file's first revision and share the file.
fun create_file_core(
    system_cfg: &SystemConfig,
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    clock: &Clock,
    commit: vector<u8>,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    operator: Option<OperatorAuth>,
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
): ID {
    let system_id = object::id(system_cfg);

    let first_revision = process_blob(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        owner,
        commit,
        ctx.sender(),
        operator,
        clock,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);

    user::check_permission_inner_file(owners_obj, operator, ctx);

    let new_inner_file = inner_file::new(
        owner,
        writers_length,
        track_back_length,
        epoch_set,
        cycle_end,
        operators_allowed,
        operators_may_bypass_draft,
        draft_epoch_duration,
        first_revision,
        clock,
        ctx,
    );

    let new_inner_file_id = object::id(&new_inner_file);

    let immortal_pass = inner_file::new_owner_pass(new_inner_file_id, ctx);

    // A file created on someone else's behalf leaves the creator able to perform
    // restricted operations on it.
    if (should_include_pass && owner != ctx.sender()) {
        user::check_permission_writer_pass(owners_obj, operator, ctx);
        assert!(pass_duration > clock.timestamp_ms(), EInvalidPassDuration);

        let temp_pass = writer_pass::new(new_inner_file_id, pass_duration, true, ctx);

        writer_pass::transfer_to(temp_pass, ctx.sender(), system_id, ctx);
    };

    inner_file::share(new_inner_file, system_id);
    writer_pass::transfer_to(immortal_pass, owner, system_id, ctx);

    new_inner_file_id
}

/// Take one revision from `credential`, into the file's history or into its draft
/// queue.
///
/// `may_bypass` is whether the credential itself permits skipping the queue: for
/// a pass, its admin privilege; for an operator, its slot's bypass bit **and**
/// the file's own, so an owner who refused the bypass cannot be overridden by an
/// admin who granted it.
///
/// What a refused bypass does differs by kind, deliberately. A pass without the
/// privilege asking to skip the queue is refused, which is what it has always
/// done. An operator without it is routed into the queue instead, because the
/// owner's answer to an operator is *where the write goes*, not whether it
/// happens ,  that routing is the whole content of `operators_may_bypass_draft`.
///
/// A routed write carries the sender's custody rather than the owner's, and
/// retires nothing, so a caller that asked to skip the queue and passed the
/// config for the revision it would have evicted is refused by name.
fun write_core(
    inner_file: &mut InnerFile,
    credential: Credential,
    may_bypass: bool,
    to_draft: bool,
    issue: Option<ID>,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    operator: Option<OperatorAuth>,
    ctx: &mut TxContext,
) {
    let mut queue = to_draft;

    if (!to_draft) {
        if (credential.is_operator()) {
            queue = !may_bypass;
        } else {
            assert!(may_bypass, ACCESSDENIED);
        };
    };

    // A draft's blobs stay with the writer who pushed them; a merge's belong to
    // the file's owner.
    let store_to: address = {
        if (queue) {
            ctx.sender()
        } else {
            inner_file.owner()
        }
    };

    let file_data: FileData = process_blob(
        system_cfg,
        blobs,
        inner_file.epoch_set(),
        inner_file.cycle_end(),
        store_to,
        commit,
        ctx.sender(),
        operator,
        clock,
        ctx,
    );

    let system_id = object::id(system_cfg);

    if (!queue) {
        eviction::advance_history(inner_file, file_data, evicted, clock, system_id);
        return
    };

    // A draft displaces nothing, so it can retire nothing.
    eviction::assert_no_config(evicted);

    let file_draft = draft::create_draft(issue, option::some(file_data), ctx);

    inner_file.pin_draft(file_draft, credential, clock, system_id, ctx);
}

/// Store `blobs` under `store_to` and record the result as one revision.
fun process_blob(
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    store_to: address,
    commit: vector<u8>,
    commit_by: address,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &mut TxContext,
): FileData {
    let (blob_config_id, _) = store::store_blob_internal(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        store_to,
        operator,
        clock,
        ctx,
    );

    file_data::create_file_data(commit, commit_by, blob_config_id)
}
