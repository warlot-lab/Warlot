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
use wal::wal::WAL;
use warlot::identity_events;

// === Errors ===

const EInsufficientFunds: u64 = 1;
const ENoBalance: u64 = 2;

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
public struct Bank has key, store {
    id: UID,
}

// === Package functions ===

/// Create a wallet for the sender with an empty bank attached.
public(package) fun create_wallet(system_id: ID, clock: &Clock, ctx: &mut TxContext): Wallet {
    let mut wallet = Wallet {
        id: object::new(ctx),
        owner: ctx.sender(),
        created_at: clock::timestamp_ms(clock),
    };

    let bank = Bank { id: object::new(ctx) };

    dof::add(&mut wallet.id, BANK_KEY, bank);

    identity_events::emit_wallet_created(system_id, object::id(&wallet), ctx.sender(), wallet.created_at);

    wallet
}

/// Deposit a whole `Coin<T>` into the wallet.
public(package) fun deposit_coin<T>(wallet: &mut Wallet, coin: Coin<T>) {
    let type_key = get_type_key<T>();
    let bank = borrow_bank_mut(wallet);

    if (df::exists_(&bank.id, type_key)) {
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

    deposit_coin<T>(wallet, deposit_coin);

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
    let bank = borrow_bank_mut(wallet);

    assert!(df::exists_(&bank.id, type_key), ENoBalance);

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
    let bank = borrow_bank_mut(wallet);

    assert!(df::exists_(&bank.id, type_key), ENoBalance);

    let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
    let total = balance::value(balance);

    let split = balance::split(balance, total);

    identity_events::emit_wallet_withdrawn(system_id, owner, type_key, total, 0);

    coin::from_balance(split, ctx)
}

/// The balance of `T` held, or zero if none is held.
public(package) fun get_balance<T>(wallet: &Wallet): u64 {
    let type_key = get_type_key<T>();
    let bank = borrow_bank(wallet);

    if (!df::exists_(&bank.id, type_key)) {
        return 0
    };

    let balance = df::borrow<String, Balance<T>>(&bank.id, type_key);
    balance::value(balance)
}

/// Whether the wallet holds at least `estimate` of `T`.
public(package) fun has_estimate<T>(wallet: &Wallet, estimate: u64): bool {
    get_balance<T>(wallet) >= estimate
}

/// The address this wallet belongs to.
public(package) fun get_owner(wallet: &Wallet): address {
    wallet.owner
}

/// Withdraw the wallet's entire WAL balance.
public(package) fun get_coin_wal(
    wallet: &mut Wallet,
    system_id: ID,
    ctx: &mut TxContext,
): Coin<WAL> {
    withdraw_all<WAL>(wallet, system_id, ctx)
}

// === Private functions ===

fun get_type_key<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}

fun borrow_bank_mut(wallet: &mut Wallet): &mut Bank {
    dof::borrow_mut<vector<u8>, Bank>(&mut wallet.id, BANK_KEY)
}

fun borrow_bank(wallet: &Wallet): &Bank {
    dof::borrow<vector<u8>, Bank>(&wallet.id, BANK_KEY)
}
