/// Creates an inner file, writes to it, merges a draft, and mints or revokes a pass.
module warlot::entry_innerfile;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{
    deny_list,
    draft,
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

// === Public functions ===

/// Store `blobs` as a file's first revision, share the file, and hand the owner
/// a non-decaying pass. When `should_include_pass` is set and the caller is not
/// the owner, the caller is given one too.
public fun create_file(
    system_cfg: &mut SystemConfig,
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
    ctx: &mut TxContext,
): ID {
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

        let temp_pass = inner_file::new_owner_pass(new_inner_file_id, owner, ctx);

        writer_pass::transfer_to(temp_pass, ctx.sender());
    };

    inner_file::share(new_inner_file, draft_epoch_duration, clock, ctx);
    writer_pass::transfer_to(immortal_pass, owner);

    new_inner_file_id
}

/// Create a file and name it as `project_name`'s database.
public fun initialize_project_file(
    project_holder: &mut ProjectHolder,
    project_name: String,
    system_cfg: &mut SystemConfig,
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
    ctx: &mut TxContext,
) {
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
        ctx,
    );

    let owners_obj = user::get_user(system_cfg, owner);
    user::check_permission_can_init_db(owners_obj, ctx);

    project_object::init_db(project_holder, project_name, new_inner_file_id, owner);
}

/// Deny `writer` until `period`, or indefinitely when `period` is zero.
public fun deny_writer(
    file: &mut InnerFile,
    writer: address,
    period: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(file.owner() == ctx.sender(), 1);
    let now_ms = clock.timestamp_ms();
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::deny(deny_obj, writer, period, now_ms);
}

/// Lift `writer`'s denial.
public fun remove_deny_writer(file: &mut InnerFile, writer: address, ctx: &mut TxContext) {
    assert!(file.owner() == ctx.sender(), 1);
    let deny_obj = deny_list::borrow_mut(file.uid_mut());
    deny_list::undeny(deny_obj, writer);
}

/// Write straight into the file's history, bypassing the draft queue.
///
/// Changes made this way cannot be reversed except through the rollback window.
public fun force_write_innerfile(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    clock: &Clock,
    system_cfg: &mut SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    ctx: &mut TxContext,
) {
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

    inner_file.override_file_add(file_data, clock);
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
    system_cfg: &mut SystemConfig,
    blobs: vector<Blob>,
    commit: vector<u8>,
    ctx: &mut TxContext,
) {
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

    if (!to_draft) {
        assert!(writer_pass.has_admin_privilege(), ACCESSDENIED);
        inner_file.override_file_add(file_data, clock);
        return
    };

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

    draft::pin_draft(inner_file.get_draft_holder(), file_draft, clock);
}

/// Record a revision as the file's known-good fallback.
public fun set_root_change(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    commit: vector<u8>,
    blob_config_id: ID,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let file_data: FileData = file_data::create_file_data(commit, ctx.sender(), blob_config_id);

    let _ = inner_file.swap_root_change(file_data);
}

/// Drop the file's known-good fallback, optionally deleting its stored content.
public fun remove_root_change(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    delete_blob: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let _ = inner_file.extract_root_change();
    if (delete_blob) {
        // The blob backing the fallback is not yet removed from Walrus here.
    }
}

/// Merge a draft into the file's history.
public fun merge_draft_into_file(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    draft_index: u64,
    merge_latest: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let draft_holder = inner_file.get_draft_holder();

    let file_data: FileData = {
        if (merge_latest) {
            draft::resolve_draft_to_file(draft_holder, draft_index, clock)
        } else {
            draft::fetch_and_delete_latest_draft(draft_holder, clock)
        }
    };

    inner_file.override_file_add(file_data, clock);
}

/// Delete one draft.
public fun delete_draft(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    draft_index: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let draft_holder = inner_file.get_draft_holder();

    draft::delete_draft(draft_holder, draft_index, clock);
}

/// Delete every draft on the file and reset its draft queue.
public fun clear_all_draft(
    inner_file: &mut InnerFile,
    writer_pass: &mut WriterPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(inner_file.owner() == ctx.sender(), INVALIDACCESS);
    inner_file.verify_pass(ctx.sender(), writer_pass, clock);

    let draft_holder = inner_file.get_draft_holder();

    draft::clear_all_draft(draft_holder, clock);
}

/// Mint a writer pass for `writer`, with or without the draft-queue bypass.
public fun create_pass(
    file: &InnerFile,
    writer: address,
    duration: u64,
    admin_pass: bool,
    ctx: &mut TxContext,
) {
    assert!(file.owner() == ctx.sender(), 1);
    let admin_pass = {
        if (admin_pass) {
            option::some(writer_pass::new_admin_pass(file.owner()))
        } else {
            option::none()
        }
    };

    let pass = writer_pass::new(object::id(file), duration, admin_pass, ctx);

    writer_pass::transfer_to(pass, writer);
}

// === Private functions ===

/// Store `blobs` under `store_to` and record the result as one revision.
fun process_blob(
    system_cfg: &mut SystemConfig,
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
