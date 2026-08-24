/// Computes how far a blob must be extended and accounts for one renewal cycle.
module warlot::renew;

// === Imports ===

use sui::{balance::Balance, coin::{Self, Coin}};
use wal::wal::WAL;
use walrus::{blob::Blob, system::System};
use warlot::{
    blob_config::{Self, BlobConfig},
    store,
    user::User,
};

// === Constants ===

const BYTES_PER_UNIT_SIZE: u64 = 1_024 * 1_024; // 1 MiB

// === Structs ===

/// A renewal budget, priced against a storage rate.
public struct Estimate has store {
    storage_price_per_unit_size: u64,
    bytes_per_unit_size: u64,
    budget: Balance<WAL>,
}

// === Public functions ===

/// Convert a coin into a renewal budget priced at `storage_price_per_unit_size`.
public fun create_estimate(storage_price_per_unit_size: u64, coin: Coin<WAL>): Estimate {
    Estimate {
        storage_price_per_unit_size,
        bytes_per_unit_size: BYTES_PER_UNIT_SIZE,
        budget: coin::into_balance(coin),
    }
}

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

/// Spend one renewal cycle bringing every blob in `blob_cfg` up to `ahead`.
public(package) fun renew_blob_cfg(
    blob_cfg: &mut BlobConfig,
    system: &mut System,
    ahead: u32,
    payment: &mut Coin<WAL>,
) {
    if (option::is_some(blob_config::cycle_limit_mut(blob_cfg))) {
        let cycle_limit = option::borrow_mut(blob_config::cycle_limit_mut(blob_cfg));

        if (*cycle_limit == 0) {
            return
        };

        *cycle_limit = *cycle_limit - 1;
    };

    blob_config::blob(blob_cfg).do_mut!(|blob| {
        let extend_epoch_count = get_renew_epoch_count(blob, system, ahead);

        if (extend_epoch_count > 0) {
            extend_blob(system, blob, payment, extend_epoch_count);
        }
    });
}

/// Extend one blob's storage resource by `new_epoch` epochs.
public(package) fun extend_blob(
    system: &mut System,
    blob: &mut Blob,
    payment: &mut Coin<WAL>,
    new_epoch: u32,
) {
    system.extend_blob(blob, new_epoch, payment);
}

/// Walk one user's blob-config list for `epoch_set` and renew every config on it.
public(package) fun process_user_renewal(
    user_mut: &mut User,
    walrus_system: &mut System,
    epoch_set: u32,
    ahead: u32,
    payment: &mut Coin<WAL>,
) {
    let mut current_blob_id_opt = store::get_epoch_set_head(user_mut, epoch_set);

    while (option::is_some(&current_blob_id_opt)) {
        let blob_id = *option::borrow(&current_blob_id_opt);

        let blob_config = store::get_blob_config_by_id(user_mut, blob_id);

        renew_blob_cfg(blob_config, walrus_system, ahead, payment);

        current_blob_id_opt = *blob_config.next();
    };
}

/// Unwrap a budget back into a spendable coin.
public(package) fun extract_payment(estimate: Estimate, ctx: &mut TxContext): Coin<WAL> {
    let Estimate {
        storage_price_per_unit_size: _,
        bytes_per_unit_size: _,
        budget,
    } = estimate;
    coin::from_balance(budget, ctx)
}

/// Return whatever is left of a budget to the sender, or destroy it if empty.
#[allow(lint(self_transfer))]
public(package) fun finalize_payment(payment: Coin<WAL>, ctx: &TxContext) {
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    }
}

// === Private functions ===

#[allow(unused_function)]
fun calcuate_renew_cost(blob: &Blob, estimate: &Estimate, epoch_count: u32): u64 {
    let storage_size = blob.storage().size();
    let storage_units = storage_size.divide_and_round_up(estimate.bytes_per_unit_size);
    let period_payment_due = estimate.storage_price_per_unit_size * storage_units;
    period_payment_due * (epoch_count as u64)
}
