/// Holds proposed inner-file revisions awaiting the owner's merge.
module warlot::draft;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{draft_events, file_data::FileData};

// === Errors ===

#[error]
const INVALIDDRAFT: vector<u8> = b"enter a vaild draft";
#[error]
const INVALIDDRAFTINDEX: vector<u8> = b"enter a valid draft index";
#[error]
const ENoDraftPinned: vector<u8> = b"THIS FILE HAS NEVER HELD A DRAFT";
#[error]
const EInvalidDraftRange: vector<u8> = b"A DRAFT RANGE MUST START BEFORE IT ENDS";

// === Structs ===

/// The drafts pending on one file.
///
/// Unlike the file's own history, whose blobs are custodied by the file owner,
/// a draft's blobs are custodied by the writer who pushed it. The epoch duration
/// exists so a draft does not outlive the branch it belongs to.
public struct FileDraftHolder has key, store {
    id: UID,
    draft_epoch_duration: u32,
    last_modified: u64,
    total_draft: u64,
    /// The next index to assign, so contributors can build on each other's work.
    available_index: u64,
}

/// One proposed revision.
public struct Draft has key, store {
    id: UID,
    /// The pass the writer used to make this draft.
    writer_pass: ID,
    /// The issue this draft resolves, if any.
    issue: Option<ID>,
    file: Option<FileData>,
}

// === View functions ===

/// The pass the writer used to make this draft.
public fun writer_pass(draft: &Draft): ID { draft.writer_pass }

/// The issue this draft resolves, if any.
public fun issue(draft: &Draft): &Option<ID> { &draft.issue }

/// The revision this draft proposes.
public fun file(draft: &Draft): &Option<FileData> { &draft.file }

/// How many drafts stand open on this file.
public fun total_draft(draft_holder: &FileDraftHolder): u64 { draft_holder.total_draft }

/// The index the next draft pinned to this file will take.
public fun available_index(draft_holder: &FileDraftHolder): u64 { draft_holder.available_index }

// === Package functions ===

/// Build an empty draft holder.
public(package) fun create_draft_holder(
    draft_epoch_duration: u32,
    ctx: &mut TxContext,
): FileDraftHolder {
    FileDraftHolder {
        id: object::new(ctx),
        draft_epoch_duration,
        last_modified: 0,
        total_draft: 0,
        available_index: 0,
    }
}

/// Build one proposed revision.
public(package) fun create_draft(
    writer_pass: ID,
    issue: Option<ID>,
    file: Option<FileData>,
    ctx: &mut TxContext,
): Draft {
    Draft {
        id: object::new(ctx),
        writer_pass,
        issue,
        file,
    }
}

/// Attach `draft` to the holder at the next free index.
///
/// The index only ever moves forward, including across deletions, so an index
/// that has been used once never names a different draft later.
public(package) fun pin_draft(
    draft_holder: &mut FileDraftHolder,
    draft: Draft,
    clock: &Clock,
    system_id: ID,
    file_id: ID,
) {
    let old_total_draft = draft_holder.total_draft;
    let available_index_point = draft_holder.available_index;

    let draft_id = object::id(&draft);
    let writer_pass = draft.writer_pass;
    let issue = draft.issue;
    let proposed = draft.file.borrow();
    let commit = proposed.commit();
    let commit_by = proposed.commit_by();
    let blob_config_id = proposed.blob_config_id();

    ofields::add<u64, Draft>(&mut draft_holder.id, available_index_point, draft);

    draft_holder.last_modified = clock.timestamp_ms();
    draft_holder.available_index = available_index_point + 1;
    draft_holder.total_draft = old_total_draft + 1;

    draft_events::emit_draft_pinned(
        system_id,
        file_id,
        draft_id,
        available_index_point,
        writer_pass,
        issue,
        commit,
        commit_by,
        blob_config_id,
        draft_holder.total_draft,
        draft_holder.last_modified,
    );
}

/// Take the revision out of the draft at `draft_index` and delete the draft.
public(package) fun resolve_draft_to_file(
    draft_holder: &mut FileDraftHolder,
    draft_index: u64,
    clock: &Clock,
    system_id: ID,
    file_id: ID,
    merged_by: address,
): FileData {
    assert!(ofields::exists_(&draft_holder.id, draft_index), INVALIDDRAFTINDEX);
    let old_total_draft = draft_holder.total_draft;
    draft_holder.total_draft = old_total_draft - 1;

    draft_holder.last_modified = clock.timestamp_ms();

    let draft = ofields::remove<u64, Draft>(&mut draft_holder.id, draft_index);
    let Draft { id, writer_pass: _, issue: _, file } = draft;
    id.delete();

    let accepted = option::destroy_some(file);

    draft_events::emit_draft_merged(
        system_id,
        file_id,
        draft_index,
        merged_by,
        accepted.commit(),
        accepted.blob_config_id(),
        draft_holder.total_draft,
        draft_holder.last_modified,
    );

    accepted
}

/// Take the revision out of the most recently pinned draft and delete it.
///
/// "Latest" is the highest index ever assigned, not the highest index still
/// present, so this aborts rather than reaching further back if that draft has
/// already been resolved or deleted. Naming the index is the way to reach the
/// others; guessing on the caller's behalf would merge content nobody asked for.
public(package) fun fetch_and_delete_latest_draft(
    draft_holder: &mut FileDraftHolder,
    clock: &Clock,
    system_id: ID,
    file_id: ID,
    merged_by: address,
): FileData {
    assert!(draft_holder.available_index > 0, ENoDraftPinned);

    let latest = draft_holder.available_index - 1;
    resolve_draft_to_file(
        draft_holder,
        latest,
        clock,
        system_id,
        file_id,
        merged_by,
    )
}

/// Mutable access to one draft.
public(package) fun get_draft(draft_holder: &mut FileDraftHolder, draft: u64): &mut Draft {
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    ofields::borrow_mut<u64, Draft>(&mut draft_holder.id, draft)
}

/// Delete one draft, returning the revision it proposed.
public(package) fun delete_draft(
    draft_holder: &mut FileDraftHolder,
    draft: u64,
    clock: &Clock,
    system_id: ID,
    file_id: ID,
    deleted_by: address,
): Option<FileData> {
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    let draft_obj = ofields::remove<u64, Draft>(&mut draft_holder.id, draft);
    let Draft { id, writer_pass: _, issue: _, file } = draft_obj;
    id.delete();
    draft_holder.last_modified = clock.timestamp_ms();
    let old_total_draft = draft_holder.total_draft;
    draft_holder.total_draft = old_total_draft - 1;

    draft_events::emit_draft_deleted(
        system_id,
        file_id,
        draft,
        deleted_by,
        draft_holder.total_draft,
        draft_holder.last_modified,
    );

    file
}

/// Delete every draft this file holds in `[from_index, to_index)`, returning the
/// revisions they proposed.
///
/// The range is the caller's, so one call costs what the caller asked it to cost.
/// The previous form walked every index the file had ever issued, which meant a
/// file that had accumulated enough drafts could never clear them again ,  and
/// those drafts were then stuck for good, since clearing was the only way out.
public(package) fun clear_drafts(
    draft_holder: &mut FileDraftHolder,
    from_index: u64,
    to_index: u64,
    clock: &Clock,
    system_id: ID,
    file_id: ID,
    deleted_by: address,
): vector<FileData> {
    assert!(from_index < to_index, EInvalidDraftRange);

    let mut revisions = vector<FileData>[];
    let mut i = from_index;

    while (i < to_index) {
        if (ofields::exists_(&draft_holder.id, i)) {
            let proposed = delete_draft(draft_holder, i, clock, system_id, file_id, deleted_by);
            revisions.push_back(option::destroy_some(proposed));
        };
        i = i + 1;
    };

    draft_holder.last_modified = clock.timestamp_ms();

    revisions
}
