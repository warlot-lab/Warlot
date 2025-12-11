module warlot::renew;

use sui::{
    coin::{Self, Coin},
    balance::Balance,
    table_vec::Self,
    };
use wal::wal::WAL;
use walrus::blob::Blob;
use walrus::system::System;
use warlot::{
    warlot_system::SystemConfig,
    user_state::Self,
    };

const BYTES_PER_UNIT_SIZE: u64 = 1_024 * 1_024; // 1 MiB

public struct Estimate has store {
    storage_price_per_unit_size: u64,
    bytes_per_unit_size: u64,
    budget: Balance<WAL>,
}

public fun create_estimate(storage_price_per_unit_size: u64, coin: Coin<WAL>): Estimate {
    Estimate {
        storage_price_per_unit_size,
        bytes_per_unit_size: BYTES_PER_UNIT_SIZE,
        budget: coin::into_balance(coin),
    }
}

#[allow(lint(self_transfer))]
public fun renew_system_blob(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    epoch_set: u32,
    ctx: &mut TxContext
) {
    // Unpack Estimate
    let Estimate { 
        storage_price_per_unit_size: _, 
        bytes_per_unit_size: _,         
        budget 
    } = estimate;

    let mut payment = coin::from_balance(budget, ctx);

  
    
    // Iterate manually using length and index
    let len = table_vec::length(system_cfg.get_indexer());
    let mut i = 0;

    while (i < len) {
        // Borrow the address at index 'i'
        let user_address = *table_vec::borrow(system_cfg.get_indexer(), i);

        // Get the user object 
        let user_mut_ref = system_cfg.get_user_mut(user_address);

        // Get the HEAD of the list (Updated from tail)
        // Get the starting blob ID
        let mut current_blob_id_opt = user_mut_ref.get_epoch_set_head(epoch_set);

        // Process the chain of blobs for this user
        while (option::is_some(&current_blob_id_opt)) {
            let blob_id = *option::borrow(&current_blob_id_opt);
            
            // Get mutable config for this blob
            let blob_config = user_state::get_blob_config_by_id(user_mut_ref, blob_id);

            // Renew (mutates payment)
            blob_config.renew_blob_cfg(walrus_system, epoch_set, &mut payment);

            // Move to next blob
            current_blob_id_opt = *blob_config.next();
        };

        // Increment index for the outer loop
        i = i + 1;
    };

    // Cleanup: Return remaining change or destroy empty coin
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    }
}


#[allow(unused_function)]
fun calcuate_renew_cost(
    blob: &Blob,
    estimate: &Estimate,
    epoch_count: u32,
): u64 {
    let storage_size = blob.storage().size();

    let storage_units = storage_size.divide_and_round_up(estimate.bytes_per_unit_size);

    let period_payment_due = estimate.storage_price_per_unit_size * storage_units;

    period_payment_due * (epoch_count as u64)
}
