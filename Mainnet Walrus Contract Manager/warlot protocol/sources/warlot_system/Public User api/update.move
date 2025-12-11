module warlot::warlot_user;

use std::string::String;
use wal::wal::WAL;
use sui::{coin::{Self, Coin}};
use warlot::{
    warlot_system::SystemConfig,
    registry::Registry,
    vault
};


// add coin to the internal wallet
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



// Corrected update_username
public fun update_username(
    system_cfg: &mut SystemConfig, 
    registry: &mut Registry, 
    new_username: String,
    payment: &mut Coin<WAL>, 
    ctx: &mut TxContext,
) {
    // Verify System ID match
    assert!(object::id(system_cfg) == registry.get_system(), 9);

    // Take the specific fee amount
    let fee = system_cfg.cost_to_update_name();
    let paid_coin = coin::split(payment, fee, ctx);

    // Get the Vault and Deposit (The correct way to handle system funds now)
    let vault = system_cfg.get_vault_mut();
    vault::deposit(vault, paid_coin);

    // Update the name in the registry
    registry.update_username(new_username);
}