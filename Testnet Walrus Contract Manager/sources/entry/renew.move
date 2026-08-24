/// Selects which users' blob configs to renew and drives `storage::renew` over them.
module warlot::entry_renew;

// === Imports ===

use sui::table_vec;
use walrus::system::System;
use warlot::{
    renew::{Self, Estimate},
    store,
    system_config::SystemConfig,
    user,
};

// === Errors ===

const EInvalidRange: u64 = 99;
const EIndexOutOfBounds: u64 = 100;

// === Public functions ===

/// Renew every user in the system.
#[allow(lint(self_transfer))]
public fun renew_system_blob(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    epoch_set: u32,
    ahead: u32,
    ctx: &mut TxContext,
) {
    let mut payment = renew::extract_payment(estimate, ctx);
    let len = table_vec::length(system_cfg.get_indexer());
    let mut i = 0;

    while (i < len) {
        let user_address = *table_vec::borrow(system_cfg.get_indexer(), i);
        let user_mut = user::get_user_mut(system_cfg, user_address);

        renew::process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

        i = i + 1;
    };

    renew::finalize_payment(payment, ctx);
}

/// Renew a contiguous range of users, `[start_index, end_index)`.
#[allow(lint(self_transfer))]
public fun renew_system_blob_range(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    epoch_set: u32,
    ahead: u32,
    start_index: u64,
    end_index: u64,
    ctx: &mut TxContext,
) {
    let mut payment = renew::extract_payment(estimate, ctx);
    let total_users = table_vec::length(system_cfg.get_indexer());

    assert!(start_index <= end_index, EInvalidRange);
    assert!(end_index <= total_users, EInvalidRange);

    let mut i = start_index;
    while (i < end_index) {
        let user_address = *table_vec::borrow(system_cfg.get_indexer(), i);
        let user_mut = user::get_user_mut(system_cfg, user_address);

        renew::process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

        i = i + 1;
    };

    renew::finalize_payment(payment, ctx);
}

/// Renew a specific list of user indices.
#[allow(lint(self_transfer))]
public fun renew_system_blob_list(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    epoch_set: u32,
    ahead: u32,
    indices: vector<u64>,
    ctx: &mut TxContext,
) {
    let mut payment = renew::extract_payment(estimate, ctx);
    let total_users = table_vec::length(system_cfg.get_indexer());
    let len = vector::length(&indices);
    let mut i = 0;

    while (i < len) {
        let user_index = *vector::borrow(&indices, i);

        assert!(user_index < total_users, EIndexOutOfBounds);

        let user_address = *table_vec::borrow(system_cfg.get_indexer(), user_index);
        let user_mut = user::get_user_mut(system_cfg, user_address);

        renew::process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

        i = i + 1;
    };

    renew::finalize_payment(payment, ctx);
}

/// Renew one user, named by address rather than index so it is immune to shifting.
public fun renew_user_by_address(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    user_addr: address,
    epoch_set: u32,
    ahead: u32,
    ctx: &mut TxContext,
) {
    let mut payment = renew::extract_payment(estimate, ctx);

    let user_mut = user::get_user_mut(system_cfg, user_addr);

    renew::process_user_renewal(user_mut, walrus_system, epoch_set, ahead, &mut payment);

    renew::finalize_payment(payment, ctx);
}

/// Renew the sender's own blobs, paid for out of the estimate they supply.
public fun renew_my_blobs(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    epoch_set: u32,
    ahead: u32,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    renew_user_by_address(system_cfg, walrus_system, estimate, sender, epoch_set, ahead, ctx);
}

/// Renew exactly one blob config, for topping up a specific file.
public fun renew_specific_blob(
    system_cfg: &mut SystemConfig,
    walrus_system: &mut System,
    estimate: Estimate,
    target_user: address,
    blob_id: ID,
    ahead: u32,
    ctx: &mut TxContext,
) {
    let mut payment = renew::extract_payment(estimate, ctx);

    let user_mut = user::get_user_mut(system_cfg, target_user);

    // Aborts if the config is not the user's, which is the intended bound.
    let blob_config = store::get_blob_config_by_id(user_mut, blob_id);

    renew::renew_blob_cfg(blob_config, walrus_system, ahead, &mut payment);

    renew::finalize_payment(payment, ctx);
}
