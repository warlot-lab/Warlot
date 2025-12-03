module warlot::warlot_user;

use std::string::String;
use wal::wal::WAL;
use sui::{coin::{Self, Coin}};
use warlot::{
    warlot_system::SystemConfig,
    registry::Registry,
};


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



