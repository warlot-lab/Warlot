module warlot::registry;
use std::string::String;
use sui::clock::Clock;
use warlot::{
    constants::Self, 
    event::Self, 
};

// this is the warlot user identifier
public struct Registry has key{
    id: UID,
    user: address,
    public_username: String,
    system_details: SystemDetail,
    created_at: u64,
    updated_at: u64,
    decay_at: u64
}



public struct SystemDetail has store{
    user_object_id: ID,
    system_id: ID,
    project_holder: Option<ID>,
}



// this is used to create a registry
public(package) fun create_registry( 
    public_username: String, 
    user_object_id: ID, 
    system_id: ID, 
    project_holder : Option<ID>,
    clock: &Clock, 
    ctx: &mut TxContext
    ){

   let registry_state =  Registry{
        id: object::new(ctx),
        user: ctx.sender(),
        public_username,
        system_details: SystemDetail{
            user_object_id,
            system_id,
            project_holder,
            // drive_id,
        },
        created_at: clock.timestamp_ms(),
        updated_at: clock.timestamp_ms(),
        decay_at: clock.timestamp_ms() + constants::api_decay(),
    };
    

    event::emit_new_user(user_object_id, object::id(&registry_state), ctx.sender());
    transfer::transfer(registry_state, ctx.sender());
}




public(package) fun update_username(registry: &mut Registry, new_username: String){
    registry.public_username = new_username;
}

public(package) fun migrate_system(registry: &mut Registry, next_system_id: ID, clock: &Clock){
    registry.system_details.system_id = next_system_id;
    registry.updated_at = clock.timestamp_ms();
}


public fun get_user(registry: &Registry): address{
    registry.user
}



public fun get_system(registry: &Registry): ID{
    registry.system_details.system_id
}