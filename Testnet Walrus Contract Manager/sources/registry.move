module setandrenew::registry;
use std::string::String;
use sui::clock::Clock;
use setandrenew::constants::Self;

public struct Registry has key{
    id: UID,
    user: address,
    user_object_id: ID,
    created_at: u64,
    hashed_apikey: String, //this is the hashed api key of the user; it will be used by our publisher to identify the user that sent the blob
    hashed_encrypt_key: String, //also hahsed that will be used to encrypt the user's data
    warlot_sign_apikey: String,
    decay_at: u64
}



public(package) fun create_registry(user_object_id: ID, hashed_apikey: String, hashed_encrypt_key: String, warlot_sign_apikey: String,  clock: &Clock, ctx: &mut TxContext){
   let registry_state =  Registry{
        id: object::new(ctx),
        user: ctx.sender(),
        user_object_id,
        created_at: clock.timestamp_ms(),
        hashed_apikey,
        hashed_encrypt_key,
        warlot_sign_apikey,
        decay_at: clock.timestamp_ms() + constants::api_decay(),
    };

      transfer::transfer(registry_state, ctx.sender());
}

// public fun update_api_key(registry: &mut Registry, new_apikey: String){
//     registry.apikey = new_apikey;
// }


// send funds for new apikey


public fun get_user(registry: &Registry): address{
    registry.user
}

