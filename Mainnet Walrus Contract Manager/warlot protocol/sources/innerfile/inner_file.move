/// Holds `InnerFile`: the authoritative head of a mutable document, its bounded
/// rollback window and its known-good fallback.
module warlot::inner_file;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{
    deny_list,
    draft::{Self, FileDraftHolder},
    file_data::FileData,
    issue::{Self, FileIssueMeta},
    writer_pass::{Self, WriterPass},
};

// === Errors ===

#[error]
const INVALIDWRITER: vector<u8> = b"permission denied";
#[error]
const DECAYEXCEEDED: vector<u8> = b"destroy current pass, and create new pass";
#[error]
const INVALIDPASS: vector<u8> = b"enter valid pass";
#[error]
const INVALIDTRACKBACKLENGTH: vector<u8> = b"provide a valid track back len data";

// === Constants ===

/// Dynamic object field key for the file's draft queue.
const FILEDRAFTKEY: vector<u8> = b"file draft";
/// Dynamic object field key for the file's issue tracker.
const ISSUEKEY: vector<u8> = b"file issue";

// === Structs ===

/// A collaboratively edited document anchored on immutable storage.
public struct InnerFile has key, store {
    id: UID,
    /// The address that may merge drafts and set the fallback.
    owner: address,
    /// How many drafts a writer may hold open at a time.
    writers_length: u8,
    file_history: FileTrack,
    created_at_ms: u64,
}

/// The file's head, its rollback window and its fallback.
public struct FileTrack has store {
    /// A revision the owner has designated as known good, to fall back to when
    /// a collaborator or a remote service has made changes they do not accept.
    root_change: Option<FileData>,
    /// How many revisions the rollback window holds.
    track_back_length: u8,
    /// The storage terms every revision of this file is stored under.
    warlot_state: WarlotState,
    /// The rollback window, newest first.
    track_back: vector<FileData>,
    last_modified: u64,
}

/// The storage terms the file's revisions are stored under.
public struct WarlotState has store {
    epoch_set: u32,
    cycle_end: u64,
}

// === Public functions ===

/// Assert `writer_pass` authorises `writer` to modify this file.
///
/// A writer with no denial recorded, or holding a non-decaying pass, is admitted
/// without further checks; otherwise the pass must not have decayed and the
/// denial must have lapsed.
public fun verify_pass(file: &InnerFile, writer: address, writer_pass: &WriterPass, clock: &Clock) {
    assert!(object::id(file) == writer_pass.file_id(), INVALIDPASS);

    let deny_obj = deny_list::borrow(&file.id);
    if (!deny_list::contains(deny_obj, writer) || writer_pass.is_immortal()) {
        return
    };

    let current_time = clock.timestamp_ms();

    assert!(writer_pass.duration() > current_time, DECAYEXCEEDED);

    let user_deny_period = deny_list::period(deny_obj, writer);
    assert!(
        !(user_deny_period == 0 || user_deny_period > current_time),
        INVALIDWRITER,
    );
}

// === View functions ===

/// The revision the owner designated as known good.
public fun root_change(inner_file: &InnerFile): &FileData {
    inner_file.file_history.root_change.borrow()
}

/// How many revisions the rollback window holds.
public fun track_back_length(inner_file: &InnerFile): u8 {
    inner_file.file_history.track_back_length
}

/// The rollback window, newest first.
public fun track_back(inner_file: &InnerFile): &vector<FileData> {
    &inner_file.file_history.track_back
}

/// The storage terms this file's revisions are stored under.
public fun warlot_state(inner_file: &InnerFile): &WarlotState {
    &inner_file.file_history.warlot_state
}

/// How many epochs ahead this file's blobs are kept paid for.
public fun epoch_set(inner_file: &InnerFile): u32 {
    inner_file.file_history.warlot_state.epoch_set
}

/// How many renewal cycles this file's blobs are bought for.
public fun cycle_end(inner_file: &InnerFile): u64 {
    inner_file.file_history.warlot_state.cycle_end
}

/// The address that may merge drafts and set the fallback.
public fun owner(inner_file: &InnerFile): address {
    inner_file.owner
}

/// How many drafts a writer may hold open at a time.
public fun writers_length(inner_file: &InnerFile): u8 {
    inner_file.writers_length
}

// === Package functions ===

/// Build a file whose rollback window starts at `first_revision`.
public(package) fun new(
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    epoch_set: u32,
    cycle_end: u64,
    first_revision: FileData,
    clock: &Clock,
    ctx: &mut TxContext,
): InnerFile {
    assert!(track_back_length > 0, INVALIDTRACKBACKLENGTH);

    InnerFile {
        id: object::new(ctx),
        owner,
        writers_length,
        file_history: FileTrack {
            root_change: option::none(),
            track_back_length,
            warlot_state: WarlotState {
                epoch_set,
                cycle_end,
            },
            track_back: vector::singleton(first_revision),
            last_modified: clock.timestamp_ms(),
        },
        created_at_ms: clock.timestamp_ms(),
    }
}

/// Attach the deny list, the draft queue and the issue tracker, then share the file.
public(package) fun share(
    mut inner_file: InnerFile,
    draft_epoch_duration: u32,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    deny_list::attach(&mut inner_file.id, ctx);
    ofields::add<vector<u8>, FileDraftHolder>(
        &mut inner_file.id,
        FILEDRAFTKEY,
        draft::create_draft_holder(draft_epoch_duration, ctx),
    );
    ofields::add<vector<u8>, FileIssueMeta>(
        &mut inner_file.id,
        ISSUEKEY,
        issue::create_file_issue_meta(clock, ctx),
    );

    transfer::public_share_object(inner_file);
}

/// The file's UID, so sibling modules can reach the objects attached to it.
public(package) fun uid(inner_file: &InnerFile): &UID {
    &inner_file.id
}

/// Mutable access to the file's UID.
public(package) fun uid_mut(inner_file: &mut InnerFile): &mut UID {
    &mut inner_file.id
}

/// The file's draft queue.
public(package) fun get_draft_holder(inner_file: &mut InnerFile): &mut FileDraftHolder {
    ofields::borrow_mut<vector<u8>, FileDraftHolder>(&mut inner_file.id, FILEDRAFTKEY)
}

/// The file's issue tracker.
public(package) fun get_issue_meta(inner_file: &InnerFile): &FileIssueMeta {
    ofields::borrow<vector<u8>, FileIssueMeta>(&inner_file.id, ISSUEKEY)
}

/// Make `file_data` the newest revision, evicting the oldest once the rollback
/// window is full.
public(package) fun override_file_add(
    inner_file: &mut InnerFile,
    file_data: FileData,
    clock: &Clock,
) {
    let max_length = inner_file.file_history.track_back_length as u64;
    let current_length = vector::length(&inner_file.file_history.track_back);

    if (max_length <= current_length) {
        let _ = inner_file.file_history.track_back.pop_back();
    };

    // Index 0 is the newest revision.
    inner_file.file_history.track_back.insert(file_data, 0);
    inner_file.file_history.last_modified = clock.timestamp_ms();
}

/// Replace the known-good fallback, returning the revision it displaced.
public(package) fun swap_root_change(inner_file: &mut InnerFile, file_data: FileData): FileData {
    option::swap(&mut inner_file.file_history.root_change, file_data)
}

/// Take the known-good fallback out of the file.
public(package) fun extract_root_change(inner_file: &mut InnerFile): FileData {
    option::extract(&mut inner_file.file_history.root_change)
}

/// Mint the non-decaying, draft-bypassing pass a file's owner holds.
public(package) fun new_owner_pass(
    file_id: ID,
    owner: address,
    ctx: &mut TxContext,
): WriterPass {
    writer_pass::new(
        file_id,
        writer_pass::immortal_duration(),
        option::some(writer_pass::new_admin_pass(owner)),
        ctx,
    )
}
