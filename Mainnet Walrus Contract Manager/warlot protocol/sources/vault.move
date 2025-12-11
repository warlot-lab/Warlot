module warlot::vault;
use sui::{
    table::{Self, Table},
    balance::{Self, Balance},
    coin::{Self, Coin},
    dynamic_field as df,
};

use std::{
    string::{Self, String},
    type_name};



// Errors
const EInvalidCoin: u64 = 0;
const EInsufficientBalance: u64 = 1;
const ENoBalanceFound: u64 = 2;
const ECoinAlreadySupported: u64 = 3;

/// The Vault struct. 
/// Note: It is NOT generic <T> because it can hold many different coin types.
public struct Vault has key, store {
    id: UID,
    /// Tracks valid coin types. Key = Type Name String (e.g., "0x2::sui::SUI")
    accepted_coins: Table<String, bool>, 
}

// ================== Initialization ==================

/// Create a new empty Vault.
public(package) fun create_vault(ctx: &mut TxContext): Vault {
    Vault {
        id: object::new(ctx),
        accepted_coins: table::new(ctx),
    }
}


// ================== Admin / Config ==================

/// Add a coin type to the allowed list.
public fun add_supported_coin<T>(vault: &mut Vault) {
    let type_name_str = get_type_name_string<T>();
    
    if (table::contains(&vault.accepted_coins, type_name_str)) {
        abort ECoinAlreadySupported
    };

    table::add(&mut vault.accepted_coins, type_name_str, true);
}

/// Remove a coin type from the allowed list
/// Note: This does not remove the balance, just prevents new deposits.
public fun remove_supported_coin<T>(vault: &mut Vault) {
    let type_name_str = get_type_name_string<T>();
    if (table::contains(&vault.accepted_coins, type_name_str)) {
        table::remove(&mut vault.accepted_coins, type_name_str);
    };
}


// ================== Core Logic ==================

/// Deposit generic Coin<T> into the vault.
public fun deposit<T>(vault: &mut Vault, payment: Coin<T>) {
    let type_name_str = get_type_name_string<T>();

    // Check if this coin is allowed
    assert!(table::contains(&vault.accepted_coins, type_name_str), EInvalidCoin);

    // Merge logic using Dynamic Fields
    // use the 'type_name_str' as the key for the Dynamic Field.
    if (df::exists_(&vault.id, type_name_str)) {
        // Case A: Balance already exists, add to it
        let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);
        balance::join(vault_balance, coin::into_balance(payment));
    } else {
        // Case B: No balance yet, create new entry
        df::add(&mut vault.id, type_name_str, coin::into_balance(payment));
    }
}

/// Withdraw specific amount of Coin<T>.
public fun withdraw<T>(
    vault: &mut Vault, 
    amount: u64, 
    ctx: &mut TxContext
): Coin<T> {
    let type_name_str = get_type_name_string<T>();

    // Ensure vault actually have funds of this type
    assert!(df::exists_(&vault.id, type_name_str), ENoBalanceFound);

    // Borrow the balance mutably
    let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);

    // Ensure sufficient funds
    assert!(balance::value(vault_balance) >= amount, EInsufficientBalance);

    // Split and return as Coin
    let split_balance = balance::split(vault_balance, amount);
    coin::from_balance(split_balance, ctx)
}

/// Withdraw ALL funds of a specific Coin<T>.
public fun withdraw_all<T>(vault: &mut Vault, ctx: &mut TxContext): Coin<T> {
    let type_name_str = get_type_name_string<T>();
    assert!(df::exists_(&vault.id, type_name_str), ENoBalanceFound);

    let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);
    let total_amount = balance::value(vault_balance);
    
    let split_balance = balance::split(vault_balance, total_amount);
    coin::from_balance(split_balance, ctx)
}

// ================== View Functions ==================

/// Check the balance of a specific coin type in the vault.
public fun balance_of<T>(vault: &Vault): u64 {
    let type_name_str = get_type_name_string<T>();
    
    if (!df::exists_(&vault.id, type_name_str)) {
        return 0
    };

    let vault_balance = df::borrow<String, Balance<T>>(&vault.id, type_name_str);
    balance::value(vault_balance)
}

/// Check if a coin is supported.
public fun is_coin_supported<T>(vault: &Vault): bool {
    let type_name_str = get_type_name_string<T>();
    table::contains(&vault.accepted_coins, type_name_str)
}

// ================== Helpers ==================

/// Helper to get the clean string representation of a type.
fun get_type_name_string<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}
