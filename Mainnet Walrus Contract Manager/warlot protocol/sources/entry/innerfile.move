/// Creates an inner file, writes to it, merges a draft, and mints or revokes a pass.
module warlot::entry_innerfile;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    blob_config::{Self, BlobConfig},
    deny_list,
    draft,
    eviction,
    file_data::{Self, FileData},
    inner_file::{Self, InnerFile},
    issue,
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

// === Public functions ===

/// Store `blobs` as a file's first revision, share the file, and hand the owner
/// a non-decaying pass. When `should_include_pass` is set and the caller is not
/// the owner, the caller is given one that expires at `pass_duration`.
///
/// `pass_duration` is a timestamp in ms and is read only on that branch. It must
/// be in the future, which is also what keeps it away from the sentinel that
/// marks a pass non-decaying: a delegate acting on someone else's behalf is
/// given authority with an end date, never authority without one.
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
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
): ID {
    system_cfg.assert_version();

    let system_id = object::id(system_cfg);

    let first_revision = process_blob(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        owner,
        commit,
        ctx.sender(),
        clock,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);

    user::check_permission_inner_file(owners_obj, ctx);

    let new_inner_file = inner_file::new(
        owner,
        writers_length,
        track_back_length,
        epoch_set,
        cycle_end,
        first_revision,
        clock,
        ctx,
    );

    let new_inner_file_id = object::id(&new_inner_file);

    let immortal_pass = inner_file::new_owner_pass(new_inner_file_id, owner, ctx);

    // A file created on someone else's behalf leaves the creator able to perform
    // restricted operations on it.
    if (should_include_pass && owner != ctx.sender()) {
        user::check_permission_writer_pass(owners_obj, ctx);
        assert!(pass_duration > clock.timestamp_ms(), EInvalidPassDuration);

        let temp_pass = writer_pass::new(
            new_inner_file_id,
            pass_duration,
            option::some(writer_pass::new_admin_pass(owner)),
            ctx,
        );

        writer_pass::transfer_to(temp_pass, ctx.sender(), system_id, ctx);
    };

    inner_file::share(new_inner_file, draft_epoch_duration, system_id, clock, ctx);
    writer_pass::transfer_to(immortal_pass, owner, system_id, ctx);

    new_inner_file_id
}

/// Create a file and name it as `project_name`'s database.
public fun initialize_project_file(
    project_holder: &mut ProjectHolder,
    project_name: String,
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
    should_include_pass: bool,
    pass_duration: u64,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let new_inner_file_id = create_file(
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
        should_include_pass,
        pass_duration,
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, ctx);

    project_object::init_db(project_holder, project_name, new_inner_file_id, owner);
}

/// Deny `writer` until `period`, or indefinitely when `period` is zero.
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
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::deny(deny_obj, writer, period, now_ms, system_id, file_id, ctx.sender());
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
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::revoke_pass(deny_obj, pass_id, system_id, file_id, ctx.sender());
}

/// Write straight into the file's history, bypassing the draft queue.
///
/// Changes made this way cannot be reversed except through the rollback window.
///
/// `evicted` carries the config named by the revision this write pushes out of
/// the window, and is empty when the window still has room. See
/// `eviction::advance_history` for when each is required.
public fun force_write_innerfile(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
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
        clock,
        ctx,
    );

    eviction::advance_history(inner_file, file_data, evicted, clock, object::id(system_cfg));
}

/// Write to the file, either as a draft awaiting the owner's merge or, with an
/// admin pass, straight into the file's history.
public fun write_(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    to_draft: bool,
    file_issue: u64,
    should_include_issue: bool,
    clock: &Clock,
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    evicted: vector<BlobConfig>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    // A draft's blobs stay with the writer who pushed them; a merge's belong to
    // the file's owner.
    let store_to: address = {
        if (to_draft) {
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
        clock,
        ctx,
    );

    let system_id = object::id(system_cfg);

    if (!to_draft) {
        assert!(writer_pass.has_admin_privilege(), ACCESSDENIED);
        eviction::advance_history(inner_file, file_data, evicted, clock, system_id);
        return
    };

    // A draft displaces nothing, so it can retire nothing.
    eviction::assert_no_config(evicted);

    let file_issue_meta = inner_file.get_issue_meta();
    let issue_state = {
        if (should_include_issue) {
            issue::confirm_issue(file_issue_meta, file_issue)
        } else {
            option::none()
        }
    };

    let file_draft = draft::create_draft(
        object::id(writer_pass),
        issue_state,
        option::some(file_data),
        ctx,
    );

    inner_file.pin_draft(file_draft, clock, system_id);
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
    writer_pass: &mut WriterPass,
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
    writer_pass: &mut WriterPass,
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
    writer_pass: &mut WriterPass,
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
    writer_pass: &mut WriterPass,
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
    writer_pass: &mut WriterPass,
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
    let admin_pass = {
        if (admin_pass) {
            option::some(writer_pass::new_admin_pass(file.owner()))
        } else {
            option::none()
        }
    };

    let pass = writer_pass::new(object::id(file), duration, admin_pass, ctx);

    writer_pass::transfer_to(pass, writer, object::id(system_cfg), ctx);
}

// === Private functions ===

/// Store `blobs` under `store_to` and record the result as one revision.
fun process_blob(
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    store_to: address,
    commit: vector<u8>,
    commit_by: address,
    clock: &Clock,
    ctx: &mut TxContext,
): FileData {
    let (blob_config_id, _) = store::store_blob_internal(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        option::none(),
        store_to,
        clock,
        ctx,
    );

    file_data::create_file_data(commit, commit_by, blob_config_id)
}
