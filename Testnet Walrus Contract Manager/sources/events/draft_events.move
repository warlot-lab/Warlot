/// Declares the events a file's draft queue raises: a revision proposed, accepted
/// or dropped.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::draft_events;

// === Imports ===

use sui::event;

// === Events ===

/// A proposed revision was pinned to a file's draft queue.
public struct DraftPinned has copy, drop, store {
    system_id: ID,
    file_id: ID,
    draft_id: ID,
    draft_index: u64,
    writer_pass: ID,
    issue: Option<ID>,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    /// How many drafts stand open on the file after the change.
    total_draft: u64,
    last_modified: u64,
}

/// A draft was accepted into the file's history.
public struct DraftMerged has copy, drop, store {
    system_id: ID,
    file_id: ID,
    draft_index: u64,
    merged_by: address,
    commit: vector<u8>,
    blob_config_id: ID,
    total_draft: u64,
    last_modified: u64,
}

/// A draft was dropped without being accepted.
public struct DraftDeleted has copy, drop, store {
    system_id: ID,
    file_id: ID,
    draft_index: u64,
    deleted_by: address,
    total_draft: u64,
    last_modified: u64,
}

// === Package functions ===

/// Announce a draft pinned to a file's queue.
public(package) fun emit_draft_pinned(
    system_id: ID,
    file_id: ID,
    draft_id: ID,
    draft_index: u64,
    writer_pass: ID,
    issue: Option<ID>,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    total_draft: u64,
    last_modified: u64,
) {
    event::emit(DraftPinned {
        system_id,
        file_id,
        draft_id,
        draft_index,
        writer_pass,
        issue,
        commit,
        commit_by,
        blob_config_id,
        total_draft,
        last_modified,
    })
}

/// Announce a draft accepted into a file's history.
public(package) fun emit_draft_merged(
    system_id: ID,
    file_id: ID,
    draft_index: u64,
    merged_by: address,
    commit: vector<u8>,
    blob_config_id: ID,
    total_draft: u64,
    last_modified: u64,
) {
    event::emit(DraftMerged {
        system_id,
        file_id,
        draft_index,
        merged_by,
        commit,
        blob_config_id,
        total_draft,
        last_modified,
    })
}

/// Announce a dropped draft.
public(package) fun emit_draft_deleted(
    system_id: ID,
    file_id: ID,
    draft_index: u64,
    deleted_by: address,
    total_draft: u64,
    last_modified: u64,
) {
    event::emit(DraftDeleted {
        system_id,
        file_id,
        draft_index,
        deleted_by,
        total_draft,
        last_modified,
    })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `DraftPinned`, in declaration order.
public fun read_draft_pinned(e: &DraftPinned): (
    ID,
    ID,
    ID,
    u64,
    ID,
    Option<ID>,
    vector<u8>,
    address,
    ID,
    u64,
    u64,
) {
    let DraftPinned {
        system_id: _system_id,
        file_id: _file_id,
        draft_id: _draft_id,
        draft_index: _draft_index,
        writer_pass: _writer_pass,
        issue: _issue,
        commit: _commit,
        commit_by: _commit_by,
        blob_config_id: _blob_config_id,
        total_draft: _total_draft,
        last_modified: _last_modified,
    } = e;

    (
        *_system_id,
        *_file_id,
        *_draft_id,
        *_draft_index,
        *_writer_pass,
        *_issue,
        *_commit,
        *_commit_by,
        *_blob_config_id,
        *_total_draft,
        *_last_modified,
    )
}

#[test_only]
/// Every field of `DraftMerged`, in declaration order.
public fun read_draft_merged(e: &DraftMerged): (ID, ID, u64, address, vector<u8>, ID, u64, u64) {
    let DraftMerged {
        system_id: _system_id,
        file_id: _file_id,
        draft_index: _draft_index,
        merged_by: _merged_by,
        commit: _commit,
        blob_config_id: _blob_config_id,
        total_draft: _total_draft,
        last_modified: _last_modified,
    } = e;

    (
        *_system_id,
        *_file_id,
        *_draft_index,
        *_merged_by,
        *_commit,
        *_blob_config_id,
        *_total_draft,
        *_last_modified,
    )
}

#[test_only]
/// Every field of `DraftDeleted`, in declaration order.
public fun read_draft_deleted(e: &DraftDeleted): (ID, ID, u64, address, u64, u64) {
    let DraftDeleted {
        system_id: _system_id,
        file_id: _file_id,
        draft_index: _draft_index,
        deleted_by: _deleted_by,
        total_draft: _total_draft,
        last_modified: _last_modified,
    } = e;

    (*_system_id, *_file_id, *_draft_index, *_deleted_by, *_total_draft, *_last_modified)
}
