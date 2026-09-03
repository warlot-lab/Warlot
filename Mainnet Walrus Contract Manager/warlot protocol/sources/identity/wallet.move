/// Holds, receives and releases a user's coin balances.
module warlot::wallet;

// === Imports ===

use std::{string::{Self, String}, type_name};
use sui::{
    balance::{Self, Balance},
    clock::{Self, Clock},
    coin::{Self, Coin},
    dynamic_field as df,
    dynamic_object_field as dof,
};
use warlot::identity_events;

// === Errors ===

#[error]
const EInsufficientFunds: vector<u8> = b"THIS WALLET HOLDS LESS THAN THAT";
#[error]
const ENoBalance: vector<u8> = b"THIS WALLET HOLDS NONE OF THAT COIN TYPE";

// === Constants ===

/// Dynamic object field key for the wallet's balance container.
const BANK_KEY: vector<u8> = b"wallet_bank";

// === Structs ===

/// The user-facing interface to their funds.
public struct Wallet has key, store {
    id: UID,
    owner: address,
    created_at: u64,
}

/// Holds balances for many coin types, one dynamic field per type name.
///
/// Attached on the first deposit rather than at the wallet's creation. It is a
/// dynamic object field ,  two objects, counting the field entry ,  and an
/// account that has never funded its wallet holds no balance for it to keep.
public struct Bank has key, store {
    id: UID,
}

// === Package functions ===

/// Create a wallet for the sender.
public(package) fun create_wallet(system_id: ID, clock: &Clock, ctx: &mut TxContext): Wallet {
    let wallet = Wallet {
        id: object::new(ctx),
        owner: ctx.sender(),
        created_at: clock::timestamp_ms(clock),
    };

    identity_events::emit_wallet_created(system_id, object::id(&wallet), ctx.sender(), wallet.created_at);

    wallet
}

/// Deposit a whole `Coin<T>` into the wallet, attaching the bank if this is the
/// first deposit the wallet has ever taken.
public(package) fun deposit_coin<T>(wallet: &mut Wallet, coin: Coin<T>, ctx: &mut TxContext) {
    let type_key = get_type_key<T>();
    let bank = borrow_bank_mut_or_attach(wallet, ctx);

    if (df::exists(&bank.id, type_key)) {
        let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
        balance::join(balance, coin::into_balance(coin));
    } else {
        df::add(&mut bank.id, type_key, coin::into_balance(coin));
    };
}

/// Split `amount` out of `funds` into the wallet and return the new balance of `T`.
public(package) fun deposit<T>(
    wallet: &mut Wallet,
    system_id: ID,
    funds: &mut Coin<T>,
    amount: u64,
    ctx: &mut TxContext,
): u64 {
    assert!(coin::value(funds) >= amount, EInsufficientFunds);

    let deposit_coin = coin::split(funds, amount, ctx);

    deposit_coin<T>(wallet, deposit_coin, ctx);

    let new_balance = get_balance<T>(wallet);

    // The wallet holds many coin types under one object, so an untyped amount
    // sums balances of different things into one meaningless number.
    identity_events::emit_wallet_deposited(
        system_id,
        wallet.owner,
        get_type_key<T>(),
        amount,
        new_balance,
    );

    new_balance
}

/// Withdraw a specific amount of `Coin<T>`.
public(package) fun withdraw<T>(
    wallet: &mut Wallet,
    system_id: ID,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let type_key = get_type_key<T>();
    let owner = wallet.owner;

    assert!(has_bank(wallet), ENoBalance);

    let bank = borrow_bank_mut(wallet);

    assert!(df::exists(&bank.id, type_key), ENoBalance);

    let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
    assert!(balance::value(balance) >= amount, EInsufficientFunds);

    let split = balance::split(balance, amount);
    let remaining = balance::value(balance);

    identity_events::emit_wallet_withdrawn(system_id, owner, type_key, amount, remaining);

    coin::from_balance(split, ctx)
}

/// Withdraw the entire balance of `Coin<T>`.
public(package) fun withdraw_all<T>(
    wallet: &mut Wallet,
    system_id: ID,
    ctx: &mut TxContext,
): Coin<T> {
    let type_key = get_type_key<T>();
    let owner = wallet.owner;

    assert!(has_bank(wallet), ENoBalance);

    let bank = borrow_bank_mut(wallet);

    assert!(df::exists(&bank.id, type_key), ENoBalance);

    let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
    let total = balance::value(balance);

    let split = balance::split(balance, total);

    identity_events::emit_wallet_withdrawn(system_id, owner, type_key, total, 0);

    coin::from_balance(split, ctx)
}

/// The balance of `T` held, or zero if none is held.
///
/// A wallet that has never taken a deposit holds no bank, and a wallet with no
/// bank holds nothing of any type, so the two absences answer the same way.
public(package) fun get_balance<T>(wallet: &Wallet): u64 {
    if (!has_bank(wallet)) {
        return 0
    };

    let type_key = get_type_key<T>();
    let bank = borrow_bank(wallet);

    if (!df::exists(&bank.id, type_key)) {
        return 0
    };

    let balance = df::borrow<String, Balance<T>>(&bank.id, type_key);
    balance::value(balance)
}

#[test_only]
/// Whether the wallet holds at least `estimate` of `T`.
public fun has_estimate<T>(wallet: &Wallet, estimate: u64): bool {
    get_balance<T>(wallet) >= estimate
}

// === Test-only helpers ===

#[test_only]
/// Whether this wallet has ever taken a deposit.
public fun has_bank_for_testing(wallet: &Wallet): bool {
    has_bank(wallet)
}

// === Private functions ===

fun get_type_key<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}

/// Whether this wallet has ever taken a deposit.
fun has_bank(wallet: &Wallet): bool {
    dof::exists<vector<u8>>(&wallet.id, BANK_KEY)
}

fun borrow_bank_mut(wallet: &mut Wallet): &mut Bank {
    dof::borrow_mut<vector<u8>, Bank>(&mut wallet.id, BANK_KEY)
}

/// The wallet's bank, attaching an empty one if this is its first deposit.
fun borrow_bank_mut_or_attach(wallet: &mut Wallet, ctx: &mut TxContext): &mut Bank {
    if (!has_bank(wallet)) {
        dof::add(&mut wallet.id, BANK_KEY, Bank { id: object::new(ctx) });
    };

    borrow_bank_mut(wallet)
}

fun borrow_bank(wallet: &Wallet): &Bank {
    dof::borrow<vector<u8>, Bank>(&wallet.id, BANK_KEY)
}
