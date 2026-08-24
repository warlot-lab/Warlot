/// Composes the privileged operations an `AdminCap` holder may perform.
module warlot::entry_admin;

// === Imports ===

use sui::coin::Coin;
use wal::wal::WAL;
use warlot::{
    admin_cap::{Self, AdminCap},
    events,
    system_config::{Self, SystemConfig},
    vault,
};

// === Admin functions ===

/// Withdraw WAL from the system vault to the caller.
#[allow(lint(self_transfer))]
public fun withdraw_system_wal(
    system_cfg: &mut SystemConfig,
    admin_cap: &mut AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(admin_cap.state() == admin_cap::state_original(), 1);

    let vault = system_cfg.get_vault_mut();
    let withdrawn_coin = vault::withdraw<WAL>(vault, amount, ctx);

    transfer::public_transfer(withdrawn_coin, ctx.sender());
}

/// Withdraw any accepted coin type from the system vault to the caller.
#[allow(lint(self_transfer))]
public fun withdraw_system_coin<T>(
    system_cfg: &mut SystemConfig,
    admin_cap: &mut AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(admin_cap.state() == admin_cap::state_original(), 1);

    let vault = system_cfg.get_vault_mut();

    // Aborts with `ENoBalanceFound` when the vault holds none of this type.
    let withdrawn_coin = vault::withdraw<T>(vault, amount, ctx);

    transfer::public_transfer(withdrawn_coin, ctx.sender());
}

/// Accept a new coin type into the system vault.
public fun add_coin_type<T>(_admin_cap: &mut AdminCap, system_cfg: &mut SystemConfig) {
    let vault = system_cfg.get_vault_mut();
    vault::add_supported_coin<T>(vault);
}

/// Stop accepting a coin type. Balances already held stay withdrawable.
public fun remove_supported_coin<T>(admin_cap: &mut AdminCap, system_cfg: &mut SystemConfig) {
    assert!(admin_cap.state() == admin_cap::state_original(), 1);

    let vault = system_cfg.get_vault_mut();
    vault::remove_supported_coin<T>(vault);
}

/// Mint the next system in the chain and share it.
public fun mint_system(
    admin_cap: &mut AdminCap,
    old_system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
    cost_to_delete: u64,
    ctx: &mut TxContext,
) {
    // System minting is linear: an old system may name only one successor.
    assert!(option::is_none(old_system.next_system()), 0);

    assert!(admin_cap.state() == admin_cap::state_original(), 3);

    let new_system = system_config::new(
        object::id(old_system),
        1 + old_system.get_system_version(),
        cost_change_apikey_forms,
        cost_to_migrate_system,
        cost_to_update_name,
        cost_to_delete,
        ctx,
    );

    let new_system_id = object::id(&new_system);
    events::emit_system_mint(new_system_id, object::id(old_system), ctx.sender());

    admin_cap.increase_total_system();
    old_system.set_next_system(new_system_id);

    transfer::public_share_object(new_system);
}

/// Overwrite the registry modification fees.
public fun update_cost(
    admin_cap: &mut AdminCap,
    system: &mut SystemConfig,
    cost_change_apikey_forms: u64,
    cost_to_migrate_system: u64,
    cost_to_update_name: u64,
) {
    assert!(admin_cap.state() == admin_cap::state_original(), 3);
    system.set_costs(cost_change_apikey_forms, cost_to_migrate_system, cost_to_update_name);
}

/// Mint a duplicate admin capability for `receiver`.
public fun mint_admin(
    system_cfg: &SystemConfig,
    receiver: address,
    admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    assert!(admin_cap.state() == admin_cap::state_original(), 1);

    let new_cap = admin_cap::new(
        object::id(system_cfg),
        admin_cap::state_duplicate(),
        0,
        ctx,
    );

    events::emit_admin_mint(object::id(&new_cap), ctx.sender());
    admin_cap::transfer_to(new_cap, receiver);
}
