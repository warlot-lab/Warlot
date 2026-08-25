/// Settles the revisions a file stops referencing.
module warlot::eviction;

// === Imports ===

use sui::clock::Clock;
use warlot::{
    blob_config::{Self, BlobConfig},
    events,
    file_data::{Self, FileData},
    inner_file::InnerFile,
};

// === Errors ===

#[error]
const EWrongConfig: vector<u8> = b"THIS CONFIG IS NOT THE ONE THE RETIRED REVISION NAMES";
#[error]
const EEvictedConfigRequired: vector<u8> =
    b"THIS WRITE PUSHES A REVISION OUT OF THE WINDOW; PASS THE CONFIG IT NAMES";
#[error]
const EUnexpectedConfig: vector<u8> = b"THIS CALL RETIRES NO CONTENT, SO IT TAKES NO CONFIG";

// === Package functions ===

/// Make `revision` the file's newest, and settle whatever it pushed out.
///
/// A revision leaving the rollback window is the last on-chain reference to
/// content that is stored and being paid for, so the caller has to say what
/// becomes of it. `evicted` is empty when the window still had room, and holds
/// exactly the displaced revision's config when it did not ,  a mismatch is
/// refused by name rather than being silently absorbed.
///
/// The one exception is a revision the fallback still names. The file has given up
/// the revision, not the state it can roll back to, so that content stays where it
/// is and no config is taken.
public(package) fun advance_history(
    inner_file: &mut InnerFile,
    revision: FileData,
    evicted: vector<BlobConfig>,
    clock: &Clock,
) {
    let file_id = object::id(inner_file);
    let fallback = inner_file.root_change_config();

    let displaced = inner_file.override_file_add(revision, clock);

    if (displaced.is_none()) {
        displaced.destroy_none();
        assert_no_config(evicted);
        return
    };

    let retired = displaced.destroy_some();
    let still_the_fallback =
        fallback.is_some() && *fallback.borrow() == retired.blob_config_id();

    if (still_the_fallback) {
        assert_no_config(evicted);
        discard(retired, file_id);
        return
    };

    let mut evicted = evicted;
    assert!(evicted.length() == 1, EEvictedConfigRequired);
    release(retired, evicted.pop_back(), file_id);
    evicted.destroy_empty();
}

/// Abort unless `configs` is empty, and consume it.
///
/// A config that arrives where nothing is being retired cannot simply be ignored:
/// it has no `drop`, so the alternatives are to consume it ,  which would mean
/// destroying content the caller never asked to destroy ,  or to refuse the call.
public(package) fun assert_no_config(configs: vector<BlobConfig>) {
    assert!(configs.is_empty(), EUnexpectedConfig);
    configs.destroy_empty();
}

/// Retire `revision` and hand the content it named back to the address that owns
/// it, destroying the config.
///
/// `config` must be the one `revision` names. Without that check the caller would
/// be choosing which config to consume rather than being handed one, and a file
/// owner could retire content belonging to a file they have nothing to do with.
public(package) fun release(revision: FileData, config: BlobConfig, file_id: ID): ID {
    let (commit, commit_by, blob_config_id) = file_data::destroy(revision);
    assert!(object::id(&config) == blob_config_id, EWrongConfig);

    let (owner, blobs) = blob_config::unwrap_for_owner(config);
    blobs.do!(|blob| transfer::public_transfer(blob, owner));

    events::emit_revision_retired(file_id, blob_config_id, commit, commit_by, true);

    blob_config_id
}

/// Retire `revision` and leave its content where it is.
///
/// Used where somebody other than the file still has a claim on the config: a
/// draft the owner rejected is still the writer's, and a fallback the file gives
/// up is still reachable by the file's owner through withdrawal. The event is the
/// whole point ,  it publishes the config id at the moment the last reference to
/// it disappears, so the party who owns it can act on it.
public(package) fun discard(revision: FileData, file_id: ID): ID {
    let (commit, commit_by, blob_config_id) = file_data::destroy(revision);

    events::emit_revision_retired(file_id, blob_config_id, commit, commit_by, false);

    blob_config_id
}
