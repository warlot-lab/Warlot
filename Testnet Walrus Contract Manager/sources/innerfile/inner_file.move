/// Holds `InnerFile`: the authoritative head of a mutable document, its bounded
/// rollback window and its known-good fallback.
module warlot::inner_file;

// === Imports ===

use sui::{clock::Clock, dynamic_object_field as ofields};
use warlot::{
    credential::Credential,
    deny_list,
    draft::{Self, Draft, FileDraftHolder},
    file_data::FileData,
    innerfile_events,
    operator::{Self, OperatorAuth},
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
#[error]
const EOperatorsRefused: vector<u8> = b"THIS FILE'S OWNER DOES NOT ADMIT SYSTEM OPERATORS";
#[error]
const ENoDraftQueue: vector<u8> = b"THIS FILE HAS NEVER HELD A DRAFT";

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

// === Structs ===

/// A collaboratively edited document anchored on immutable storage.
public struct InnerFile has key, store {
    id: UID,
    /// The address that may merge drafts and set the fallback.
    owner: address,
    /// How many drafts may stand open on this file at once.
    writers_length: u8,
    /// Whether a system operator's credential may write this file at all.
    ///
    /// Set by the owner and by nobody else, and gated on the sender rather than
    /// on a pass: a pass that could flip it would let an operator re-admit
    /// itself. The account-level grant of the operator role has already happened
    /// by the time a file exists, so this is the pin that shuts one file against
    /// it.
    operators_allowed: bool,
    /// Whether a system operator's writes may go straight into this file's
    /// history rather than into the draft queue.
    ///
    /// Both this and the operator's own slot have to carry the bypass for a write
    /// to skip the queue. The owner wins: an admin granting bypass on the slot
    /// cannot override a file whose owner refused it here.
    operators_may_bypass_draft: bool,
    /// How many epochs a draft on this file lives for.
    ///
    /// Held here rather than only on the queue, because the queue is built on the
    /// first draft and the terms have to survive until then.
    draft_epoch_duration: u32,
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

    assert_not_refused(file, writer, object::id(writer_pass), current_time);
}

/// Assert an operator credential authorises `writer` to modify this file.
///
/// Sibling to `verify_pass`, and deliberately not a replacement for it. Three
/// conditions rather than four: there is no "is this pass for this file" check,
/// because a capability names a system and not a file, and the file-level answer
/// is `operators_allowed` instead. The other two are the same record read the
/// same way ,  the owner's denial of an address reaches a capability holder
/// exactly as it reaches a pass holder, and the revoked-id space the deny list
/// keeps is keyed by `ID` and does not care which kind of object an id names.
///
/// The credential's own expiry and its right to act for this account are settled
/// before this is reached: `operator::authorise` against the system's set, and
/// the operator role against the account owner's grant.
public fun verify_operator(
    file: &InnerFile,
    writer: address,
    auth: &OperatorAuth,
    clock: &Clock,
) {
    assert!(file.operators_allowed, EOperatorsRefused);

    assert_not_refused(file, writer, auth.auth_cap_id(), clock.timestamp_ms());
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

/// Whether the pass or capability `pass_id` has been revoked on this file.
public fun is_pass_revoked(inner_file: &InnerFile, pass_id: ID): bool {
    if (!deny_list::attached(&inner_file.id)) return false;

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

/// When the rollback window last took a new revision.
public fun last_modified(inner_file: &InnerFile): u64 {
    inner_file.file_history.last_modified
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

/// Whether a system operator's credential may write this file at all.
public fun operators_allowed(inner_file: &InnerFile): bool { inner_file.operators_allowed }

/// Whether a system operator's writes may skip this file's draft queue.
public fun operators_may_bypass_draft(inner_file: &InnerFile): bool {
    inner_file.operators_may_bypass_draft
}

/// How many epochs a draft on this file lives for.
public fun draft_epoch_duration(inner_file: &InnerFile): u32 { inner_file.draft_epoch_duration }

/// Whether this file holds a draft queue yet.
public fun has_draft_queue(inner_file: &InnerFile): bool {
    ofields::exists_<vector<u8>>(&inner_file.id, FILEDRAFTKEY)
}

/// Whether this file holds a deny list yet.
public fun has_deny_list(inner_file: &InnerFile): bool {
    deny_list::attached(&inner_file.id)
}

/// The deepest rollback window a file may ask for.
public fun max_track_back(): u8 { MAX_TRACK_BACK }

// === Test-only helpers ===

#[test_only]
/// When this file was created.
public fun created_at_ms(inner_file: &InnerFile): u64 {
    inner_file.created_at_ms
}

// === Package functions ===

/// Build a file whose rollback window starts at `first_revision`.
public(package) fun new(
    owner: address,
    writers_length: u8,
    track_back_length: u8,
    epoch_set: u32,
    cycle_end: u64,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    draft_epoch_duration: u32,
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
        operators_allowed,
        operators_may_bypass_draft,
        draft_epoch_duration,
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

/// Share the file.
///
/// The deny list and the draft queue are no longer built here. Both are dynamic
/// object fields ,  two objects each, counting the field entry ,  and most files
/// never deny anybody and never take a draft. They are attached by the first call
/// that puts something in them, which is a change to when they are created and to
/// nothing else about them.
public(package) fun share(inner_file: InnerFile, system_id: ID) {
    // Announced at the share rather than at construction, because a file that is
    // never shared is a file nobody can reach.
    let first_revision = &inner_file.file_history.track_back[0];

    innerfile_events::emit_inner_file_created(
        system_id,
        object::id(&inner_file),
        inner_file.owner,
        first_revision.commit_by(),
        inner_file.writers_length,
        inner_file.file_history.track_back_length,
        inner_file.file_history.warlot_state.epoch_set,
        inner_file.file_history.warlot_state.cycle_end,
        inner_file.draft_epoch_duration,
        inner_file.operators_allowed,
        inner_file.operators_may_bypass_draft,
        inner_file.created_at_ms,
        first_revision.commit(),
        first_revision.blob_config_id(),
    );

    transfer::public_share_object(inner_file);
}

/// Replace both operator bits, and announce them.
///
/// Wholesale rather than one at a time, the same way an address delegation is
/// set, so one call always leaves the file holding exactly what the owner named.
/// The caller is responsible for the owner check ,  it is made at the entry
/// point, against the sender.
public(package) fun set_operator_policy(
    inner_file: &mut InnerFile,
    operators_allowed: bool,
    operators_may_bypass_draft: bool,
    system_id: ID,
    set_by: address,
) {
    inner_file.operators_allowed = operators_allowed;
    inner_file.operators_may_bypass_draft = operators_may_bypass_draft;

    innerfile_events::emit_file_operator_policy_set(
        system_id,
        object::id(inner_file),
        operators_allowed,
        operators_may_bypass_draft,
        set_by,
    );
}

/// The file's UID, so sibling modules can reach the objects attached to it.
public(package) fun uid(inner_file: &InnerFile): &UID {
    &inner_file.id
}

/// Mutable access to the file's UID.
public(package) fun uid_mut(inner_file: &mut InnerFile): &mut UID {
    &mut inner_file.id
}

/// The file's draft queue, or an abort if it has never held a draft.
///
/// The four calls that resolve or drop drafts reach for this. A file with no
/// queue has no draft to resolve, so refusing by name here says the same thing
/// the index lookup used to say and says it one step earlier.
public(package) fun get_draft_holder(inner_file: &mut InnerFile): &mut FileDraftHolder {
    assert!(ofields::exists_<vector<u8>>(&inner_file.id, FILEDRAFTKEY), ENoDraftQueue);

    ofields::borrow_mut<vector<u8>, FileDraftHolder>(&mut inner_file.id, FILEDRAFTKEY)
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
public(package) fun pin_draft(
    inner_file: &mut InnerFile,
    draft: Draft,
    credential: Credential,
    clock: &Clock,
    system_id: ID,
    ctx: &mut TxContext,
) {
    let cap = inner_file.writers_length as u64;
    let file_id = object::id(inner_file);
    let draft_epoch_duration = inner_file.draft_epoch_duration;

    if (!ofields::exists_<vector<u8>>(&inner_file.id, FILEDRAFTKEY)) {
        ofields::add<vector<u8>, FileDraftHolder>(
            &mut inner_file.id,
            FILEDRAFTKEY,
            draft::create_draft_holder(draft_epoch_duration, ctx),
        );
    };

    let draft_holder = inner_file.get_draft_holder();

    assert!(draft::total_draft(draft_holder) < cap, EDraftLimitReached);

    draft::pin_draft(draft_holder, draft, credential, clock, system_id, file_id);
}

/// Record the known-good fallback, returning the revision it displaced if there
/// was one.
///
/// `swap_or_fill` rather than `swap`: a file starts with no fallback, so the
/// first call has nothing to displace.
public(package) fun swap_root_change(
    inner_file: &mut InnerFile,
    file_data: FileData,
    system_id: ID,
): Option<FileData> {
    let file_id = object::id(inner_file);
    let previous_blob_config = inner_file.root_change_config();

    let commit = file_data.commit();
    let commit_by = file_data.commit_by();
    let blob_config_id = file_data.blob_config_id();

    let displaced = option::swap_or_fill(&mut inner_file.file_history.root_change, file_data);

    innerfile_events::emit_root_change_set(
        system_id,
        file_id,
        commit,
        commit_by,
        blob_config_id,
        previous_blob_config,
    );

    displaced
}

/// Take the known-good fallback out of the file.
public(package) fun extract_root_change(
    inner_file: &mut InnerFile,
    system_id: ID,
    removed_by: address,
): FileData {
    let file_id = object::id(inner_file);
    let removed = option::extract(&mut inner_file.file_history.root_change);

    // Distinct from the revision retirement that follows it: a retirement fires
    // wherever a revision loses its last reference, so on its own it cannot say
    // whether the file still has a fallback.
    innerfile_events::emit_root_change_removed(system_id, file_id, removed.blob_config_id(), removed_by);

    removed
}

/// Mint the non-decaying, draft-bypassing pass a file's owner holds.
public(package) fun new_owner_pass(file_id: ID, ctx: &mut TxContext): WriterPass {
    writer_pass::new(file_id, writer_pass::immortal_duration(), true, ctx)
}

// === Private functions ===

/// Abort if the file's owner has refused `writer`, or has revoked `credential_id`.
///
/// The half of a credential check that does not depend on which kind of
/// credential was presented. A file that has never denied anybody and never
/// revoked anything holds no deny list at all, and refuses nobody.
fun assert_not_refused(file: &InnerFile, writer: address, credential_id: ID, now_ms: u64) {
    if (!deny_list::attached(&file.id)) return;

    let deny_obj = deny_list::borrow(&file.id);

    if (deny_list::contains(deny_obj, writer)) {
        // A denial recorded with a period of zero holds indefinitely; any other
        // period holds until the clock passes it.
        let user_deny_period = deny_list::period(deny_obj, writer);
        assert!(
            !(user_deny_period == 0 || user_deny_period > now_ms),
            INVALIDWRITER,
        );
    };

    assert!(!deny_list::is_pass_revoked(deny_obj, credential_id), EPassRevoked);
}
