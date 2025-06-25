module warlot::warlotUser;

use std::string::String;
use wal::wal::WAL;
use sui::{coin::{Self, Coin}, clock::Clock};
use warlot::{
    userstate::Self,
    warlotsystem::SystemConfig,
    registry::Registry,
};

// create user internal object and public registry

public fun create_user(
    system_cfg: &mut SystemConfig,
    apikey: String,
    encrypt_key: String,
    warlot_sign_apikey: String,
     public_username: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = userstate::create_user( public_username, object::id(system_cfg), apikey, encrypt_key, warlot_sign_apikey, clock, ctx);

    system_cfg.add_user(new_user, ctx);
    system_cfg.increase_user_count();
       
}

// add coin to your internal wallet
public fun deposit_coin(
     system_cfg: &mut SystemConfig,
     coin: &mut Coin<WAL>,
     amount: u64,
     ctx: &mut TxContext
): u64 {
    let user = system_cfg.get_user_mut(ctx.sender());
    let wallet_state = user.get_wallet();

    wallet_state.deposit(coin, amount, ctx)

}



// update your api keys with cost
public fun update_api_key(
    system_cfg: &mut SystemConfig,
    registry: &mut Registry, 
    new_hashed_apikey: String, 
    new_warlot_sign_apikey: String,
    clock: &Clock,
    payment: &mut Coin<WAL>,
    ctx: &mut TxContext
){
    assert!(object::id(system_cfg) == registry.get_system(), 9);
    let funds = payment.split(
                    system_cfg.cost_change_apikey_forms(), 
                    ctx);

    coin::put<WAL>(system_cfg.get_mut_system_balance(), funds);
    registry.update_api_key(
    new_hashed_apikey, 
    new_warlot_sign_apikey,
    clock
    )
}


// update name with cost
public fun update_username(
    system_cfg: &mut SystemConfig, 
    registry: &mut Registry, 
    new_username: String,
    payment: &mut Coin<WAL>,
    ctx: &mut TxContext,
    ){
    assert!(object::id(system_cfg) == registry.get_system(), 9);
    let funds = payment.split(
                    system_cfg.cost_to_update_name(), 
                    ctx);

    coin::put<WAL>(system_cfg.get_mut_system_balance(), funds);
    registry.update_username(new_username)
}

