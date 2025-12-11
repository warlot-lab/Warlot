module warlot::register_user;

use std::string::String;
use sui::clock::Clock;
use warlot::{
    user_state::Self,
    warlot_system::SystemConfig,
};

/*
    The All key word in the funcyion in the register function is used to 
    is to indicate that that function will create all the object for all warlot application state 
    e.g, drve application state, dev applkication state,
*/

// create user internal object and public registry without warlot system permission
public fun all_register_user_publicly(
    system_cfg: &mut SystemConfig,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = user_state::create_user( public_username, object::id(system_cfg), clock, option::none(), ctx);
    system_cfg.add_user(new_user, ctx);
     
}



// create user with system permission 
public fun all_register_user_with_system_permission(
    system_cfg: &mut SystemConfig,
    public_username: String,
    clock: &Clock,
    ctx: &mut TxContext
    ){
    let new_user = user_state::create_user( public_username, object::id(system_cfg), clock, option::some(system_cfg.get_warlot_address()), ctx);
    system_cfg.add_user(new_user, ctx);
   
}

