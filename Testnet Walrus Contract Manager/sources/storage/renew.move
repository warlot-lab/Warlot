/// Computes how far a blob must be extended and spends one renewal cycle doing it.
module warlot::renew;

// === Imports ===

use sui::coin::{Self, Coin};
use wal::wal::WAL;
use walrus::{blob::{Self, Blob}, system::System};
use warlot::{blob_config::{Self, BlobConfig}, storage_events};

// === Errors ===

#[error]
const EInvalidAhead: vector<u8> = b"A CONFIG'S STORAGE TERM MUST BE AT LEAST ONE EPOCH";

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

/// Bring every blob in `blob_cfg` back up to the term the config was bought under.
///
/// The term is a sustained target rather than a one-off purchase: every renewal
/// tops the blobs back up to `current_epoch + epoch_set`, so a config settles into
/// a steady state that many epochs ahead of wherever the chain has got to.
///
/// The cycle is charged after the extension, and only if at least one blob was
/// actually extended. Charging it up front makes a call that does nothing
/// indistinguishable from one that does work, which lets any address exhaust
/// another user's mandate for the price of gas. A term of zero can never do work,
/// so it is refused outright rather than accepted as a silent no-op.
public(package) fun renew_blob_cfg(
    blob_cfg: &mut BlobConfig,
    system: &mut System,
    payment: &mut Coin<WAL>,
    system_id: ID,
    ctx: &TxContext,
) {
    let ahead = blob_config::epoch_set(blob_cfg);

    assert!(ahead > 0, EInvalidAhead);

    let config_id = blob_config::config_id(blob_cfg);
    let owner = blob_config::owner(blob_cfg);
    let executed_by = ctx.sender();
    let current_epoch = system.epoch();

    if (!blob_config::has_cycles(blob_cfg)) {
        // A drained mandate is the outcome an attacker is aiming for, so it is
        // the one that must not be silent.
        storage_events::emit_renew_skipped(
            system_id,
            config_id,
            owner,
            option::none(),
            storage_events::renew_skip_cycle_exhausted(),
            ahead,
            current_epoch,
            executed_by,
        );

        return
    };

    let mut extended = 0;
    let mut wal_spent = 0;

    // Bounded by the blobs this config holds, which is fixed when it is created.
    blob_config::blobs_mut(blob_cfg).do_mut!(|blob| {
        let extend_epoch_count = get_renew_epoch_count(blob, system, ahead);
        let blob_obj_id = blob::object_id(blob);

        if (extend_epoch_count > 0) {
            // The cost is the coin's value either side of the call. Nothing else
            // knows it: the price is Walrus's, not the protocol's, and it varies
            // with the size and the number of epochs bought.
            let before = coin::value(payment);

            system.extend_blob(blob, extend_epoch_count, payment);

            let spent = before - coin::value(payment);

            extended = extended + 1;
            wal_spent = wal_spent + spent;

            storage_events::emit_blob_renewed(
                system_id,
                config_id,
                owner,
                blob_obj_id,
                ahead,
                current_epoch,
                extend_epoch_count,
                blob::storage(blob).end_epoch(),
                spent,
                executed_by,
            );
        } else {
            let reason = if (blob::storage(blob).end_epoch() < current_epoch) {
                storage_events::renew_skip_expired()
            } else {
                storage_events::renew_skip_already_funded()
            };

            storage_events::emit_renew_skipped(
                system_id,
                config_id,
                owner,
                option::some(blob_obj_id),
                reason,
                ahead,
                current_epoch,
                executed_by,
            );
        }
    });

    if (extended > 0) {
        blob_config::consume_cycle(blob_cfg);

        storage_events::emit_renew_cycle_spent(
            system_id,
            config_id,
            owner,
            extended,
            wal_spent,
            blob_config::cycle_limit(blob_cfg),
            executed_by,
        );
    };
}
