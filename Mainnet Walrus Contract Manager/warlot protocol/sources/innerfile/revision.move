/// Turns stored blobs into one revision of an inner file.
///
/// One function, and it exists as a module because the two halves of the
/// inner-file entry surface ,  creating a file and writing to it ,  both need it
/// and neither may import the other. The entry layer sits at the top of the
/// ladder, so a helper shared across it belongs below it rather than beside it.
module warlot::revision;

// === Imports ===

use sui::clock::Clock;
use walrus::blob::Blob;
use warlot::{file_data::{Self, FileData}, operator::OperatorAuth, store, system_config::SystemConfig};

// === Package functions ===

/// Store `blobs` under `store_to` and record the result as one revision.
///
/// `store_to` is the address that takes custody, which is the file's owner for a
/// write into history and the sender for one routed into the draft queue.
/// `commit_by` is who made the change, and the two differ on every delegated
/// write.
public(package) fun store_revision(
    system_cfg: &SystemConfig,
    blobs: vector<Blob>,
    epoch_set: u32,
    cycle_end: u64,
    store_to: address,
    commit: vector<u8>,
    commit_by: address,
    operator: Option<OperatorAuth>,
    clock: &Clock,
    ctx: &mut TxContext,
): FileData {
    let (blob_config_id, _) = store::store_blob_internal(
        system_cfg,
        blobs,
        epoch_set,
        cycle_end,
        store_to,
        operator,
        clock,
        ctx,
    );

    file_data::create_file_data(commit, commit_by, blob_config_id)
}
