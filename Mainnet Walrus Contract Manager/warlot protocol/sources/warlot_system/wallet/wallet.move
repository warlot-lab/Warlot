module warlot::wallet;

use std::{
    string::{Self, String},
    type_name};
use sui::{
    coin::{Self, Coin},
    balance::{Self, Balance},
    clock::{Self, Clock},
    dynamic_object_field as dof,
    dynamic_field as df
    };

use wal::wal::WAL; 
use warlot::event; 

// Keys for Dynamic Fields
const BANK_KEY: vector<u8> = b"wallet_bank";

// Errors
const EInsufficientFunds: u64 = 1;
const ENoBalance: u64 = 2;

/// The main User Wallet object
public struct Wallet has key, store {
    id: UID,
    owner: address,
    created_at: u64,
}

/// The Bank struct holding all balances
public struct Bank has key, store {
    id: UID,
}

// ================== Initialization ==================

public(package) fun create_wallet(clock: &Clock, ctx: &mut TxContext): Wallet {
    let mut wallet = Wallet {
        id: object::new(ctx),
        owner: ctx.sender(),
        created_at: clock::timestamp_ms(clock),
    };

    //  Create the Bank
    let bank = Bank { id: object::new(ctx) };

    // Attach Bank to Wallet as a Dynamic Object Field
    dof::add(&mut wallet.id, BANK_KEY, bank);

    event::emit_wallet_created(object::id(&wallet), ctx.sender());
    wallet
}

// ================== Core Banking Logic (Generic) ==================

/// Helper: Get the string key for a coin type
fun get_type_key<T>(): String {
    string::from_ascii(type_name::with_defining_ids<T>().into_string())
}

/// Helper: Borrow the Bank mutably
fun borrow_bank_mut(wallet: &mut Wallet): &mut Bank {
    dof::borrow_mut<vector<u8>, Bank>(&mut wallet.id, BANK_KEY)
}

/// Helper: Borrow the Bank immutably
fun borrow_bank(wallet: &Wallet): &Bank {
    dof::borrow<vector<u8>, Bank>(&wallet.id, BANK_KEY)
}

/// Deposit a full Coin<T> into the wallet
public(package) fun deposit_coin<T>(wallet: &mut Wallet, coin: Coin<T>) {
    let type_key = get_type_key<T>();
    let bank = borrow_bank_mut(wallet);

    // Check if balance exists, if so join, else create
    if (df::exists_(&bank.id, type_key)) {
        let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
        balance::join(balance, coin::into_balance(coin));
    } else {
        df::add(&mut bank.id, type_key, coin::into_balance(coin));
    };


}

///  specific deposit logic: Splits from a mutable Coin ref
public(package) fun deposit<T>(
    wallet: &mut Wallet, 
    funds: &mut Coin<T>, 
    amount: u64, 
    ctx: &mut TxContext
): u64 {
    assert!(coin::value(funds) >= amount, EInsufficientFunds);
    
    // Split the specific amount
    let deposit_coin = coin::split(funds, amount, ctx);
    
    // Deposit it safely
    deposit_coin<T>(wallet, deposit_coin);

    
    event::emit_deposit(ctx.sender(), amount);

    // Return the new total balance of this specific coin
    get_balance<T>(wallet)
}

/// Withdraw specific amount of Coin<T>
public(package) fun withdraw<T>(
    wallet: &mut Wallet, 
    amount: u64, 
    ctx: &mut TxContext
): Coin<T> {
    let type_key = get_type_key<T>();
    let bank = borrow_bank_mut(wallet);

    assert!(df::exists_(&bank.id, type_key), ENoBalance);
    
    let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
    assert!(balance::value(balance) >= amount, EInsufficientFunds);

    let split = balance::split(balance, amount);
    coin::from_balance(split, ctx)
}

/// Withdraw ALL funds for a specific token
public(package) fun withdraw_all<T>(wallet: &mut Wallet, ctx: &mut TxContext): Coin<T> {
    let type_key = get_type_key<T>();
    let bank = borrow_bank_mut(wallet);
    
    assert!(df::exists_(&bank.id, type_key), ENoBalance);

    let balance = df::borrow_mut<String, Balance<T>>(&mut bank.id, type_key);
    let total = balance::value(balance);
    
    let split = balance::split(balance, total);
    coin::from_balance(split, ctx)
}

// ================== Getters / View Functions ==================

public(package) fun get_balance<T>(wallet: &Wallet): u64 {
    let type_key = get_type_key<T>();
    let bank = borrow_bank(wallet);

    if (!df::exists_(&bank.id, type_key)) {
        return 0
    };

    let balance = df::borrow<String, Balance<T>>(&bank.id, type_key);
    balance::value(balance)
}

public(package) fun has_estimate<T>(wallet: &Wallet, estimate: u64): bool {
    get_balance<T>(wallet) >= estimate
}

public(package) fun get_owner(wallet: &Wallet): address {
    wallet.owner
}

// ================== Legacy Wrappers  ==================


public(package) fun get_coin_wal(wallet: &mut Wallet, ctx: &mut TxContext): Coin<WAL> {
    withdraw_all<WAL>(wallet, ctx)
}