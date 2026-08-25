/// Holds `InnerFile`: the authoritative head of a mutable document, its bounded
/// rollback window and its known-good fallback.
module warlot::inner_file;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{
    deny_list,
    draft::{Self, Draft, FileDraftHolder},
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
#[error]
const EDraftLimitReached: vector<u8> = b"THIS FILE ALREADY HOLDS AS MANY OPEN DRAFTS AS IT ALLOWS";
#[error]
const EPassRevoked: vector<u8> = b"this pass has been revoked by the file owner";

// === Constants ===

/// The deepest rollback window a file may ask for.
///
/// The window is a vector held inline on a shared object, so every entry is
/// re-serialised through consensus on every write, and every entry is a revision
/// whose content is being paid for. Eight is past the point where a deeper
/// history is worth either cost; the field is a `u8` and used to accept 255.
const MAX_TRACK_BACK: u8 = 8;

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
    /// How many drafts may stand open on this file at once.
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
/// Four conditions, each independent of the others: the pass is for this file,
/// it has not decayed, the writer is not denied, and the pass has not been
/// revoked. A non-decaying pass is exempt from the second and from nothing else
/// ,  its end date is the owner's decision rather than the clock's, and both of
/// the owner's revocations still reach it.
public fun verify_pass(file: &InnerFile, writer: address, writer_pass: &WriterPass, clock: &Clock) {
    assert!(object::id(file) == writer_pass.file_id(), INVALIDPASS);

    let current_time = clock.timestamp_ms();

    assert!(
        writer_pass.is_immortal() || writer_pass.duration() > current_time,
        DECAYEXCEEDED,
    );

    let deny_obj = deny_list::borrow(&file.id);

    if (deny_list::contains(deny_obj, writer)) {
        // A denial recorded with a period of zero holds indefinitely; any other
        // period holds until the clock passes it.
        let user_deny_period = deny_list::period(deny_obj, writer);
        assert!(
            !(user_deny_period == 0 || user_deny_period > current_time),
            INVALIDWRITER,
        );
    };

    assert!(!deny_list::is_pass_revoked(deny_obj, object::id(writer_pass)), EPassRevoked);
}

// === View functions ===

/// The revision the owner designated as known good.
public fun root_change(inner_file: &InnerFile): &FileData {
    inner_file.file_history.root_change.borrow()
}

/// Whether the file already holds a known-good fallback.
public fun has_root_change(inner_file: &InnerFile): bool {
    inner_file.file_history.root_change.is_some()
}

/// Whether the pass `pass_id` has been revoked on this file.
public fun is_pass_revoked(inner_file: &InnerFile, pass_id: ID): bool {
    deny_list::is_pass_revoked(deny_list::borrow(&inner_file.id), pass_id)
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

/// How many drafts may stand open on this file at once.
public fun writers_length(inner_file: &InnerFile): u8 {
    inner_file.writers_length
}

/// The config the fallback names, if the file holds one.
public fun root_change_config(inner_file: &InnerFile): Option<ID> {
    if (inner_file.file_history.root_change.is_none()) {
        return option::none()
    };

    option::some(inner_file.file_history.root_change.borrow().blob_config_id())
}

/// The deepest rollback window a file may ask for.
public fun max_track_back(): u8 { MAX_TRACK_BACK }

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
    assert!(
        track_back_length > 0 && track_back_length <= MAX_TRACK_BACK,
        INVALIDTRACKBACKLENGTH,
    );

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

/// Make `file_data` the newest revision, returning the oldest one if the rollback
/// window was already full.
///
/// The displaced revision comes back rather than being discarded, because it names
/// content that is still stored and still being paid for. What becomes of that
/// content is the caller's to settle; the window's job ends at deciding that the
/// revision no longer belongs to the file.
///
/// The window is bounded at `MAX_TRACK_BACK`, so the shift that keeps index 0 the
/// newest revision moves at most that many entries.
public(package) fun override_file_add(
    inner_file: &mut InnerFile,
    file_data: FileData,
    clock: &Clock,
): Option<FileData> {
    let max_length = inner_file.file_history.track_back_length as u64;
    let current_length = vector::length(&inner_file.file_history.track_back);

    let displaced = if (max_length <= current_length) {
        option::some(inner_file.file_history.track_back.pop_back())
    } else {
        option::none()
    };

    // Index 0 is the newest revision.
    inner_file.file_history.track_back.insert(file_data, 0);
    inner_file.file_history.last_modified = clock.timestamp_ms();

    displaced
}

/// Attach `draft` to the file's queue, refusing it once the file already holds as
/// many open drafts as it allows.
///
/// The cap was declared on the file from the beginning and enforced nowhere, so
/// the queue was a shared structure any pass holder could grow without limit.
public(package) fun pin_draft(inner_file: &mut InnerFile, draft: Draft, clock: &Clock) {
    let cap = inner_file.writers_length as u64;
    let draft_holder = inner_file.get_draft_holder();

    assert!(draft::total_draft(draft_holder) < cap, EDraftLimitReached);

    draft::pin_draft(draft_holder, draft, clock);
}

/// Record the known-good fallback, returning the revision it displaced if there
/// was one.
///
/// `swap_or_fill` rather than `swap`: a file starts with no fallback, so the
/// first call has nothing to displace.
public(package) fun swap_root_change(
    inner_file: &mut InnerFile,
    file_data: FileData,
): Option<FileData> {
    option::swap_or_fill(&mut inner_file.file_history.root_change, file_data)
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
