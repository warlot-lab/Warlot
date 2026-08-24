/// Custodies the protocol's multi-coin treasury.
module warlot::vault;

// === Imports ===

use std::{string::{Self, String}, type_name};
use sui::{
    balance::{Self, Balance},
    coin::{Self, Coin},
    dynamic_field as df,
    table::{Self, Table},
};

// === Errors ===

const EInvalidCoin: u64 = 0;
const EInsufficientBalance: u64 = 1;
const ENoBalanceFound: u64 = 2;
const ECoinAlreadySupported: u64 = 3;

// === Structs ===

/// A container for assets.
/// Not generic over `T`, so one vault can hold many coin types at once, each
/// under a dynamic field keyed by its type name.
public struct Vault has key, store {
    id: UID,
    /// Tracks valid coin types. Key = type name string (e.g. `0x2::sui::SUI`).
    accepted_coins: Table<String, bool>,
}

// === Public functions ===

/// Add a coin type to the allowed list.
public fun add_supported_coin<T>(vault: &mut Vault) {
    let type_name_str = get_type_name_string<T>();

    if (table::contains(&vault.accepted_coins, type_name_str)) {
        abort ECoinAlreadySupported
    };

    table::add(&mut vault.accepted_coins, type_name_str, true);
}

/// Remove a coin type from the allowed list.
/// This does not remove the balance, it only prevents new deposits.
public fun remove_supported_coin<T>(vault: &mut Vault) {
    let type_name_str = get_type_name_string<T>();
    if (table::contains(&vault.accepted_coins, type_name_str)) {
        table::remove(&mut vault.accepted_coins, type_name_str);
    };
}

/// Deposit a `Coin<T>` into the vault, merging it with any balance already held.
public fun deposit<T>(vault: &mut Vault, payment: Coin<T>) {
    let type_name_str = get_type_name_string<T>();

    assert!(table::contains(&vault.accepted_coins, type_name_str), EInvalidCoin);

    if (df::exists_(&vault.id, type_name_str)) {
        let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);
        balance::join(vault_balance, coin::into_balance(payment));
    } else {
        df::add(&mut vault.id, type_name_str, coin::into_balance(payment));
    }
}

/// Withdraw a specific amount of `Coin<T>`.
public fun withdraw<T>(vault: &mut Vault, amount: u64, ctx: &mut TxContext): Coin<T> {
    let type_name_str = get_type_name_string<T>();

    assert!(df::exists_(&vault.id, type_name_str), ENoBalanceFound);

    let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);

    assert!(balance::value(vault_balance) >= amount, EInsufficientBalance);

    let split_balance = balance::split(vault_balance, amount);
    coin::from_balance(split_balance, ctx)
}

/// Withdraw the entire balance of `Coin<T>`.
public fun withdraw_all<T>(vault: &mut Vault, ctx: &mut TxContext): Coin<T> {
    let type_name_str = get_type_name_string<T>();
    assert!(df::exists_(&vault.id, type_name_str), ENoBalanceFound);

    let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);
    let total_amount = balance::value(vault_balance);

    let split_balance = balance::split(vault_balance, total_amount);
    coin::from_balance(split_balance, ctx)
}

// === View functions ===

/// The balance of `T` held in the vault, or zero if none is held.
public fun balance_of<T>(vault: &Vault): u64 {
    let type_name_str = get_type_name_string<T>();

    if (!df::exists_(&vault.id, type_name_str)) {
        return 0
    };

    let vault_balance = df::borrow<String, Balance<T>>(&vault.id, type_name_str);
    balance::value(vault_balance)
}

/// Whether `T` is on the accepted-coin list.
public fun is_coin_supported<T>(vault: &Vault): bool {
    let type_name_str = get_type_name_string<T>();
    table::contains(&vault.accepted_coins, type_name_str)
}

// === Package functions ===

/// Create a new, empty vault accepting no coin types.
public(package) fun create_vault(ctx: &mut TxContext): Vault {
    Vault {
        id: object::new(ctx),
        accepted_coins: table::new(ctx),
    }
}

// === Private functions ===

fun get_type_name_string<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}
