module warlot::registry;
use std::string::String;
use sui::clock::Clock;
use warlot::{
    constants::Self, 
    event::Self, 
    drive_meta::Drive,
};

// this is the warlot user identifier
public struct Registry has key{
    id: UID,
    user: address,
    public_username: String,
    system_details: SystemDetail,
    api_properties: Api,
    created_at: u64,
    updated_at: u64,
    decay_at: u64
}

public struct Api has store{
    hashed_apikey: String, //this is the hashed api key of the user; it will be used by our publisher to identify the user that sent the blob
    hashed_encrypt_key: String, //also hahsed that will be used to encrypt the user's data
    warlot_sign_apikey: String,
}

public struct SystemDetail has store{
    user_object_id: ID,
    system_id: ID,
    project_holder: Option<ID>,
    drive_id: Option<ID>
}



// this is used to create a registry
public(package) fun create_registry( 
    public_username: String, 
    user_object_id: ID, 
    system_id: ID, 
    user_project_holder : Option<ID>,
    hashed_apikey: String, 
    hashed_encrypt_key: String, 
    warlot_sign_apikey: String,  
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
            project_holder: user_project_holder,
            drive_id,
        },
        api_properties: Api{
            hashed_apikey,
            hashed_encrypt_key,
            warlot_sign_apikey,
        },
        created_at: clock.timestamp_ms(),
        updated_at: clock.timestamp_ms(),
        decay_at: clock.timestamp_ms() + constants::api_decay(),
    };
    

    event::emit_new_user(user_object_id, object::id(&registry_state), ctx.sender());
    transfer::transfer(registry_state, ctx.sender());
}


public(package) fun update_api_key(
    registry: &mut Registry, 
    new_hashed_apikey: String, 
    new_warlot_sign_apikey: String,
    clock: &Clock
    ){
    registry.api_properties.hashed_apikey = new_hashed_apikey;
    registry.api_properties.warlot_sign_apikey = new_warlot_sign_apikey;
    registry.updated_at = clock.timestamp_ms();
}


public(package) fun update_username(registry: &mut Registry, new_username: String){
    registry.public_username = new_username;
}


// send funds for new apikey
public fun get_user(registry: &Registry): address{
    registry.user
}



public fun get_system(registry: &Registry): ID{
    registry.system_details.system_id
}