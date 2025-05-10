module setandrenew::wallet;
use wal::wal::WAL;
use sui::coin::{Self, Coin};
use sui::{balance::{Self, Balance}, clock::Clock};
use setandrenew::event::Self;


public struct Wallet has key, store{
    id: UID,
    owner: address,
    created_at: u64,
    balance : Balance<WAL>,
}


public(package) fun create_wallet(clock: &Clock, ctx: &mut TxContext): Wallet{
    let wallet  = Wallet{
        id : object::new(ctx),
        owner: ctx.sender(),
        created_at: clock.timestamp_ms(),
        balance: balance::zero<WAL>(),
    };

    event::emit_wallet_created(object::id(&wallet), ctx.sender());

    wallet
}


public(package) fun deposit(wallet: &mut Wallet, funds: &mut Coin<WAL>, amount: u64, ctx: &mut TxContext):u64 {
    // making sure there is enough money in the coin object
    assert!(funds.value() >= amount, 1);
    let d_amount = funds.split(amount, ctx);
    coin::put(&mut wallet.balance, d_amount);
    event::emit_deposit(ctx.sender(), amount);

    wallet.balance.value()
}


public(package) fun return_balance(wallet: &mut Wallet, coin: Coin<WAL>){
    coin::put(&mut wallet.balance, coin);
}


public(package) fun get_balance(wallet: &mut Wallet, amount: u64): Balance<WAL> {
    let cash = wallet.balance.split(amount);
    cash
}

public(package) fun has_estimate(wallet: &Wallet, estimate: u64):bool{
    if (wallet.balance.value() >= estimate){
        return true
    };
    false
}

public(package) fun get_owner(wallet: &Wallet): address{
    wallet.owner
}

