/// Merges, rejects and clears the drafts standing open on an inner file.
module warlot::entry_file_draft;

// === Imports ===

use sui::clock::Clock;
use warlot::{
    blob_config::{Self, BlobConfig},
    draft,
    eviction,
    file_data::FileData,
    inner_file::InnerFile,
    system_config::SystemConfig,
    writer_pass::WriterPass,
};

// === Errors ===

#[error]
const INVALIDACCESS: vector<u8> = b"Invalid access";
#[error]
const EWrongDraftConfig: vector<u8> = b"THIS CONFIG IS NOT THE ONE THE MERGED DRAFT NAMES";

// === Public functions ===

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
