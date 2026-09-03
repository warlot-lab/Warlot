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
use warlot::{admin_cap::{Self, AdminCap}, treasury_events};

// === Errors ===

#[error]
const EInvalidCoin: vector<u8> = b"THIS VAULT DOES NOT ACCEPT THAT COIN TYPE";
#[error]
const EInsufficientBalance: vector<u8> = b"THE VAULT HOLDS LESS THAN THAT";
#[error]
const ENoBalanceFound: vector<u8> = b"THE VAULT HOLDS NONE OF THAT COIN TYPE";
#[error]
const ECoinAlreadySupported: vector<u8> = b"THIS VAULT ALREADY ACCEPTS THAT COIN TYPE";
#[error]
const ENotOriginalCap: vector<u8> = b"THIS OPERATION NEEDS THE ORIGINAL ADMIN CAPABILITY";
#[error]
const ECapForAnotherSystem: vector<u8> = b"THIS ADMIN CAPABILITY WAS MINTED FOR A DIFFERENT SYSTEM";

// === Structs ===

/// A container for assets.
/// Not generic over `T`, so one vault can hold many coin types at once, each
/// under a dynamic field keyed by its type name.
public struct Vault has key, store {
    id: UID,
    /// The system this vault is the treasury of. Every operation that takes value
    /// out of the vault is authorised against this, so the vault does not depend
    /// on being unreachable to be safe.
    system: ID,
    /// Tracks valid coin types. Key = type name string (e.g. `0x2::sui::SUI`).
    accepted_coins: Table<String, bool>,
}

// === Public functions ===

/// Add a coin type to the allowed list.
public fun add_supported_coin<T>(vault: &mut Vault, admin_cap: &AdminCap) {
    vault.assert_operator(admin_cap);

    let type_name_str = get_type_name_string<T>();

    assert!(!table::contains(&vault.accepted_coins, type_name_str), ECoinAlreadySupported);

    table::add(&mut vault.accepted_coins, type_name_str, true);

    treasury_events::emit_vault_coin_support_changed(vault.system, type_name_str, true);
}

/// Remove a coin type from the allowed list.
/// This does not remove the balance, it only prevents new deposits.
public fun remove_supported_coin<T>(vault: &mut Vault, admin_cap: &AdminCap) {
    vault.assert_operator(admin_cap);

    let type_name_str = get_type_name_string<T>();
    if (table::contains(&vault.accepted_coins, type_name_str)) {
        table::remove(&mut vault.accepted_coins, type_name_str);

        treasury_events::emit_vault_coin_support_changed(vault.system, type_name_str, false);
    };
}

/// Deposit a `Coin<T>` into the vault, merging it with any balance already held.
///
/// Deliberately unauthorised. Paying into the treasury is what users do when they
/// pay a fee, and a deposit can only ever increase what the vault holds ,  the
/// accepted-coin list is the only thing that needs saying no here, and it does.
public fun deposit<T>(vault: &mut Vault, payment: Coin<T>) {
    let type_name_str = get_type_name_string<T>();

    assert!(table::contains(&vault.accepted_coins, type_name_str), EInvalidCoin);

    let system = vault.system;
    let amount = coin::value(&payment);

    if (df::exists(&vault.id, type_name_str)) {
        let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);
        balance::join(vault_balance, coin::into_balance(payment));
    } else {
        df::add(&mut vault.id, type_name_str, coin::into_balance(payment));
    };

    treasury_events::emit_vault_deposited(system, type_name_str, amount, balance_of<T>(vault));
}

/// Withdraw a specific amount of `Coin<T>`.
/// Every payout is announced from here rather than from the entry points that
/// compose it, so a route added later cannot take value out of the treasury
/// without saying so.
public fun withdraw<T>(
    vault: &mut Vault,
    admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    vault.assert_operator(admin_cap);

    let type_name_str = get_type_name_string<T>();

    assert!(df::exists(&vault.id, type_name_str), ENoBalanceFound);

    let system = vault.system;

    let vault_balance = df::borrow_mut<String, Balance<T>>(&mut vault.id, type_name_str);

    assert!(balance::value(vault_balance) >= amount, EInsufficientBalance);

    let split_balance = balance::split(vault_balance, amount);
    let remaining = balance::value(vault_balance);

    treasury_events::emit_system_withdraw(system, ctx.sender(), type_name_str, amount, remaining);

    coin::from_balance(split_balance, ctx)
}

// === View functions ===

/// The balance of `T` held in the vault, or zero if none is held.
public fun balance_of<T>(vault: &Vault): u64 {
    let type_name_str = get_type_name_string<T>();

    if (!df::exists(&vault.id, type_name_str)) {
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

/// The system this vault is the treasury of.
public fun system(vault: &Vault): ID {
    vault.system
}

// === Package functions ===

/// Create a new, empty vault accepting no coin types.
public(package) fun create_vault(system: ID, ctx: &mut TxContext): Vault {
    Vault {
        id: object::new(ctx),
        system,
        accepted_coins: table::new(ctx),
    }
}

/// Add a coin type to the allowed list while the vault is still being built.
///
/// The vault's own system has no original capability until the transaction that
/// mints it has finished, so the first accepted coin type cannot be authorised
/// the ordinary way. This is `public(package)`, and its only caller is the system
/// constructor.
public(package) fun support_coin_on_creation<T>(vault: &mut Vault) {
    let type_name_str = get_type_name_string<T>();

    assert!(!table::contains(&vault.accepted_coins, type_name_str), ECoinAlreadySupported);

    table::add(&mut vault.accepted_coins, type_name_str, true);

    treasury_events::emit_vault_coin_support_changed(vault.system, type_name_str, true);
}

// === Private functions ===

/// Assert `admin_cap` is an original capability for this vault's own system.
fun assert_operator(vault: &Vault, admin_cap: &AdminCap) {
    assert!(admin_cap.state() == admin_cap::state_original(), ENotOriginalCap);
    assert!(admin_cap.system_config_id() == vault.system, ECapForAnotherSystem);
}

fun get_type_name_string<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}
