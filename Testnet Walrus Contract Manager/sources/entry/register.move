/// Creates, renames and migrates a user's `Registry` and the `User` state it names.
module warlot::entry_register;

// === Imports ===

use std::string::String;
use sui::{clock::Clock, coin::{Self, Coin}};
use wal::wal::WAL;
use warlot::{
    registry::{Self, Registry},
    system_config::{Self, SystemConfig},
    user,
    vault,
};

// === Errors ===

#[error]
const ERegistryForAnotherSystem: vector<u8> = b"THIS REGISTRY BELONGS TO A DIFFERENT SYSTEM";
#[error]
const EInsufficientPayment: vector<u8> = b"THE COIN DOES NOT COVER THE MIGRATION FEE";
#[error]
const ENotRegisteredHere: vector<u8> = b"THIS USER IS NOT REGISTERED WITH THE SYSTEM BEING LEFT";
#[error]
const EAlreadyRegisteredThere: vector<u8> =
    b"THIS USER IS ALREADY REGISTERED WITH THE SYSTEM BEING JOINED";

// === Public functions ===

/// Register the sender with no delegate.
///
/// `all_` marks a registration that creates every object a Warlot application
/// state needs, rather than just the user record.
public fun all_register_user_publicly(
    system_cfg: &mut SystemConfig,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let new_user = user::create_user(
        public_username,
        object::id(system_cfg),
        clock,
        false,
        ctx,
    );

    user::add_user(system_cfg, new_user, ctx);
}

/// Register the sender, granting the system operator role every capability bit.
///
/// The grant names no address. It reaches whichever capability the system's
/// operator set holds at the time of the call, so a backend key added, retired
/// or rotated afterwards inherits or loses it with no further write against this
/// user. The address this used to name was fixed at `mint_system` and had no
/// setter, which is what made a key rotation an O(users) migration.
public fun all_register_user_with_system_permission(
    system_cfg: &mut SystemConfig,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    let new_user = user::create_user(
        public_username,
        object::id(system_cfg),
        clock,
        true,
        ctx,
    );

    user::add_user(system_cfg, new_user, ctx);
}

/// Replace the registry's public username, paying the system's fee.
public fun update_username(
    system_cfg: &mut SystemConfig,
    registry: &mut Registry,
    new_username: String,
    payment: &mut Coin<WAL>,
    ctx: &mut TxContext,
) {
    system_cfg.assert_version();

    assert!(object::id(system_cfg) == registry.get_system(), ERegistryForAnotherSystem);

    let fee = system_cfg.cost_to_update_name();
    let paid_coin = coin::split(payment, fee, ctx);

    let vault = system_cfg.get_vault_mut();
    vault::deposit(vault, paid_coin);

    registry.update_username(new_username);
}

/// Move a user's state and registry from one system to the next.
public fun migrate_system(
    registry: &mut Registry,
    current_system: &mut SystemConfig,
    next_system: &mut SystemConfig,
    coin: &mut Coin<WAL>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    current_system.assert_version();
    next_system.assert_version();

    let user_address = registry.get_user();

    let cost = next_system.cost_to_migrate_system();

    assert!(object::id(current_system) == registry.get_system(), ERegistryForAnotherSystem);

    assert!(coin.value() >= cost, EInsufficientPayment);

    assert!(user::check_user(current_system, registry.get_user()), ENotRegisteredHere);

    // This version only allows migration into a system the user is not already in.
    assert!(!user::check_user(next_system, registry.get_user()), EAlreadyRegisteredThere);

    // Only the fee leaves the caller's coin; the change stays where it was.
    let payment = coin::split(coin, cost, ctx);

    let next_vault = system_config::get_vault_mut(next_system);
    vault::deposit(next_vault, payment);

    let user_data = user::remove_user(current_system, user_address);

    user::add_user(next_system, user_data, ctx);

    registry.migrate_system(object::id(next_system), clock);
}
