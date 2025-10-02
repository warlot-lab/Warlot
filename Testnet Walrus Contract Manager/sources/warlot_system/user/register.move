module warlot::register_user;

use std::string::String;
use wal::wal::WAL;
use sui::{coin::{Self, Coin}, clock::Clock};
use warlot::{
    user_state::Self,
    warlot_system::SystemConfig,
    registry::Registry,
};

/*
    The All key word in the funcyion in the register function is used to 
    is to indicate that that function will create all the object for all warlot application state 
    e.g, drve application state, dev applkication state,
*/

// create user internal object and public registry without warlot system permission
public fun all_register_user_publicly(
    system_cfg: &mut SystemConfig,
    apikey: String,
    encrypt_key: String,
    warlot_sign_apikey: String,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = user_state::create_user( public_username, object::id(system_cfg), apikey, encrypt_key, warlot_sign_apikey, clock, option::none(), ctx);
    system_cfg.add_user(new_user, ctx);
    system_cfg.increase_user_count();   
}



// create user with system permission 
public fun all_register_user_with_system_permission(
    system_cfg: &mut SystemConfig,
    apikey: String,
    encrypt_key: String,
    warlot_sign_apikey: String,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = user_state::create_user( public_username, object::id(system_cfg), apikey, encrypt_key, warlot_sign_apikey, clock, option::some(system_cfg.get_warlot_address()), ctx);
    system_cfg.add_user(new_user, ctx);
    system_cfg.increase_user_count();   
}

public fun dev_register_user_publicly(){
    
}