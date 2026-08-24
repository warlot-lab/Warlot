/// Computes how far a blob must be extended and spends one renewal cycle doing it.
module warlot::renew;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use walrus::{blob::Blob, system::System};
use warlot::blob_config::{Self, BlobConfig};

// === Errors ===

#[error]
const EInvalidAhead: vector<u8> = b"RENEWAL HORIZON MUST BE AT LEAST ONE EPOCH";

// === Package functions ===

/// How many epochs `blob` must be extended by to reach `ahead` epochs beyond the
/// current one. Zero when the blob has expired or is already paid far enough out.
public(package) fun get_renew_epoch_count(blob: &Blob, system: &System, ahead: u32): u32 {
    let current_epoch = system.epoch();
    let blob_end_epoch = blob.storage().end_epoch();

    let target_epoch = current_epoch + ahead;

    // An expired blob cannot be renewed, and a blob already paid past the target
    // owes nothing. The second check is also what keeps the subtraction safe.
    if (blob_end_epoch < current_epoch || blob_end_epoch >= target_epoch) {
        return 0
    };

    target_epoch - blob_end_epoch
}

/// Bring every blob in `blob_cfg` up to `ahead` epochs beyond the current one.
///
/// The cycle is charged after the extension, and only if at least one blob was
/// actually extended. Charging it up front makes a call that does nothing
/// indistinguishable from one that does work, which lets any address exhaust
/// another user's mandate for the price of gas. A horizon of zero can never do
/// work, so it is refused outright rather than accepted as a silent no-op.
public(package) fun renew_blob_cfg(
    blob_cfg: &mut BlobConfig,
    system: &mut System,
    ahead: u32,
    payment: &mut Coin<WAL>,
) {
    assert!(ahead > 0, EInvalidAhead);

    if (!blob_config::has_cycles(blob_cfg)) {
        return
    };

    let mut extended = false;

    blob_config::blobs_mut(blob_cfg).do_mut!(|blob| {
        let extend_epoch_count = get_renew_epoch_count(blob, system, ahead);

        if (extend_epoch_count > 0) {
            system.extend_blob(blob, extend_epoch_count, payment);
            extended = true;
        }
    });

    if (extended) {
        blob_config::consume_cycle(blob_cfg);
    };
}
