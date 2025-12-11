module warlot::renew;

use sui::{
    coin::{Self, Coin},
    balance::Balance,
    table_vec::{Self}
    };


use wal::wal::WAL;

use walrus::{
    blob::Blob,
    system::System};

use warlot::{
    warlot_system::SystemConfig,
    user_state::{Self, User},
};

const BYTES_PER_UNIT_SIZE: u64 = 1_024 * 1_024; // 1 MiB

// Errors
const EInvalidRange: u64 = 99;
const EIndexOutOfBounds: u64 = 100;

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

// ================== Core Logic (Private Helper) ==================

/// Helper: Processes the renewal for a SINGLE user.
fun process_user_renewal(
    user_mut: &mut User,
    walrus_system: &mut System,
    epoch_set: u32,
    ahead: u32,
    payment: &mut Coin<WAL>
) {
    // Get the HEAD of the linked list for this epoch_set
    let mut current_blob_id_opt = user_mut.get_epoch_set_head(epoch_set);

    // Traverse the linked list
    while (option::is_some(&current_blob_id_opt)) {
        let blob_id = *option::borrow(&current_blob_id_opt);
        
        // Get mutable config
        let blob_config = user_state::get_blob_config_by_id(user_mut, blob_id);

        // Execute Renewal
        blob_config.renew_blob_cfg(walrus_system, ahead, payment);

        // Move to next blob in the chain
        current_blob_id_opt = *blob_config.next();
    };
}

// ================== Public Functions ==================

/// Strategy 1: Renew ALL users in the system 
#[allow(lint(self_transfer))]
public fun renew_system_blob(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    epoch_set: u32,
    ahead: u32, // Added 'ahead' to match others
    ctx: &mut TxContext
) {
    let mut payment = extract_payment(estimate, ctx);
    let len = table_vec::length(system_cfg.get_indexer());
    let mut i = 0;

    while (i < len) {
        let user_address = *table_vec::borrow(system_cfg.get_indexer(), i);
        let user_mut = system_cfg.get_user_mut(user_address);
        
        process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);
        
        i = i + 1;
    };

    finalize_payment(payment, ctx);
}

/// Strategy 2: Renew a contiguous RANGE of users [start, end)
#[allow(lint(self_transfer))]
public fun renew_system_blob_range(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    epoch_set: u32,
    ahead: u32,
    start_index: u64,
    end_index: u64,
    ctx: &mut TxContext
) {
    let mut payment = extract_payment(estimate, ctx);
    let total_users = table_vec::length(system_cfg.get_indexer());
    
    assert!(start_index <= end_index, EInvalidRange);
    assert!(end_index <= total_users, EInvalidRange);

    let mut i = start_index;
    while (i < end_index) {
        let user_address = *table_vec::borrow(system_cfg.get_indexer(), i);
        let user_mut = system_cfg.get_user_mut(user_address);
        
        process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);
        
        i = i + 1;
    };

    finalize_payment(payment, ctx);
}

/// Strategy 3: Renew a specific LIST of user indices (e.g. [3, 6, 7])
#[allow(lint(self_transfer))]
public fun renew_system_blob_list(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    epoch_set: u32,
    ahead: u32,
    indices: vector<u64>,
    ctx: &mut TxContext
) {
    let mut payment = extract_payment(estimate, ctx);
    let total_users = table_vec::length(system_cfg.get_indexer());
    let len = vector::length(&indices);
    let mut i = 0;

    while (i < len) {
        let user_index = *vector::borrow(&indices, i);
        
        // Bounds check
        assert!(user_index < total_users, EIndexOutOfBounds);

        let user_address = *table_vec::borrow(system_cfg.get_indexer(), user_index);
        let user_mut = system_cfg.get_user_mut(user_address);

        process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

        i = i + 1;
    };

    finalize_payment(payment, ctx);
}


/// Strategy 4: Address-Based Renewal (Safer than Index)
/// Target a specific user by their address. This is immune to index shifting.
public fun renew_user_by_address(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    user_addr: address,
    epoch_set: u32,
    ahead: u32,
    ctx: &mut TxContext
) {
    let mut payment = extract_payment(estimate, ctx);
    
    // Get User
  
    let user_mut = system_cfg.get_user_mut(user_addr);

    // Process
    process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

    finalize_payment(payment, ctx);
}

/// Strategy 5: Self-Service Renewal
/// Allows a user to renew THEIR OWN blobs.
/// They pay for it directly using the 'estimate' they pass in.
public fun renew_my_blobs(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    epoch_set: u32,
    ahead: u32,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    renew_user_by_address(system_cfg, walrus_system, estimate, sender, epoch_set, ahead, ctx);
}

/// Strategy 6: Single Blob Renewal (Granular)
/// Renew exactly ONE blob, identified by its ID.
/// "Emergency Top-ups" of specific files.
public fun renew_specific_blob(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate, 
    target_user: address,
    blob_id: ID,
    ahead: u32,
    ctx: &mut TxContext
) {
    let mut payment = extract_payment(estimate, ctx);
    
    // Get User and Blob Config
    let user_mut = system_cfg.get_user_mut(target_user);
    
    // Check if blob exists to avoid panic? 
    // get_blob_config_by_id typically panics if missing, which is acceptable safety
    let blob_config = user_state::get_blob_config_by_id(user_mut, blob_id);

    // Renew just this one
    blob_config.renew_blob_cfg(walrus_system, ahead, &mut payment);

    finalize_payment(payment, ctx);
}

// ================== Payment Helpers ==================

fun extract_payment(estimate: Estimate, ctx: &mut TxContext): Coin<WAL> {
    let Estimate { 
        storage_price_per_unit_size: _, 
        bytes_per_unit_size: _,         
        budget 
    } = estimate;
    coin::from_balance(budget, ctx)
}

#[allow(lint(self_transfer))]
fun finalize_payment(payment: Coin<WAL>, ctx: &TxContext) {
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    }
}

// ================== Cost Calculation ==================

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


