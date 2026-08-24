/// Holds proposed inner-file revisions awaiting the owner's merge.
module warlot::draft;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::file_data::FileData;

// === Errors ===

#[error]
const INVALIDDRAFT: vector<u8> = b"enter a vaild draft";
#[error]
const INVALIDDRAFTINDEX: vector<u8> = b"enter a valid draft index";

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
public(package) fun pin_draft(draft_holder: &mut FileDraftHolder, draft: Draft, clock: &Clock) {
    let old_total_draft = draft_holder.total_draft;
    let available_index_point = draft_holder.available_index;
    ofields::add<u64, Draft>(&mut draft_holder.id, available_index_point, draft);

    draft_holder.last_modified = clock.timestamp_ms();
    draft_holder.available_index = available_index_point + 1;
    draft_holder.total_draft = old_total_draft + 1;
}

/// Take the revision out of the draft at `draft_index` and delete the draft.
public(package) fun resolve_draft_to_file(
    draft_holder: &mut FileDraftHolder,
    draft_index: u64,
    clock: &Clock,
): FileData {
    assert!(ofields::exists_(&draft_holder.id, draft_index), INVALIDDRAFTINDEX);
    let old_total_draft = draft_holder.total_draft;
    draft_holder.total_draft = old_total_draft - 1;

    draft_holder.last_modified = clock.timestamp_ms();

    let draft = ofields::remove<u64, Draft>(&mut draft_holder.id, draft_index);
    let Draft { id, writer_pass: _, issue: _, file } = draft;
    id.delete();
    option::destroy_some(file)
}

/// Take the revision out of the most recently pinned draft and delete it.
public(package) fun fetch_and_delete_latest_draft(
    draft_holder: &mut FileDraftHolder,
    clock: &Clock,
): FileData {
    let latest = draft_holder.available_index - 1;
    resolve_draft_to_file(
        draft_holder,
        latest,
        clock,
    )
}

/// Mutable access to one draft.
public(package) fun get_draft(draft_holder: &mut FileDraftHolder, draft: u64): &mut Draft {
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    ofields::borrow_mut<u64, Draft>(&mut draft_holder.id, draft)
}

/// Delete one draft and the revision it proposed.
public(package) fun delete_draft(draft_holder: &mut FileDraftHolder, draft: u64, clock: &Clock) {
    assert!(ofields::exists_(&draft_holder.id, draft), INVALIDDRAFT);
    let draft_obj = ofields::remove<u64, Draft>(&mut draft_holder.id, draft);
    let Draft { id, writer_pass: _, issue: _, file: _ } = draft_obj;
    id.delete();
    draft_holder.last_modified = clock.timestamp_ms();
    let old_total_draft = draft_holder.total_draft;
    draft_holder.total_draft = old_total_draft - 1;
}

/// Delete every draft on this file and reset the holder.
public(package) fun clear_all_draft(draft_holder: &mut FileDraftHolder, clock: &Clock) {
    let mut i: u64 = 0;
    while (i < draft_holder.available_index) {
        if (ofields::exists_(&draft_holder.id, i)) {
            delete_draft(draft_holder, i, clock)
        };
        i = i + 1;
    };

    draft_holder.last_modified = clock.timestamp_ms();
    draft_holder.available_index = 0;
    draft_holder.total_draft = 0;
}
