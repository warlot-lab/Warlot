/// Represents one revision of an inner file: its commit, its author and its blob config.
module warlot::file_data;

// === Structs ===

/// One recorded change to an inner file.
public struct FileData has store, drop {
    /// The commitment to the content at this revision.
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
    FileData {
        commit,
        commit_by,
        blob_config_id,
    }
}
