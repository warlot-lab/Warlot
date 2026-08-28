/// Declares the events an inner file's own history raises: its creation, its head,
/// the revisions it lets go, and its known-good fallback.
///
/// Structs and emitters only ,  this module imports nothing from the rest of the
/// package, so it can never take part in an import cycle and every domain module
/// is free to announce from the point of state change.
///
/// Every event type the protocol raises is declared under `sources/events/`, and
/// nowhere else. One package-scoped event-type filter therefore returns the whole
/// stream, however many modules declare into it. `docs/events.md` records the
/// filter shapes that hold that promise and the ones that no longer do.
module warlot::innerfile_events;

// === Imports ===

use sui::event;

// === Events ===

/// A file was created and shared, with its first revision already in the window.
public struct InnerFileCreated has copy, drop, store {
    system_id: ID,
    file_id: ID,
    owner: address,
    created_by: address,
    writers_length: u8,
    track_back_length: u8,
    epoch_set: u32,
    cycle_end: u64,
    draft_epoch_duration: u32,
    /// Whether a system operator's credential may write this file at all.
    operators_allowed: bool,
    /// Whether a system operator's writes may skip this file's draft queue.
    operators_may_bypass_draft: bool,
    created_at_ms: u64,
    commit: vector<u8>,
    blob_config_id: ID,
}

/// A file's owner replaced both operator bits.
public struct FileOperatorPolicySet has copy, drop, store {
    system_id: ID,
    file_id: ID,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    set_by: address,
}

/// A revision became the file's head.
public struct HeadAdvanced has copy, drop, store {
    system_id: ID,
    file_id: ID,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    /// The head this one displaced.
    previous_commit: vector<u8>,
    previous_blob_config: ID,
    /// How many revisions the rollback window holds after the write.
    window_depth: u64,
    last_modified: u64,
}

/// A revision stopped being referenced by the file that held it.
///
/// `released` distinguishes the two outcomes: the revision's content was handed
/// back to its owner and the config destroyed, or the config was left alive
/// because someone else still holds a claim on it ,  a draft's author, or the
/// file's own fallback. The config id is carried either way, because it is the
/// only handle on content that has just lost its last on-chain reference.
public struct RevisionRetired has copy, drop, store {
    system_id: ID,
    file_id: ID,
    blob_config: ID,
    commit: vector<u8>,
    commit_by: address,
    released: bool,
}

/// A revision was recorded as the file's known-good fallback.
public struct RootChangeSet has copy, drop, store {
    system_id: ID,
    file_id: ID,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    /// The fallback this one replaced, if the file held one.
    previous_blob_config: Option<ID>,
}

/// A file gave up its known-good fallback.
public struct RootChangeRemoved has copy, drop, store {
    system_id: ID,
    file_id: ID,
    blob_config_id: ID,
    removed_by: address,
}

// === Package functions ===

/// Announce a newly shared file.
public(package) fun emit_inner_file_created(
    system_id: ID,
    file_id: ID,
    owner: address,
    created_by: address,
    writers_length: u8,
    track_back_length: u8,
    epoch_set: u32,
    cycle_end: u64,
    draft_epoch_duration: u32,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    created_at_ms: u64,
    commit: vector<u8>,
    blob_config_id: ID,
) {
    event::emit(InnerFileCreated {
        system_id,
        file_id,
        owner,
        created_by,
        writers_length,
        track_back_length,
        epoch_set,
        cycle_end,
        draft_epoch_duration,
        operators_allowed,
        operators_may_bypass_draft,
        created_at_ms,
        commit,
        blob_config_id,
    })
}

/// Announce a file's operator bits being replaced.
public(package) fun emit_file_operator_policy_set(
    system_id: ID,
    file_id: ID,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    set_by: address,
) {
    event::emit(FileOperatorPolicySet {
        system_id,
        file_id,
        operators_allowed,
        operators_may_bypass_draft,
        set_by,
    })
}

/// Announce a new head revision.
public(package) fun emit_head_advanced(
    system_id: ID,
    file_id: ID,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    previous_commit: vector<u8>,
    previous_blob_config: ID,
    window_depth: u64,
    last_modified: u64,
) {
    event::emit(HeadAdvanced {
        system_id,
        file_id,
        commit,
        commit_by,
        blob_config_id,
        previous_commit,
        previous_blob_config,
        window_depth,
        last_modified,
    })
}

/// Announce a revision leaving the file that held it.
public(package) fun emit_revision_retired(
    system_id: ID,
    file_id: ID,
    blob_config: ID,
    commit: vector<u8>,
    commit_by: address,
    released: bool,
) {
    event::emit(RevisionRetired {
        system_id,
        file_id,
        blob_config,
        commit,
        commit_by,
        released,
    })
}

/// Announce a newly recorded fallback.
public(package) fun emit_root_change_set(
    system_id: ID,
    file_id: ID,
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
    previous_blob_config: Option<ID>,
) {
    event::emit(RootChangeSet {
        system_id,
        file_id,
        commit,
        commit_by,
        blob_config_id,
        previous_blob_config,
    })
}

/// Announce a dropped fallback.
public(package) fun emit_root_change_removed(
    system_id: ID,
    file_id: ID,
    blob_config_id: ID,
    removed_by: address,
) {
    event::emit(RootChangeRemoved { system_id, file_id, blob_config_id, removed_by })
}

// === Test-only readers ===

// One reader per event, returning every field in declaration order. A test that
// rebuilds state from the stream has to bind or discard each field explicitly,
// so a field the reconstruction ignores is visible at the call site rather than
// absent from it.

#[test_only]
/// Every field of `InnerFileCreated`, in declaration order.
public fun read_inner_file_created(e: &InnerFileCreated): (
    ID,
    ID,
    address,
    address,
    u8,
    u8,
    u32,
    u64,
    u32,
    bool,
    bool,
    u64,
    vector<u8>,
    ID,
) {
    let InnerFileCreated {
        system_id: _system_id,
        file_id: _file_id,
        owner: _owner,
        created_by: _created_by,
        writers_length: _writers_length,
        track_back_length: _track_back_length,
        epoch_set: _epoch_set,
        cycle_end: _cycle_end,
        draft_epoch_duration: _draft_epoch_duration,
        operators_allowed: _operators_allowed,
        operators_may_bypass_draft: _operators_may_bypass_draft,
        created_at_ms: _created_at_ms,
        commit: _commit,
        blob_config_id: _blob_config_id,
    } = e;

    (
        *_system_id,
        *_file_id,
        *_owner,
        *_created_by,
        *_writers_length,
        *_track_back_length,
        *_epoch_set,
        *_cycle_end,
        *_draft_epoch_duration,
        *_operators_allowed,
        *_operators_may_bypass_draft,
        *_created_at_ms,
        *_commit,
        *_blob_config_id,
    )
}

#[test_only]
/// Every field of `HeadAdvanced`, in declaration order.
public fun read_head_advanced(e: &HeadAdvanced): (
    ID,
    ID,
    vector<u8>,
    address,
    ID,
    vector<u8>,
    ID,
    u64,
    u64,
) {
    let HeadAdvanced {
        system_id: _system_id,
        file_id: _file_id,
        commit: _commit,
        commit_by: _commit_by,
        blob_config_id: _blob_config_id,
        previous_commit: _previous_commit,
        previous_blob_config: _previous_blob_config,
        window_depth: _window_depth,
        last_modified: _last_modified,
    } = e;

    (
        *_system_id,
        *_file_id,
        *_commit,
        *_commit_by,
        *_blob_config_id,
        *_previous_commit,
        *_previous_blob_config,
        *_window_depth,
        *_last_modified,
    )
}

#[test_only]
/// Every field of `RevisionRetired`, in declaration order.
public fun read_revision_retired(e: &RevisionRetired): (ID, ID, ID, vector<u8>, address, bool) {
    let RevisionRetired {
        system_id: _system_id,
        file_id: _file_id,
        blob_config: _blob_config,
        commit: _commit,
        commit_by: _commit_by,
        released: _released,
    } = e;

    (*_system_id, *_file_id, *_blob_config, *_commit, *_commit_by, *_released)
}

#[test_only]
/// Every field of `RootChangeSet`, in declaration order.
public fun read_root_change_set(e: &RootChangeSet): (ID, ID, vector<u8>, address, ID, Option<ID>) {
    let RootChangeSet {
        system_id: _system_id,
        file_id: _file_id,
        commit: _commit,
        commit_by: _commit_by,
        blob_config_id: _blob_config_id,
        previous_blob_config: _previous_blob_config,
    } = e;

    (*_system_id, *_file_id, *_commit, *_commit_by, *_blob_config_id, *_previous_blob_config)
}

#[test_only]
/// Every field of `RootChangeRemoved`, in declaration order.
public fun read_root_change_removed(e: &RootChangeRemoved): (ID, ID, ID, address) {
    let RootChangeRemoved {
        system_id: _system_id,
        file_id: _file_id,
        blob_config_id: _blob_config_id,
        removed_by: _removed_by,
    } = e;

    (*_system_id, *_file_id, *_blob_config_id, *_removed_by)
}

#[test_only]
/// Every field of `FileOperatorPolicySet`, in declaration order.
public fun read_file_operator_policy_set(e: &FileOperatorPolicySet): (
    ID,
    ID,
    bool,
    bool,
    address,
) {
    let FileOperatorPolicySet {
        system_id: _system_id,
        file_id: _file_id,
        operators_allowed: _operators_allowed,
        operators_may_bypass_draft: _operators_may_bypass_draft,
        set_by: _set_by,
    } = e;

    (
        *_system_id,
        *_file_id,
        *_operators_allowed,
        *_operators_may_bypass_draft,
        *_set_by,
    )
}
