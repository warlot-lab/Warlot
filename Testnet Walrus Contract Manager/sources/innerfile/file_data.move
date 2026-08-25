/// Represents one revision of an inner file: its commit, its author and its blob config.
module warlot::file_data;

// === Imports ===

use warlot::commit;

// === Structs ===

/// One recorded change to an inner file.
///
/// Deliberately without `drop`. A revision names a `BlobConfig` holding paid-for
/// content, so a revision that fell out of scope unnoticed was content nobody
/// could reach and the renewal service kept paying for. Every place a revision
/// stops being referenced now has to say what became of its content, because the
/// only way to be rid of the value is to unpack it.
public struct FileData has store {
    /// The commitment to the content at this revision, exactly 32 bytes.
    commit: vector<u8>,
    /// The address that made the change.
    commit_by: address,
    /// The blob config holding the content at this revision.
    blob_config_id: ID,
}

// === View functions ===

/// The commitment to the content at this revision.
public fun commit(file_data: &FileData): vector<u8> {
    file_data.commit
}

/// The address that made this change.
public fun commit_by(file_data: &FileData): address {
    file_data.commit_by
}

/// The blob config holding the content at this revision.
public fun blob_config_id(file_data: &FileData): ID {
    file_data.blob_config_id
}

// === Package functions ===

/// Record one revision.
public(package) fun create_file_data(
    commit: vector<u8>,
    commit_by: address,
    blob_config_id: ID,
): FileData {
    commit::assert_valid_root(&commit);

    FileData {
        commit,
        commit_by,
        blob_config_id,
    }
}

/// Unpack a revision into the parts a caller has to account for.
///
/// The only way to consume a `FileData`. It yields the config id precisely so
/// that whoever retires a revision cannot do so without holding the name of the
/// content it leaves behind.
public(package) fun destroy(file_data: FileData): (vector<u8>, address, ID) {
    let FileData { commit, commit_by, blob_config_id } = file_data;

    (commit, commit_by, blob_config_id)
}
